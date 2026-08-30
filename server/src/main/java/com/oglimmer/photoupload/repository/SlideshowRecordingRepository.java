/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.SlideshowRecording;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface SlideshowRecordingRepository extends JpaRepository<SlideshowRecording, Long> {

  /**
   * Every {@code audio_path} in the table. Recording audio lives in this table, not in {@code
   * file_metadata}, so any sweep that decides what a bucket key is for must consult both — see the
   * comment on {@code FileStorageService.purgeOrphanedS3Objects}.
   */
  @Query("SELECT r.audioPath FROM SlideshowRecording r WHERE r.audioPath IS NOT NULL")
  List<String> findAllAudioPaths();

  /** Every {@code audio_filename}, so the derived {@code .m4a} siblings can be named. */
  @Query("SELECT r.audioFilename FROM SlideshowRecording r WHERE r.audioFilename IS NOT NULL")
  List<String> findAllAudioFilenames();

  /** Backend-scoped variants, for the per-backend orphan sweep. */
  @Query(
      "SELECT r.audioPath FROM SlideshowRecording r"
          + " WHERE r.audioPath IS NOT NULL AND r.album.storageBackend.id = :backendId")
  List<String> findAudioPathsByStorageBackend(@Param("backendId") Long backendId);

  @Query(
      "SELECT r.audioFilename FROM SlideshowRecording r"
          + " WHERE r.audioFilename IS NOT NULL AND r.album.storageBackend.id = :backendId")
  List<String> findAudioFilenamesByStorageBackend(@Param("backendId") Long backendId);

  /**
   * Narration bytes this user keeps on one backend. No DISTINCT needed: {@code duplicateAlbum}
   * copies files and tags but not recordings, so no two rows ever share an audio object.
   */
  @Query(
      "SELECT COALESCE(SUM(r.audioBytes), 0) FROM SlideshowRecording r"
          + " WHERE r.album.user.id = :userId AND r.album.storageBackend.id = :backendId"
          + " AND r.audioBytes IS NOT NULL")
  long sumAudioBytes(@Param("userId") Long userId, @Param("backendId") Long backendId);

  /** Recordings on one backend whose audio size was never recorded — the backfill's worklist. */
  @Query(
      "SELECT r FROM SlideshowRecording r WHERE r.album.storageBackend.id = :backendId"
          + " AND r.audioBytes IS NULL AND r.audioPath IS NOT NULL")
  List<SlideshowRecording> findByStorageBackendWithUnknownAudioBytes(
      @Param("backendId") Long backendId);

  // User-scoped queries via album relationship
  @Query(
      "SELECT s FROM SlideshowRecording s WHERE s.album.id = :albumId AND s.album.user.id = :userId ORDER BY s.createdAt DESC")
  List<SlideshowRecording> findByAlbumIdAndUserIdOrderByCreatedAtDesc(
      @Param("albumId") Long albumId, @Param("userId") Long userId);

  @Query("SELECT s FROM SlideshowRecording s WHERE s.id = :id AND s.album.user.id = :userId")
  Optional<SlideshowRecording> findByIdAndUserId(
      @Param("id") Long id, @Param("userId") Long userId);

  // Public access via public token (no user scoping needed)
  Optional<SlideshowRecording> findByPublicToken(String publicToken);
}
