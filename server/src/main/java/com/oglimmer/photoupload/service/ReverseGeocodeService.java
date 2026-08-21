/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.GeocodingProperties;
import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.GeocodeCacheEntry;
import com.oglimmer.photoupload.repository.GeocodeCacheRepository;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.annotation.PreDestroy;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Limit;
import org.springframework.stereotype.Service;

/**
 * Turns coordinates into place names, asking Apple as rarely as it possibly can.
 *
 * <p>A gallery grouped by region asks for a name per region, every time somebody opens the album,
 * from every browser. Apple's answer for a spot never changes, so almost all of those questions
 * have been answered before. The lookup walks four steps and stops at the first that answers:
 *
 * <ol>
 *   <li>the in-memory map — same pod, same coordinate, microseconds;
 *   <li>the {@code geocode_cache} row for the exact snapped point — shared by every pod, survives
 *       restarts and deploys;
 *   <li>the nearest cached point within {@code reuse-radius-meters} — a region is 2 km across, so a
 *       name resolved 300 m away is the same name, and one row can answer for a whole village;
 *   <li>Apple, rate-limited, single-flighted, and written back so nobody asks again.
 * </ol>
 *
 * <p>Nothing here ever fails a request. Throttled, misconfigured, offline, no name at that spot —
 * all come back as "no name", and the caller shows coordinates instead. The one thing this class
 * will not do is make the user wait: lookups that run past the request's budget keep going in the
 * background and land in the cache for the next visitor.
 */
@Service
@Profile(Profiles.API)
@Slf4j
public class ReverseGeocodeService {

  /**
   * How long a batch may spend waiting on fresh lookups before it answers with what it has. Kept
   * near the single-call timeout: the point is that a cold album still paints promptly.
   */
  private static final Duration BATCH_BUDGET = Duration.ofSeconds(4);

  /**
   * Metres per degree of latitude. Good to ~0.3% anywhere, which a cache box does not care about.
   */
  private static final double METERS_PER_DEGREE_LAT = 111_320.0;

  /** Degrees are stored scaled by this so the cache key is an integer pair. 10^-4° ≈ 11 m. */
  private static final double SCALE = 10_000.0;

  /**
   * Version of {@link #labelFor}. Bump it whenever the rule changes: cached rows written by an
   * older rule are then treated as stale and re-resolved as people browse, rather than living on as
   * names nobody would produce today.
   *
   * <p>Version 2 is the first that reads Apple's {@code structuredAddress}. Version 1 could only
   * see the country, so every region in a country was labelled after the country.
   */
  private static final int LABEL_VERSION = 2;

  private final GeocodeCacheRepository repository;
  private final AppleMapsGeocodeClient client;
  private final AppleMapsTokenService tokenService;
  private final GeocodingProperties properties;
  private final MeterRegistry meterRegistry;

  private final Map<PointKey, Optional<String>> memoryCache = new ConcurrentHashMap<>();
  private final Map<PointKey, CompletableFuture<Optional<String>>> inFlight =
      new ConcurrentHashMap<>();
  private final ExecutorService lookupExecutor;

  // Fixed-window limiter on outbound calls. Not a token bucket on purpose: the window only has to
  // stop a runaway, and an AtomicLong pair does that without a scheduler or a lock.
  private final AtomicLong windowStartedAtMillis = new AtomicLong(System.currentTimeMillis());
  private final AtomicInteger lookupsThisWindow = new AtomicInteger();

  public ReverseGeocodeService(
      GeocodeCacheRepository repository,
      AppleMapsGeocodeClient client,
      AppleMapsTokenService tokenService,
      GeocodingProperties properties,
      MeterRegistry meterRegistry) {
    this.repository = repository;
    this.client = client;
    this.tokenService = tokenService;
    this.properties = properties;
    this.meterRegistry = meterRegistry;
    ThreadFactory factory =
        runnable -> {
          Thread thread = new Thread(runnable, "geocode-lookup");
          thread.setDaemon(true);
          return thread;
        };
    this.lookupExecutor =
        Executors.newFixedThreadPool(Math.max(1, properties.getMaxConcurrentLookups()), factory);
  }

