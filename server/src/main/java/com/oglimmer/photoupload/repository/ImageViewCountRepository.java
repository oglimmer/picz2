/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.ImageViewCount;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface ImageViewCountRepository extends JpaRepository<ImageViewCount, Long> {

  /** Adds to one visitor's counters for one photo, creating the row on first sight. */
  @Modifying
  @Query(
      value =
          "INSERT INTO image_view_counts"
              + " (album_id, file_metadata_id, visitor_id, opens, walk_ins, first_seen_at,"
              + " last_seen_at)"
              + " VALUES (:albumId, :fileId, :visitorId, :opens, :walkIns, :now, :now)"
              + " ON DUPLICATE KEY UPDATE opens = opens + VALUES(opens),"
              + " walk_ins = walk_ins + VALUES(walk_ins), last_seen_at = VALUES(last_seen_at)",
      nativeQuery = true)
  void addViews(
      @Param("albumId") Long albumId,
      @Param("fileId") Long fileId,
      @Param("visitorId") String visitorId,
      @Param("opens") int opens,
      @Param("walkIns") int walkIns,
      @Param("now") Instant now);

  /**
   * Of the given ids, the ones a visitor of this album can actually see full screen: in the album,
   * a picture or a video (which steps over text cards, D86), and not {@code hidden} (D70). Anything
   * else in a beacon is dropped, so a made-up id cannot plant a count.
   */
  @Query(
      value =
          "SELECT f.id FROM file_metadata f WHERE f.album_id = :albumId AND f.id IN (:ids)"
              + " AND (f.mime_type LIKE 'image/%' OR f.mime_type LIKE 'video/%')"
              + " AND NOT EXISTS (SELECT 1 FROM image_tags it JOIN tags t ON t.id = it.tag_id"
              + " WHERE it.file_metadata_id = f.id AND t.name = :hidden)",
      nativeQuery = true)
  List<Long> findViewableIds(
      @Param("albumId") Long albumId,
      @Param("ids") Collection<Long> ids,
      @Param("hidden") String hiddenTag);

  /** How many photos a visitor of this album could look at — the "of N" in "looked at 12 of N". */
  @Query(
      value =
          "SELECT COUNT(*) FROM file_metadata f WHERE f.album_id = :albumId"
              + " AND (f.mime_type LIKE 'image/%' OR f.mime_type LIKE 'video/%')"
              + " AND NOT EXISTS (SELECT 1 FROM image_tags it JOIN tags t ON t.id = it.tag_id"
              + " WHERE it.file_metadata_id = f.id AND t.name = :hidden)",
      nativeQuery = true)
  long countViewable(@Param("albumId") Long albumId, @Param("hidden") String hiddenTag);

  /**
   * Album-wide totals. Rows whose photo has since moved to another album are left out, here and in
   * {@link #findTopImages}, so the two always agree.
   */
  @Query(
      value =
          "SELECT COUNT(DISTINCT v.file_metadata_id) AS imagesViewed,"
              + " COALESCE(SUM(v.opens), 0) AS opens, COALESCE(SUM(v.walk_ins), 0) AS walkIns"
              + " FROM image_view_counts v JOIN file_metadata f ON f.id = v.file_metadata_id"
              + " WHERE v.album_id = :albumId AND f.album_id = v.album_id",
      nativeQuery = true)
  ImageViewTotals findTotals(@Param("albumId") Long albumId);

  /** The most looked-at photos first: opens and walk-ins together, then id for a stable order. */
  @Query(
      value =
          "SELECT v.file_metadata_id AS fileId, f.public_token AS publicToken,"
              + " f.original_name AS originalName, f.mime_type AS mimeType,"
              + " SUM(v.opens) AS opens, SUM(v.walk_ins) AS walkIns, COUNT(*) AS viewers"
              + " FROM image_view_counts v JOIN file_metadata f ON f.id = v.file_metadata_id"
              + " WHERE v.album_id = :albumId AND f.album_id = v.album_id"
              + " GROUP BY v.file_metadata_id, f.public_token, f.original_name, f.mime_type"
              + " ORDER BY SUM(v.opens) + SUM(v.walk_ins) DESC, v.file_metadata_id ASC"
              + " LIMIT :limit",
      nativeQuery = true)
  List<ImageViewRow> findTopImages(@Param("albumId") Long albumId, @Param("limit") int limit);

  @Modifying
  @Query(value = "DELETE FROM image_view_counts WHERE album_id = :albumId", nativeQuery = true)
  void deleteByAlbumId(@Param("albumId") Long albumId);

  interface ImageViewTotals {
    Long getImagesViewed();

    Long getOpens();

    Long getWalkIns();
  }

  interface ImageViewRow {
    Long getFileId();

    String getPublicToken();

    String getOriginalName();

    String getMimeType();

    Long getOpens();

    Long getWalkIns();

    Long getViewers();
  }
}
