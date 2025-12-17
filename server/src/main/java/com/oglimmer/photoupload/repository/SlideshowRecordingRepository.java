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
