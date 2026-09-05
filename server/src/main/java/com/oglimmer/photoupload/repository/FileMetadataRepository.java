/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

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

  @Query(
      "SELECT MAX(f.displayOrder) FROM FileMetadata f WHERE f.album.id = :albumId AND f.album.user.id = :userId")
  Integer findMaxDisplayOrderByAlbumIdAndUserId(
      @Param("albumId") Long albumId, @Param("userId") Long userId);

  @Query("SELECT f FROM FileMetadata f WHERE f.id = :fileId AND f.album.user.id = :userId")
  Optional<FileMetadata> findByIdAndUserId(
      @Param("fileId") Long fileId, @Param("userId") Long userId);

  Optional<FileMetadata> findByPublicToken(String publicToken);

  /**
   * Of the given ids, those that exist and belong to {@code userId}. The reorder endpoint compares
   * the size of this list with the size of its input, so a foreign id fails the same way a missing
   * one does.
   */
  @Query("SELECT f.id FROM FileMetadata f WHERE f.id IN :fileIds AND f.album.user.id = :userId")
  List<Long> findExistingIdsForUser(
      @Param("fileIds") List<Long> fileIds, @Param("userId") Long userId);

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

  /**
   * Rows of {@code userId} whose original bytes hash to {@code checksum}, in any of their albums.
   *
   * <p>Exists for the TUS path, which has no equivalent of the multipart flow's {@link
   * #findByChecksum(String)} sweep. Scoped to the user on purpose: {@code findByChecksum} is
   * account-blind, and a hook that rejected an upload because a *different* account holds the same
   * bytes would both leak that fact and lose the user's photo.
   *
   * <p>The case this closes: the same iCloud photo synced from an iPhone and an iPad. Each device
   * mints its own {@code PHAsset.localIdentifier}, so the {@code contentId} check cannot see the
   * pair — but {@code PHAssetResourceManager} writes the untouched original resource on both, so
   * the SHA-256 matches.
   */
  @Query("SELECT f FROM FileMetadata f WHERE f.checksum = :checksum AND f.album.user.id = :userId")
  List<FileMetadata> findByChecksumAndUserId(
      @Param("checksum") String checksum, @Param("userId") Long userId);

  @Query(
      "SELECT f.checksum FROM FileMetadata f WHERE f.album.user.id = :userId AND f.uploadedAt >= :uploadedAt AND f.checksum IS NOT NULL")
  List<String> findChecksumsByUserAndUploadedAtAfter(
      @Param("userId") Long userId, @Param("uploadedAt") java.time.Instant uploadedAt);

  /**
   * ContentIds this user has uploaded since {@code uploadedAt}.
   *
   * <p>Feeds the client's post-reinstall reconciliation. Checksum reconciliation cannot do this
   * job: the client matches a returned checksum against its own local checksum→asset map, which is
   * empty on a fresh install, so it marks nothing. A contentId is the client's own identifier for
   * the source asset (on iOS, {@code PHAsset.localIdentifier}) and belongs to the photo library
   * rather than to the app, so it still matches after a reinstall.
   */
  @Query(
      "SELECT f.contentId FROM FileMetadata f WHERE f.album.user.id = :userId AND f.uploadedAt >= :uploadedAt AND f.contentId IS NOT NULL")
  List<String> findContentIdsByUserAndUploadedAtAfter(
      @Param("userId") Long userId, @Param("uploadedAt") java.time.Instant uploadedAt);

  // ContentId-based duplicate detection (for iOS and other sources that provide unique content IDs)
  @Query(
      "SELECT f FROM FileMetadata f WHERE f.contentId = :contentId AND f.album.user.id = :userId")
  List<FileMetadata> findByContentIdAndUserId(
      @Param("contentId") String contentId, @Param("userId") Long userId);

  /**
   * The same set, narrowed to files whose album sits on one storage backend. The orphan sweep runs
   * per backend now: a key that is missing from the DB is only garbage relative to the bucket it
   * was found in, and comparing one bucket's keys against every album's paths would delete a user's
   * objects the moment two backends happened to hold the same key.
   */
  @Query(
      value =
          "SELECT f.file_path FROM file_metadata f JOIN albums a ON a.id = f.album_id"
              + " WHERE a.storage_backend_id = :backendId AND f.file_path IS NOT NULL"
              + " UNION SELECT f.thumbnail_path FROM file_metadata f JOIN albums a ON a.id = f.album_id"
              + " WHERE a.storage_backend_id = :backendId AND f.thumbnail_path IS NOT NULL"
              + " UNION SELECT f.medium_path FROM file_metadata f JOIN albums a ON a.id = f.album_id"
              + " WHERE a.storage_backend_id = :backendId AND f.medium_path IS NOT NULL"
              + " UNION SELECT f.large_path FROM file_metadata f JOIN albums a ON a.id = f.album_id"
              + " WHERE a.storage_backend_id = :backendId AND f.large_path IS NOT NULL"
              + " UNION SELECT f.transcoded_video_path FROM file_metadata f JOIN albums a ON a.id = f.album_id"
              + " WHERE a.storage_backend_id = :backendId AND f.transcoded_video_path IS NOT NULL",
      nativeQuery = true)
  List<String> findStoredPathsByStorageBackend(@Param("backendId") Long backendId);

  /**
   * Of the given file paths, return those still referenced by rows outside the named album. Used
   * during album deletion to skip physical-storage cleanup for files cross-album-shared via {@code
   * duplicateAlbum} (which copies metadata rows but reuses the same storage paths).
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
   * Conditions: - processing finished cleanly ({@code processing_status='DONE'}), so the worker did
   * produce the derivatives we intend to keep serving from; - row is older than the cutoff
   * (operator-configured retention window); - {@code file_path} is non-null (i.e. not already
   * purged) AND points at an S3 originals key (legacy local-disk paths are out of scope — Gap 8
   * unmounted the PVC for the api/worker pods, but the retention runner deliberately does not
   * delete bytes off any local disk); - {@code thumbnail_path IS NOT NULL} as a defensive sanity
   * check that *some* derivative exists. {@code DONE} rows always have this in practice, but this
   * protects against an anomalous row that was force-marked DONE without derivatives.
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

  /** Same, narrowed to one storage backend — the orphan sweep runs a bucket at a time. */
  @Query(
      "SELECT f.filePath FROM FileMetadata f "
          + "WHERE f.filePath IS NOT NULL AND f.filePath LIKE 'originals/%' "
          + "AND f.album.storageBackend.id = :backendId")
  List<String> findOriginalsKeysByStorageBackend(@Param("backendId") Long backendId);

  /**
   * Original bytes this user keeps on one storage backend, counting each object once.
   *
   * <p>The DISTINCT is not defensive tidiness: {@code duplicateAlbum} copies metadata rows that
   * point at the *same* keys, so a user who duplicates an album would otherwise appear to have
   * doubled their usage without a byte being written. {@code file_path IS NULL} rows are
   * retention-purged and genuinely occupy nothing.
   */
  @Query(
      value =
          "SELECT COALESCE(SUM(t.file_size), 0) FROM ("
              + " SELECT DISTINCT f.file_path, f.file_size FROM file_metadata f"
              + " JOIN albums a ON a.id = f.album_id"
              + " WHERE a.user_id = :userId AND a.storage_backend_id = :backendId"
              + " AND f.file_path IS NOT NULL) t",
      nativeQuery = true)
  long sumOriginalBytes(@Param("userId") Long userId, @Param("backendId") Long backendId);

  /**
   * Derivative bytes for the same set. Deduplicated on the derivative keys rather than on the row,
   * for the same duplicate-album reason — a copy points at the source asset's {@code
   * derivatives/{id}/} objects, so the two rows describe one set of bytes.
   */
  @Query(
      value =
          "SELECT COALESCE(SUM(t.derivative_bytes), 0) FROM ("
              + " SELECT DISTINCT COALESCE(f.thumbnail_path, f.medium_path, f.large_path,"
              + " f.transcoded_video_path) AS k, f.derivative_bytes FROM file_metadata f"
              + " JOIN albums a ON a.id = f.album_id"
              + " WHERE a.user_id = :userId AND a.storage_backend_id = :backendId"
              + " AND f.derivative_bytes > 0) t",
      nativeQuery = true)
  long sumDerivativeBytes(@Param("userId") Long userId, @Param("backendId") Long backendId);

  /** Assets on one backend whose derivative sizes were never recorded — the backfill's worklist. */
  @Query(
      "SELECT f FROM FileMetadata f WHERE f.album.storageBackend.id = :backendId"
          + " AND f.derivativeBytes = 0")
  List<FileMetadata> findWithUnknownDerivativeBytes(@Param("backendId") Long backendId);

  /**
   * Phase 4.5 follow-up — image-typed DONE rows missing at least one of the three image
   * derivatives. Used by the {@code REGEN_THUMBNAILS} admin endpoint to enqueue a regen job per
   * stranded asset (e.g. an old vipsthumbnail OOM that produced two of three sizes before
   * markFailed promoted the row to DONE-with-gaps).
   *
   * <p>Excludes assets that already have a {@code QUEUED}/{@code PROCESSING} job — repeat clicks of
   * the endpoint don't double-enqueue.
   *
   * <p>Returns IDs only (projection); the worker re-fetches the full entity inside its own TX. Cap
   * is applied at the SQL layer so a misconfigured caller can't load tens of thousands of rows into
   * the api pod's heap.
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

  /**
   * Video-typed DONE rows that never produced a web-playable MP4. The transcode failure path in
   * {@code FileProcessingService} only logs a warning — the job still completes DONE with
   * thumbnails and EXIF — so these rows are invisible unless you go looking for a null {@code
   * transcoded_video_path}.
   *
   * <p>Introduced after a run where every 10-bit HDR clip failed to encode: x264's {@code main}
   * profile is 8-bit only and the command specified no {@code -pix_fmt}, so ffmpeg picked
   * yuv420p10le to match the source and the encoder refused it. 26 assets were stranded before
   * anyone noticed.
   *
   * <p>Self-correcting: a successful re-encode populates {@code transcoded_video_path}, which drops
   * the row out of this set. Same {@code NOT EXISTS} guard as the thumbnail sweep so repeat calls
   * don't double-enqueue, and the same SQL-level cap.
   */
  @Query(
      value =
          "SELECT fm.id FROM file_metadata fm "
              + "WHERE fm.processing_status = 'DONE' "
              + "AND fm.mime_type LIKE 'video/%' "
              + "AND fm.transcoded_video_path IS NULL "
              + "AND fm.file_path IS NOT NULL "
              + "AND NOT EXISTS ("
              + "  SELECT 1 FROM processing_jobs pj "
              + "  WHERE pj.asset_id = fm.id AND pj.status IN ('QUEUED', 'PROCESSING')"
              + ") "
              + "ORDER BY fm.id ASC "
              + "LIMIT :maxRows",
      nativeQuery = true)
  List<Long> findMissingVideoTranscodeIds(@Param("maxRows") int maxRows);

  /**
   * DONE image/video rows whose capture date was never re-derived by the timezone-aware extractor
   * ({@code exif_date_source IS NULL}), plus rows that have a date but no capture offset yet — the
   * ones written before {@code capture_utc_offset_seconds} existed, which "group by day" needs to
   * put a photo on the day its own camera saw. Used by the {@code EXTRACT_CAPTURE_DATE} admin
   * endpoint.
   *
   * <p>Requires {@code file_path}: the capture time lives in the original's EXIF/QuickTime atoms
   * and no derivative carries it, so retention-purged rows can never be fixed and are excluded
   * rather than enqueued and failed.
   *
   * <p>Self-shrinking — the worker always writes a source (including {@code NONE} when the file has
   * no readable timestamp), so a row leaves this set after one pass. The offset arm is limited to
   * the three sources that always yield an offset, so rows that genuinely cannot have one ({@code
   * MVHD_UTC} videos, {@code NONE}) are never re-swept. Same {@code NOT EXISTS} guard and SQL-level
   * cap as the other sweeps; page by re-invoking until {@code enqueued == 0}.
   */
  @Query(
      value =
          "SELECT fm.id FROM file_metadata fm "
              + "WHERE fm.processing_status = 'DONE' "
              + "AND ("
              + "  fm.exif_date_source IS NULL "
              + "  OR (fm.capture_utc_offset_seconds IS NULL "
              + "      AND fm.exif_date_source IN "
              + "          ('EXIF_OFFSET_TIME', 'EXIF_FALLBACK_ZONE', 'QUICKTIME_LOCAL'))"
              + ") "
              + "AND fm.file_path IS NOT NULL "
              + "AND (fm.mime_type LIKE 'image/%' OR fm.mime_type LIKE 'video/%') "
              + "AND NOT EXISTS ("
              + "  SELECT 1 FROM processing_jobs pj "
              + "  WHERE pj.asset_id = fm.id AND pj.status IN ('QUEUED', 'PROCESSING')"
              + ") "
              + "ORDER BY fm.id ASC "
              + "LIMIT :maxRows",
      nativeQuery = true)
  List<Long> findStaleCaptureDateIds(@Param("maxRows") int maxRows);

  /**
   * DONE image/video rows that were never inspected for a capture location ({@code gps_source IS
   * NULL}) — i.e. everything uploaded before the map filter existed. Used by the {@code
   * EXTRACT_GPS} admin endpoint.
   *
   * <p>Requires {@code file_path}: coordinates live in the original's EXIF GPS IFD or QuickTime
   * location atom and no derivative carries either, so retention-purged rows can never be
   * backfilled and are excluded rather than enqueued and failed.
   *
   * <p>Self-shrinking — the worker always writes a source (including {@code NONE} for files with no
   * location), so a row leaves this set after one pass. Same {@code NOT EXISTS} guard and SQL-level
   * cap as the other sweeps; page by re-invoking until {@code enqueued == 0}.
   */
  @Query(
      value =
          "SELECT fm.id FROM file_metadata fm "
              + "WHERE fm.processing_status = 'DONE' "
              + "AND fm.gps_source IS NULL "
              + "AND fm.file_path IS NOT NULL "
              + "AND (fm.mime_type LIKE 'image/%' OR fm.mime_type LIKE 'video/%') "
              + "AND NOT EXISTS ("
              + "  SELECT 1 FROM processing_jobs pj "
              + "  WHERE pj.asset_id = fm.id AND pj.status IN ('QUEUED', 'PROCESSING')"
              + ") "
              + "ORDER BY fm.id ASC "
              + "LIMIT :maxRows",
      nativeQuery = true)
  List<Long> findMissingGpsIds(@Param("maxRows") int maxRows);
}
