/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * One remembered answer from the Apple Maps Server API: the place name at a coordinate, in one
 * language.
 *
 * <p>The coordinate is stored snapped and scaled — degrees × 10<sup>4</sup>, about 11 m — so the
 * key is an integer pair rather than a float pair, and so that the same spot asked for twice with
 * slightly different decimals lands on the same row.
 *
 * <p>A row with a null {@link #placeName} is not a failure: it records that Apple was asked and had
 * no name for that spot, which is worth remembering exactly as much as a name is.
 */
@Entity
@Table(
    name = "geocode_cache",
    uniqueConstraints = {
      @UniqueConstraint(
          name = "uk_geocode_cache_point",
          columnNames = {"lat_e4", "lng_e4", "language"})
    })
@Data
@NoArgsConstructor
@AllArgsConstructor
public class GeocodeCacheEntry {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "lat_e4", nullable = false)
  private Integer latE4;

  @Column(name = "lng_e4", nullable = false)
  private Integer lngE4;

  @Column(name = "language", nullable = false, length = 16)
  private String language;

  @Column(name = "place_name", length = 255)
  private String placeName;

  @Column(name = "locality", length = 255)
  private String locality;

  @Column(name = "sub_locality", length = 255)
  private String subLocality;

  @Column(name = "administrative_area", length = 255)
  private String administrativeArea;

  @Column(name = "country", length = 255)
  private String country;

  @Column(name = "country_code", length = 8)
  private String countryCode;

  @Column(name = "resolved_at", nullable = false)
  private Instant resolvedAt;

  @Column(name = "hit_count", nullable = false)
  private long hitCount;

  /**
   * Which version of the label rule wrote {@link #placeName}. Rows below the service's current
   * version are re-resolved on next use — see V39 for why that is not a one-off cleanup script.
   */
  @Column(name = "resolver_version", nullable = false)
  private int resolverVersion;

  @PrePersist
  void onPersist() {
    if (resolvedAt == null) {
      resolvedAt = Instant.now();
    }
  }
}
