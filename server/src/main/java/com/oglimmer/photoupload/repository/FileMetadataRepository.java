/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
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
}
