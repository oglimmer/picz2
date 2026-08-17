/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.PresentationGroup;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface PresentationGroupRepository extends JpaRepository<PresentationGroup, Long> {

  // Ordered by the anchor image's position so the client can render sections without re-sorting.
  @Query(
      "SELECT g FROM PresentationGroup g WHERE g.album.id = :albumId"
          + " ORDER BY g.startFile.displayOrder ASC, g.startFile.id ASC")
  List<PresentationGroup> findByAlbumIdOrderByStartFile(@Param("albumId") Long albumId);

  @Query("SELECT g FROM PresentationGroup g WHERE g.id = :id AND g.album.user.id = :userId")
  Optional<PresentationGroup> findByIdAndUserId(@Param("id") Long id, @Param("userId") Long userId);

  boolean existsByAlbumIdAndTagIdAndStartFileId(Long albumId, Long tagId, Long startFileId);
}
