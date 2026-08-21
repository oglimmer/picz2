/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.GeocodingProperties;
import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.service.ReverseGeocodeService;
import jakarta.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Turns coordinates into place names for the gallery's "by day &amp; region" headings.
 *
 * <p>Batched by design: one album view asks about every region it drew in a single request, which
 * is one round trip instead of twenty and lets {@link ReverseGeocodeService} collapse duplicates
 * before any of them reach Apple.
 *
 * <p>A GET rather than a POST so the browser, and any proxy in front of us, can cache the answer —
 * a resolved place name is as immutable as data gets. Responses that still have unresolved points
 * are marked {@code no-store} instead, so a temporarily-unknown name is not frozen for a day.
 *
 * <p>Unauthenticated, because public share links group by region too. That makes it a geocoding
 * proxy in principle, so it is fenced: a cap on points per request, a per-IP request ceiling here,
 * and a pod-wide ceiling on calls that actually reach Apple in the service. Every one of those
 * fences degrades to "no name", never to an error — the UI simply shows coordinates.
 */
@Profile(Profiles.API)
@RestController
@RequiredArgsConstructor
@Slf4j
public class GeocodeController {

  private final ReverseGeocodeService geocodeService;
  private final GeocodingProperties properties;

  /** Per-IP fixed windows. Bounded by clearing, for the same reason the memory cache is. */
  private final Map<String, Window> clientWindows = new ConcurrentHashMap<>();

  private static final int MAX_TRACKED_CLIENTS = 10_000;

  private static final class Window {
    private volatile long startedAtMillis = System.currentTimeMillis();
    private final AtomicInteger count = new AtomicInteger();
  }

  /** One coordinate and the name we know for it; {@code name} is null when we know none. */
  public record PlaceResponse(double lat, double lng, String name) {}

  public record ReverseGeocodeResponse(List<PlaceResponse> places) {}

  /**
   * @param locations one or more {@code lat,lng} pairs in signed decimal degrees
   * @param language optional language tag for the names, e.g. {@code de-DE}
   */
  @GetMapping("/api/geocode/reverse")
  public ResponseEntity<?> reverse(
      @RequestParam(name = "loc") List<String> locations,
      @RequestParam(name = "lang", required = false) String language,
      HttpServletRequest request) {

    if (locations.size() > properties.getMaxPointsPerRequest()) {
      return ResponseEntity.badRequest()
          .body(Map.of("error", "At most " + properties.getMaxPointsPerRequest() + " loc values"));
    }

    List<ReverseGeocodeService.Point> points = new ArrayList<>(locations.size());
    for (String location : locations) {
      ReverseGeocodeService.Point point = parse(location);
      if (point == null) {
        return ResponseEntity.badRequest()
            .body(Map.of("error", "Malformed loc value: " + location));
      }
      points.add(point);
    }

    if (!withinClientLimit(clientIp(request))) {
      // 429 rather than a silent empty answer: this one is the caller's own doing, and the client
      // backs off instead of retrying. The UI keeps showing coordinates either way.
      return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
          .cacheControl(CacheControl.noStore())
          .body(Map.of("error", "Too many geocode requests"));
    }

    List<ReverseGeocodeService.ResolvedPlace> resolved = geocodeService.resolve(points, language);
    List<PlaceResponse> places =
        resolved.stream()
            .map(place -> new PlaceResponse(place.latitude(), place.longitude(), place.name()))
            .toList();
    boolean complete = places.stream().allMatch(place -> place.name() != null);

    return ResponseEntity.ok()
        .cacheControl(
            complete
                ? CacheControl.maxAge(java.time.Duration.ofDays(1)).cachePublic()
                : CacheControl.noStore())
        .body(new ReverseGeocodeResponse(places));
  }

  /** Parses {@code "50.047,8.574"}, returning null for anything that is not a real coordinate. */
  private ReverseGeocodeService.Point parse(String location) {
    if (location == null) {
      return null;
    }
    String[] parts = location.split(",");
    if (parts.length != 2) {
      return null;
    }
    try {
      double latitude = Double.parseDouble(parts[0].trim());
      double longitude = Double.parseDouble(parts[1].trim());
      if (!Double.isFinite(latitude) || !Double.isFinite(longitude)) {
        return null;
      }
      if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
        return null;
      }
      return new ReverseGeocodeService.Point(latitude, longitude);
    } catch (NumberFormatException e) {
      return null;
    }
  }

  private boolean withinClientLimit(String clientIp) {
    if (properties.getMaxRequestsPerMinutePerClient() <= 0) {
      return true;
    }
    if (clientWindows.size() > MAX_TRACKED_CLIENTS) {
      clientWindows.clear();
    }
    Window window = clientWindows.computeIfAbsent(clientIp, ip -> new Window());
    long now = System.currentTimeMillis();
    if (now - window.startedAtMillis >= 60_000L) {
      window.startedAtMillis = now;
      window.count.set(0);
    }
    return window.count.incrementAndGet() <= properties.getMaxRequestsPerMinutePerClient();
  }

  /** Same precedence the analytics path uses: the proxy headers first, the socket last. */
  private String clientIp(HttpServletRequest request) {
    String forwarded = request.getHeader("X-Forwarded-For");
    if (forwarded != null && !forwarded.isEmpty()) {
      return forwarded.split(",")[0].trim();
    }
    String realIp = request.getHeader("X-Real-IP");
    if (realIp != null && !realIp.isEmpty()) {
      return realIp;
    }
    return request.getRemoteAddr();
  }
}