  @PreDestroy
  void shutdown() {
    lookupExecutor.shutdownNow();
  }

  /** A coordinate to look up, in signed decimal degrees (WGS 84). */
  public record Point(double latitude, double longitude) {}

  /** What the endpoint answers per requested point; {@code name} is null when nothing is known. */
  public record ResolvedPlace(double latitude, double longitude, String name) {}

  /** Snapped cache key: integer degrees × 10^4 plus the language the name is in. */
  private record PointKey(int latE4, int lngE4, String language) {}

  /** True when a lookup could actually happen — used by {@code /api/capabilities}. */
  public boolean isEnabled() {
    return properties.isEnabled() && tokenService.isEnabled();
  }

  /**
   * Resolves a batch of coordinates.
   *
   * <p>Duplicate points (after snapping) are collapsed, so a caller that sends the same spot twenty
   * times costs exactly one lookup. Cached points return immediately; the rest are looked up
   * concurrently, capped by {@code max-concurrent-lookups}, and whatever has not landed inside
   * {@link #BATCH_BUDGET} comes back as "no name" while the lookup continues in the background.
   *
   * @param points requested coordinates, in the caller's order
   * @param requestedLanguage a language tag, e.g. "de-DE"; snapped to a supported one
   * @return one entry per requested point, in the same order
   */
  public List<ResolvedPlace> resolve(List<Point> points, String requestedLanguage) {
    String language = normaliseLanguage(requestedLanguage);
    if (points.isEmpty()) {
      return List.of();
    }

    // Distinct snapped keys, in first-seen order, so the work below is per *place*, not per point.
    Map<PointKey, Point> distinct = new LinkedHashMap<>();
    List<PointKey> keysInOrder = new ArrayList<>(points.size());
    for (Point point : points) {
      PointKey key = keyFor(point, language);
      keysInOrder.add(key);
      distinct.putIfAbsent(key, point);
    }

    Map<PointKey, String> resolved = new ConcurrentHashMap<>();
    List<CompletableFuture<?>> pending = new ArrayList<>();

    for (Map.Entry<PointKey, Point> entry : distinct.entrySet()) {
      PointKey key = entry.getKey();
      Optional<String> cached = fromCache(key);
      if (cached != null) {
        cached.ifPresent(name -> resolved.put(key, name));
        continue;
      }
      if (!isEnabled() || !allowLookup()) {
        continue;
      }
      pending.add(
          lookupAsync(key, entry.getValue())
              .thenAccept(name -> name.ifPresent(value -> resolved.put(key, value))));
    }

    if (!pending.isEmpty()) {
      try {
        CompletableFuture.allOf(pending.toArray(new CompletableFuture[0]))
            .get(BATCH_BUDGET.toMillis(), TimeUnit.MILLISECONDS);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
      } catch (Exception e) {
        // Timeout or a failed lookup: answer with what is known. The unfinished lookups keep
        // running and populate the cache, so the next request for this album is instant.
        log.debug("🗺️ Geocode batch answered before every lookup finished: {}", e.toString());
      }
    }

    List<ResolvedPlace> answer = new ArrayList<>(points.size());
    for (int i = 0; i < points.size(); i++) {
      Point point = points.get(i);
      answer.add(
          new ResolvedPlace(point.latitude(), point.longitude(), resolved.get(keysInOrder.get(i))));
    }
    return answer;
  }

  /**
   * Reads the three cache layers.
   *
   * @return null when nothing is cached (the caller must look it up), an empty Optional when the
   *     cache remembers that this spot has no name, or the name
   */
  private Optional<String> fromCache(PointKey key) {
    Optional<String> memory = memoryCache.get(key);
    if (memory != null) {
      count("geocode.cache", "layer", "memory");
      return memory;
    }

    Optional<GeocodeCacheEntry> exact =
        repository.findByLatE4AndLngE4AndLanguage(key.latE4(), key.lngE4(), key.language());
    if (exact.isPresent() && isFresh(exact.get())) {
      count("geocode.cache", "layer", "database");
      return remember(key, exact.get().getPlaceName());
    }

    Optional<GeocodeCacheEntry> nearby = findNearby(key);
    if (nearby.isPresent()) {
      count("geocode.cache", "layer", "nearby");
      return remember(key, nearby.get().getPlaceName());
    }
    return null;
  }

