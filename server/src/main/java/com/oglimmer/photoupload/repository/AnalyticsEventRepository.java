/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.AnalyticsEvent;
import java.time.Instant;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

@Repository
public interface AnalyticsEventRepository extends JpaRepository<AnalyticsEvent, Long> {

  List<AnalyticsEvent> findByAlbumOrderByCreatedAtDesc(Album album);

  List<AnalyticsEvent> findByAlbumAndCreatedAtBetweenOrderByCreatedAtDesc(
      Album album, Instant startDate, Instant endDate);

  @Query(
      """
    SELECT ae.eventType as eventType, COUNT(ae) as count
    FROM AnalyticsEvent ae
    WHERE ae.album = :album
    GROUP BY ae.eventType
    """)
  List<EventTypeCount> countEventsByTypeForAlbum(Album album);

  @Query(
      """
    SELECT ae.filterTag as filterTag, COUNT(ae) as count
    FROM AnalyticsEvent ae
    WHERE ae.album = :album AND ae.filterTag IS NOT NULL
    GROUP BY ae.filterTag
    ORDER BY COUNT(ae) DESC
    """)
  List<FilterTagCount> countEventsByFilterTagForAlbum(Album album);

  @Query(
      """
    SELECT COUNT(DISTINCT ae.visitorId)
    FROM AnalyticsEvent ae
    WHERE ae.album = :album
    """)
  Long countUniqueVisitorsByAlbum(Album album);

  interface EventTypeCount {
    String getEventType();

    Long getCount();
  }

  interface FilterTagCount {
    String getFilterTag();

    Long getCount();
  }
}
