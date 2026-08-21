/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import java.util.Set;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * Tuning for server-side reverse geocoding — turning a photo's coordinates into a place name via
 * the Apple Maps Server API.
 *
 * <p>The credentials are the MapKit ones ({@code maps.apple.*}); these settings only govern how
 * hard we lean on Apple. Defaults are deliberately conservative on the outbound side and generous
 * on the cache side, because a place name for a coordinate does not change and Apple's daily quota
 * does.
 */
@Configuration
@ConfigurationProperties(prefix = "maps.geocode")
@Data
public class GeocodingProperties {

  /** Master switch. Off means {@code /api/geocode/reverse} answers "unknown" for everything. */
  private boolean enabled = true;

  /** Base URL of the Apple Maps Server API. Overridable so tests can point at a local stub. */
  private String baseUrl = "https://maps-api.apple.com";

  /**
   * How far a cached point may be from the requested one and still be reused, in metres. A photo
   * region is 2 km across, so a name resolved 300 m away describes the same place — and this is
   * what keeps a whole city trip down to a handful of calls instead of one per cluster.
   */
  private int reuseRadiusMeters = 300;

  /** Points accepted in one request. Enough for a very long album, small enough to bound work. */
  private int maxPointsPerRequest = 60;

  /** How long before a "no name here" answer is worth asking about again. */
  private int negativeTtlDays = 7;

  /**
   * Fresh lookups allowed per minute across the whole pod. The cache absorbs normal browsing; this
   * is the ceiling that stops a scripted caller (or a bug) from spending the daily Apple quota.
   * Requests over the ceiling are answered "unknown", never queued.
   */
  private int maxLookupsPerMinute = 120;

  /** Lookups in flight at once. Apple is fast; this is about not pinning Tomcat threads. */
  private int maxConcurrentLookups = 4;

  /** Requests one client IP may make per minute. Same idea, one layer further out. */
  private int maxRequestsPerMinutePerClient = 60;

  /** HTTP timeout for a single Apple call. Short: the UI has coordinates to fall back on. */
  private int requestTimeoutSeconds = 5;

  /** Language used when the caller asks for one we do not offer, or asks for none. */
  private String defaultLanguage = "en";

  /**
   * Languages the cache is allowed to hold. Every extra language multiplies both the Apple calls
   * and the cache rows, and an open-ended list lets a caller force endless cache misses, so the
   * requested language is snapped into this set.
   */
  private Set<String> supportedLanguages = Set.of("en", "de", "fr", "es", "it");

  /** In-memory entries held in front of the database before the map is cleared. */
  private int memoryCacheSize = 20_000;
}