  /** The nearest remembered point inside the reuse radius, if there is one with a real name. */
  private Optional<GeocodeCacheEntry> findNearby(PointKey key) {
    int radius = properties.getReuseRadiusMeters();
    if (radius <= 0) {
      return Optional.empty();
    }
    double latDegrees = radius / METERS_PER_DEGREE_LAT;
    // Longitude degrees are shorter away from the equator, so the box has to be wider there to
    // cover the same distance on the ground. Clamped because cos() heads to zero at the poles.
    double cos = Math.max(0.01, Math.cos(Math.toRadians(key.latE4() / SCALE)));
    double lngDegrees = latDegrees / cos;
    int latDelta = (int) Math.ceil(latDegrees * SCALE);
    int lngDelta = (int) Math.ceil(lngDegrees * SCALE);
    List<GeocodeCacheEntry> hits =
        repository.findNearby(
            key.language(),
            key.latE4(),
            key.lngE4(),
            key.latE4() - latDelta,
            key.latE4() + latDelta,
            key.lngE4() - lngDelta,
            key.lngE4() + lngDelta,
            Limit.of(1));
    // A neighbouring *negative* row says nothing about this point — the sea 300 m away does not
    // mean the village here has no name — so only a real name is reused, and only one written by
    // the current rule (otherwise stale labels would spread sideways instead of dying out).
    return hits.stream()
        .filter(hit -> hit.getPlaceName() != null && hit.getResolverVersion() >= LABEL_VERSION)
        .findFirst();
  }

  /**
   * Whether a cached row may still be used: it must come from the current label rule, and a
   * negative entry must not have gone stale. A name from the current rule never expires.
   */
  private boolean isFresh(GeocodeCacheEntry entry) {
    if (entry.getResolverVersion() < LABEL_VERSION) {
      return false;
    }
    if (entry.getPlaceName() != null) {
      return true;
    }
    Instant cutoff = Instant.now().minus(Duration.ofDays(properties.getNegativeTtlDays()));
    return entry.getResolvedAt() != null && entry.getResolvedAt().isAfter(cutoff);
  }

  /**
   * Starts (or joins) the single lookup for this key.
   *
   * <p>Twenty visitors opening the same public album at the same moment produce one Apple call, not
   * twenty: the first puts a future in {@link #inFlight} and everyone else waits on it.
   */
  private CompletableFuture<Optional<String>> lookupAsync(PointKey key, Point point) {
    return inFlight.computeIfAbsent(
        key,
        k -> {
          CompletableFuture<Optional<String>> future =
              CompletableFuture.supplyAsync(() -> lookup(k, point), lookupExecutor);
          future.whenComplete((result, error) -> inFlight.remove(k));
          return future;
        });
  }

  /**
   * The actual Apple call plus the write-back. Runs on the lookup pool, never on a Tomcat thread.
   */
  private Optional<String> lookup(PointKey key, Point point) {
    Optional<AppleMapsGeocodeClient.ApplePlace> place =
        client.reverseGeocode(point.latitude(), point.longitude(), key.language());
    String name = place.map(this::labelFor).filter(value -> !value.isBlank()).orElse(null);
    count("geocode.lookup", "result", name == null ? "empty" : "resolved");
    persist(key, place.orElse(null), name);
    return remember(key, name);
  }

  /**
   * The heading for a photo region, coarsening only as far as it has to.
   *
   * <p>A town name is what people recognise, so the city wins. Landscape photos often sit in no
   * town at all, and there Apple's area of interest ("Banff National Park") is far better than the
   * province. Only when nothing local is known does this fall back to the state or the country —
   * and then it says both ("Alberta, Canada"), because a bare province name is easy to misread.
   *
   * <p>The district is deliberately not preferred over the city: a region is up to 2 km across, so
   * naming it after whichever neighbourhood its centre landed in is more precise than it is true.
   */
  private String labelFor(AppleMapsGeocodeClient.ApplePlace place) {
    String city = place.cityName();
    if (city != null) {
      return city;
    }
    String areaOfInterest = place.areaOfInterestName();
    if (areaOfInterest != null) {
      return areaOfInterest;
    }
    String district = place.districtName();
    if (district != null) {
      return district;
    }
    String state = place.stateName();
    String country = blankToNull(place.country());
    if (state != null) {
      return country == null || country.equals(state) ? state : state + ", " + country;
    }
    if (country != null) {
      return country;
    }
    return blankToNull(place.name()) == null ? "" : place.name().trim();
  }

