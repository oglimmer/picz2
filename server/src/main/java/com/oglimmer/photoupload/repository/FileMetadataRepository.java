/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface FileMetadataRepository extends JpaRepository<FileMetadata, Long> {

  Optional<FileMetadata> findByStoredFilename(String storedFilename);

  boolean existsByStoredFilename(String storedFilename);

  void deleteByStoredFilename(String storedFilename);

  List<FileMetadata> findAllByOrderByDisplayOrderAsc();

  // User-scoped queries via album relationship
  @Query(
      "SELECT f FROM FileMetadata f WHERE f.album.id = :albumId AND f.album.user.id = :userId ORDER BY f.displayOrder ASC")
  List<FileMetadata> findByAlbumIdAndUserIdOrderByDisplayOrderAsc(
      @Param("albumId") Long albumId, @Param("userId") Long userId);

  @Query(
      "SELECT DISTINCT f FROM FileMetadata f "
          + "LEFT JOIN FETCH f.imageTags it "
          + "LEFT JOIN FETCH it.tag "
          + "WHERE f.album.id = :albumId AND f.album.user.id = :userId "
          + "ORDER BY f.displayOrder ASC")
  List<FileMetadata> findByAlbumIdAndUserIdWithTagsOrderByDisplayOrderAsc(
      @Param("albumId") Long albumId, @Param("userId") Long userId);

  List<FileMetadata> findByAlbumIsNullOrderByDisplayOrderAsc();

  @Query("SELECT MAX(f.displayOrder) FROM FileMetadata f")
  Integer findMaxDisplayOrder();

  @Query(
      "SELECT MAX(f.displayOrder) FROM FileMetadata f WHERE f.album.id = :albumId AND f.album.user.id = :userId")
  Integer findMaxDisplayOrderByAlbumIdAndUserId(
      @Param("albumId") Long albumId, @Param("userId") Long userId);

  @Query("SELECT f FROM FileMetadata f WHERE f.id = :fileId AND f.album.user.id = :userId")
  Optional<FileMetadata> findByIdAndUserId(
      @Param("fileId") Long fileId, @Param("userId") Long userId);

  Optional<FileMetadata> findByPublicToken(String publicToken);

  @Query("SELECT f.id FROM FileMetadata f WHERE f.id IN :fileIds")
  List<Long> findExistingIds(@Param("fileIds") List<Long> fileIds);

  List<FileMetadata> findByAlbumShareTokenOrderByDisplayOrderAsc(String shareToken);

  @Query(
      "SELECT DISTINCT f FROM FileMetadata f "
          + "LEFT JOIN FETCH f.imageTags it "
          + "LEFT JOIN FETCH it.tag "
          + "LEFT JOIN FETCH f.album a "
          + "WHERE a.shareToken = :shareToken "
          + "ORDER BY f.displayOrder ASC")
  List<FileMetadata> findByAlbumShareTokenWithTagsOrderByDisplayOrderAsc(
      @Param("shareToken") String shareToken);

  long countByFilePath(String filePath);

  List<FileMetadata> findByChecksum(String checksum);

  @Query(
      "SELECT f FROM FileMetadata f WHERE f.checksum = :checksum AND f.album.id = :albumId AND f.album.user.id = :userId")
  Optional<FileMetadata> findByChecksumAndAlbumIdAndUserId(
      @Param("checksum") String checksum,
      @Param("albumId") Long albumId,
      @Param("userId") Long userId);

  @Query(
      "SELECT f.checksum FROM FileMetadata f WHERE f.album.user.id = :userId AND f.uploadedAt >= :uploadedAt AND f.checksum IS NOT NULL")
  List<String> findChecksumsByUserAndUploadedAtAfter(
      @Param("userId") Long userId, @Param("uploadedAt") java.time.Instant uploadedAt);

  // ContentId-based duplicate detection (for iOS and other sources that provide unique content IDs)
  @Query(
      "SELECT f FROM FileMetadata f WHERE f.contentId = :contentId AND f.album.user.id = :userId")
  List<FileMetadata> findByContentIdAndUserId(
      @Param("contentId") String contentId, @Param("userId") Long userId);

  // Find files in an album uploaded after a specific time (for subscription notifications)
  List<FileMetadata> findByAlbumAndUploadedAtAfter(Album album, Instant uploadedAt);

  /** Returns every non-null stored path across all five path columns in a single query. */
  @Query(
      value =
          "SELECT file_path FROM file_metadata WHERE file_path IS NOT NULL"
              + " UNION SELECT thumbnail_path FROM file_metadata WHERE thumbnail_path IS NOT NULL"
              + " UNION SELECT medium_path FROM file_metadata WHERE medium_path IS NOT NULL"
              + " UNION SELECT large_path FROM file_metadata WHERE large_path IS NOT NULL"
              + " UNION SELECT transcoded_video_path FROM file_metadata WHERE transcoded_video_path IS NOT NULL",
      nativeQuery = true)
  List<String> findAllStoredPaths();

  /**
   * Of the given file paths, return those still referenced by rows outside the named album.
   * Used during album deletion to skip physical-storage cleanup for files cross-album-shared via
   * {@code duplicateAlbum} (which copies metadata rows but reuses the same storage paths).
   */
  @Query(
      "SELECT DISTINCT f.filePath FROM FileMetadata f "
          + "WHERE f.album.id <> :albumId AND f.filePath IN :paths")
  List<String> findFilePathsSharedOutsideAlbum(
      @Param("albumId") Long albumId, @Param("paths") Collection<String> paths);

  /**
   * Bulk-delete every file_metadata row in the album in a single statement. SQL FK cascades take
   * care of {@code image_tags}, {@code processing_jobs}, and {@code slideshow_recording_images}.
   * Storage-layer cleanup must run before this — once the rows are gone, the keys cannot be found.
   */
  @Modifying(clearAutomatically = true)
  @Query("DELETE FROM FileMetadata f WHERE f.album.id = :albumId")
  int bulkDeleteByAlbumId(@Param("albumId") Long albumId);

  /**
   * Phase 6 / Gap 4-finish — rows eligible for original-purge by the nightly retention CronJob.
   * Conditions:
   *   - processing finished cleanly ({@code processing_status='DONE'}), so the worker did produce
   *     the derivatives we intend to keep serving from;
   *   - row is older than the cutoff (operator-configured retention window);
   *   - {@code file_path} is non-null (i.e. not already purged) AND points at an S3 originals key
   *     (legacy local-disk paths are out of scope — Gap 8 unmounted the PVC for the api/worker
   *     pods, but the retention runner deliberately does not delete bytes off any local disk);
   *   - {@code thumbnail_path IS NOT NULL} as a defensive sanity check that *some* derivative
   *     exists. {@code DONE} rows always have this in practice, but this protects against an
   *     anomalous row that was force-marked DONE without derivatives.
   *
   * <p>{@code LIMIT :maxRows} keeps a single CronJob firing bounded if the cutoff is misconfigured.
   */
  @Query(
      value =
          "SELECT * FROM file_metadata "
              + "WHERE processing_status = 'DONE' "
              + "AND uploaded_at < :cutoff "
              + "AND file_path IS NOT NULL "
              + "AND file_path LIKE 'originals/%' "
              + "AND thumbnail_path IS NOT NULL "
              + "ORDER BY uploaded_at ASC "
              + "LIMIT :maxRows",
      nativeQuery = true)
  List<FileMetadata> findRetentionPurgeCandidates(
      @Param("cutoff") Instant cutoff, @Param("maxRows") int maxRows);

  /**
   * Phase 5 follow-up — projection of every {@code originals/} S3 key currently referenced by a
   * row. The retention runner's orphan-detection pass set-diffs this against {@code listObjects}
   * over the {@code originals/} prefix to find keys that have no row pointing at them (post-finish
   * hook crash, multipart insert failure after PUT, etc.).
   *
   * <p>Projection-only; no entity hydration. Returning a {@code List} is fine — even at 100k+
   * rows the result is a few MiB of short strings.
   */
  @Query(
      "SELECT f.filePath FROM FileMetadata f "
          + "WHERE f.filePath IS NOT NULL AND f.filePath LIKE 'originals/%'")
  List<String> findAllOriginalsKeys();

  /**
   * Phase 4.5 follow-up — image-typed DONE rows missing at least one of the three image
   * derivatives. Used by the {@code REGEN_THUMBNAILS} admin endpoint to enqueue a regen job per
   * stranded asset (e.g. an old vipsthumbnail OOM that produced two of three sizes before
   * markFailed promoted the row to DONE-with-gaps).
   *
   * <p>Excludes assets that already have a {@code QUEUED}/{@code PROCESSING} job — repeat clicks
   * of the endpoint don't double-enqueue.
   *
   * <p>Returns IDs only (projection); the worker re-fetches the full entity inside its own TX.
   * Cap is applied at the SQL layer so a misconfigured caller can't load tens of thousands of
   * rows into the api pod's heap.
   */
  @Query(
      value =
          "SELECT fm.id FROM file_metadata fm "
              + "WHERE fm.processing_status = 'DONE' "
              + "AND fm.mime_type LIKE 'image/%' "
              + "AND (fm.thumbnail_path IS NULL OR fm.medium_path IS NULL OR fm.large_path IS NULL) "
              + "AND NOT EXISTS ("
              + "  SELECT 1 FROM processing_jobs pj "
              + "  WHERE pj.asset_id = fm.id AND pj.status IN ('QUEUED', 'PROCESSING')"
              + ") "
              + "ORDER BY fm.id ASC "
              + "LIMIT :maxRows",
      nativeQuery = true)
  List<Long> findMissingThumbnailIds(@Param("maxRows") int maxRows);
}
