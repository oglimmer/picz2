/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.oglimmer.photoupload.config.GeocodingProperties;
import com.oglimmer.photoupload.config.Profiles;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpHeaders;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * Thin client for the Apple Maps Server API's {@code /v1/reverseGeocode}.
 *
 * <p>Apple's REST API does not take the signing JWT directly: the JWT is exchanged once at {@code
 * /v1/token} for a short-lived access token, and that access token authorises the actual calls.
 * Both are cached here — a token exchange per geocode would double the request count for nothing.
 *
 * <p>This class knows nothing about caching place names or rate limits; it is the part that talks
 * to Apple and nothing else. {@link ReverseGeocodeService} owns the policy.
 */
@Component
@Profile(Profiles.API)
@Slf4j
public class AppleMapsGeocodeClient {

  /** Renew the access token this long before Apple's stated expiry. */
  private static final long TOKEN_MARGIN_SECONDS = 60;

  private final AppleMapsTokenService tokenService;
  private final GeocodingProperties properties;
  private final RestClient restClient;

  private volatile String accessToken;
  private volatile Instant accessTokenUntil = Instant.EPOCH;

  public AppleMapsGeocodeClient(
      AppleMapsTokenService tokenService, GeocodingProperties properties) {
    this.tokenService = tokenService;
    this.properties = properties;
    Duration timeout = Duration.ofSeconds(properties.getRequestTimeoutSeconds());
    SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
    factory.setConnectTimeout(timeout);
    factory.setReadTimeout(timeout);
    // Built here rather than injected: Boot 4 moved the auto-configured RestClient.Builder bean
    // into the spring-boot-restclient starter, which this app does not depend on, so asking for
    // one fails the whole context at startup. Nothing is lost — this client wants its own short
    // timeouts and its own base URL, so it would have cloned the shared builder anyway.
    this.restClient =
        RestClient.builder().requestFactory(factory).baseUrl(properties.getBaseUrl()).build();
  }

  /** Apple's reply to {@code /v1/token}. */
  @JsonIgnoreProperties(ignoreUnknown = true)
  record TokenResponse(String accessToken, Long expiresInSeconds) {}

  /**
   * One place from Apple; every field is optional, and mid-ocean most of them are absent.
   *
   * <p>The city, district and state live inside {@link StructuredAddress}, <em>not</em> at the top
   * level — that is the one real difference from MapKit JS's flat {@code Place}, and getting it
   * wrong is invisible rather than loud: the country still parses, so every coordinate in a country
   * comes back named after the country. The flat fields are still declared and still preferred when
   * present, so both shapes work.
   */
  @JsonIgnoreProperties(ignoreUnknown = true)
  public record ApplePlace(
      String name,
      String locality,
      String subLocality,
      String administrativeArea,
      String country,
      String countryCode,
      StructuredAddress structuredAddress) {

    /** Convenience constructor for the flat shape, used by tests. */
    public ApplePlace(
        String name,
        String locality,
        String subLocality,
        String administrativeArea,
        String country,
        String countryCode) {
      this(name, locality, subLocality, administrativeArea, country, countryCode, null);
    }

    /** City or town, e.g. "Banff". */
    public String cityName() {
      return firstSet(locality, structuredAddress == null ? null : structuredAddress.locality());
    }

    /** District inside a city, e.g. "Kreuzberg". */
    public String districtName() {
      return firstSet(
          subLocality, structuredAddress == null ? null : structuredAddress.subLocality());
    }

    /** State, province or federal state, e.g. "Alberta". */
    public String stateName() {
      return firstSet(
          administrativeArea,
          structuredAddress == null ? null : structuredAddress.administrativeArea());
    }

    /**
     * A named place with no town of its own — "Banff National Park", "Yosemite Valley". Exactly
     * what a landscape photo taken nowhere near a settlement should be labelled with.
     */
    public String areaOfInterestName() {
      if (structuredAddress == null) {
        return null;
      }
      String area = firstOf(structuredAddress.areasOfInterest());
      return area != null ? area : firstOf(structuredAddress.dependentLocalities());
    }

    private static String firstSet(String preferred, String fallback) {
      if (preferred != null && !preferred.isBlank()) return preferred.trim();
      if (fallback != null && !fallback.isBlank()) return fallback.trim();
      return null;
    }

    private static String firstOf(List<String> values) {
      if (values == null) {
        return null;
      }
      return values.stream()
          .filter(value -> value != null && !value.isBlank())
          .findFirst()
          .orElse(null);
    }
  }

  /** Apple's address breakdown. Only the parts a place *name* can come from are declared. */
  @JsonIgnoreProperties(ignoreUnknown = true)
  public record StructuredAddress(
      String administrativeArea,
      String locality,
      String subLocality,
      List<String> areasOfInterest,
      List<String> dependentLocalities) {}

  @JsonIgnoreProperties(ignoreUnknown = true)
  record ReverseGeocodeResponse(List<ApplePlace> results) {}

  /**
   * Asks Apple what is at a coordinate.
   *
   * @param latitude signed decimal degrees, WGS 84
   * @param longitude signed decimal degrees, WGS 84
   * @param language short language tag ("en", "de")
   * @return the best place Apple returned, empty when it returned none or the call failed — the
   *     caller cannot tell the difference and does not need to, because both mean "no name to
   *     show". A failure is logged here; an empty result is normal and is not.
   */
  public Optional<ApplePlace> reverseGeocode(double latitude, double longitude, String language) {
    try {
      String token = accessToken();
      ReverseGeocodeResponse response =
          restClient
              .get()
              .uri(
                  builder ->
                      builder
                          .path("/v1/reverseGeocode")
                          .queryParam("loc", latitude + "," + longitude)
                          .queryParam("lang", language)
                          .build())
              .header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
              .retrieve()
              .body(ReverseGeocodeResponse.class);
      if (response == null || response.results() == null || response.results().isEmpty()) {
        return Optional.empty();
      }
      return Optional.of(response.results().get(0));
    } catch (RestClientException e) {
      // 401 usually means the access token was revoked early; drop it so the next call
      // re-exchanges.
      accessTokenUntil = Instant.EPOCH;
      log.warn(
          "🗺️ Apple reverse geocode failed for {},{}: {}", latitude, longitude, e.getMessage());
      return Optional.empty();
    } catch (IllegalStateException e) {
      log.warn("🗺️ Apple reverse geocode skipped: {}", e.getMessage());
      return Optional.empty();
    }
  }

  /**
   * A valid access token, exchanging the signed JWT for a new one when the cached token is gone or
   * nearly expired.
   */
  private String accessToken() {
    String current = accessToken;
    if (current != null && Instant.now().isBefore(accessTokenUntil)) {
      return current;
    }
    synchronized (this) {
      if (accessToken != null && Instant.now().isBefore(accessTokenUntil)) {
        return accessToken;
      }
      TokenResponse response =
          restClient
              .get()
              .uri("/v1/token")
              .header(HttpHeaders.AUTHORIZATION, "Bearer " + tokenService.serverToken())
              .retrieve()
              .body(TokenResponse.class);
      if (response == null || response.accessToken() == null) {
        throw new IllegalStateException("Apple Maps token exchange returned no access token");
      }
      long ttl = response.expiresInSeconds() == null ? 1800L : response.expiresInSeconds();
      accessToken = response.accessToken();
      accessTokenUntil = Instant.now().plusSeconds(Math.max(1, ttl - TOKEN_MARGIN_SECONDS));
      log.debug("🗺️ Apple Maps access token refreshed, valid {}s", ttl);
      return accessToken;
    }
  }
}