  private static String blankToNull(String value) {
    return value == null || value.isBlank() ? null : value.trim();
  }

  private void persist(PointKey key, AppleMapsGeocodeClient.ApplePlace place, String name) {
    GeocodeCacheEntry entry =
        repository
            .findByLatE4AndLngE4AndLanguage(key.latE4(), key.lngE4(), key.language())
            .orElseGet(GeocodeCacheEntry::new);
    entry.setLatE4(key.latE4());
    entry.setLngE4(key.lngE4());
    entry.setLanguage(key.language());
    entry.setPlaceName(truncate(name));
    if (place != null) {
      // The resolved components, not the raw fields: Apple puts these inside structuredAddress on
      // the Server API, and storing what we actually read is what makes a later rule change cheap.
      entry.setLocality(truncate(place.cityName()));
      entry.setSubLocality(truncate(place.districtName()));
      entry.setAdministrativeArea(truncate(place.stateName()));
      entry.setCountry(truncate(place.country()));
      entry.setCountryCode(place.countryCode() == null ? null : truncate(place.countryCode(), 8));
    }
    entry.setResolverVersion(LABEL_VERSION);
    entry.setResolvedAt(Instant.now());
    entry.setHitCount(entry.getHitCount() + 1);
    try {
      repository.save(entry);
    } catch (DataIntegrityViolationException e) {
      // Another pod wrote the same point first. Its answer is as good as ours — nothing to do.
      log.debug("🗺️ Geocode cache row already written by another pod for {}", key);
    }
  }

  /**
   * Puts a result in the memory layer and hands it back. Clears the map when it outgrows its cap.
   */
  private Optional<String> remember(PointKey key, String name) {
    if (memoryCache.size() >= properties.getMemoryCacheSize()) {
      // Deliberately a clear, not an eviction policy: the database is the real cache, so the worst
      // this costs is a few DB reads while the hot set builds up again.
      log.info("🗺️ Geocode memory cache full ({} entries) — clearing", memoryCache.size());
      memoryCache.clear();
    }
    Optional<String> value = Optional.ofNullable(name);
    memoryCache.put(key, value);
    return value;
  }

  /** Fixed-window check on outbound lookups. False means "answer without a name this time". */
  private boolean allowLookup() {
    long now = System.currentTimeMillis();
    long windowStart = windowStartedAtMillis.get();
    if (now - windowStart >= 60_000L && windowStartedAtMillis.compareAndSet(windowStart, now)) {
      lookupsThisWindow.set(0);
    }
    if (lookupsThisWindow.incrementAndGet() > properties.getMaxLookupsPerMinute()) {
      count("geocode.lookup", "result", "throttled");
      return false;
    }
    return true;
  }

  private PointKey keyFor(Point point, String language) {
    return new PointKey(
        (int) Math.round(point.latitude() * SCALE),
        (int) Math.round(point.longitude() * SCALE),
        language);
  }

  /**
   * Snaps a requested language onto the supported set, because every distinct language is its own
   * set of Apple calls and its own set of cache rows.
   */
  private String normaliseLanguage(String requested) {
    if (requested == null || requested.isBlank()) {
      return properties.getDefaultLanguage();
    }
    String base = requested.trim().toLowerCase(Locale.ROOT).split("[-_]")[0];
    return properties.getSupportedLanguages().contains(base)
        ? base
        : properties.getDefaultLanguage();
  }

  private String truncate(String value) {
    return truncate(value, 255);
  }

  private String truncate(String value, int max) {
    if (value == null) {
      return null;
    }
    String trimmed = value.trim();
    return trimmed.length() <= max ? trimmed : trimmed.substring(0, max);
  }

  private void count(String metric, String tagKey, String tagValue) {
    meterRegistry.counter(metric, tagKey, tagValue).increment();
  }
}
