/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.GeocodeCacheEntry;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface GeocodeCacheRepository extends JpaRepository<GeocodeCacheEntry, Long> {

  Optional<GeocodeCacheEntry> findByLatE4AndLngE4AndLanguage(
      Integer latE4, Integer lngE4, String language);

  /**
   * Every cached point of one language inside a bounding box, nearest-first by squared distance in
   * scaled units.
   *
   * <p>This is what turns "one Apple call per photo cluster" into "one Apple call per
   * neighbourhood": a cluster centre a few hundred metres from a point we already know reuses that
   * answer. The ordering is a plain arithmetic expression rather than a spatial function so it
   * works on any MariaDB build; the index on (language, lat_e4, lng_e4) makes the box scan cheap
   * and the rows inside it are few.
   *
   * <p>The caller only ever wants the nearest row, so it passes {@code Limit.of(1)} — the box is
   * small, but a dense city centre can still hold dozens of remembered points.
   *
   * <p>Longitude degrees shrink towards the poles, so the caller passes an already-widened
   * longitude half-width — the box is computed in metres before it is turned into degrees.
   */
  @Query(
      "SELECT g FROM GeocodeCacheEntry g"
          + " WHERE g.language = :language"
          + " AND g.latE4 BETWEEN :minLat AND :maxLat"
          + " AND g.lngE4 BETWEEN :minLng AND :maxLng"
          + " ORDER BY (g.latE4 - :latE4) * (g.latE4 - :latE4)"
          + " + (g.lngE4 - :lngE4) * (g.lngE4 - :lngE4) ASC")
  List<GeocodeCacheEntry> findNearby(
      @Param("language") String language,
      @Param("latE4") int latE4,
      @Param("lngE4") int lngE4,
      @Param("minLat") int minLat,
      @Param("maxLat") int maxLat,
      @Param("minLng") int minLng,
      @Param("maxLng") int maxLng,
      Limit limit);
}
