/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.ImageTag;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface ImageTagRepository extends JpaRepository<ImageTag, Long> {

  List<ImageTag> findByFileMetadataId(Long fileMetadataId);

  @Query(
      "SELECT it FROM ImageTag it WHERE it.fileMetadata.id = :fileMetadataId AND it.tag.id = :tagId")
  Optional<ImageTag> findByFileMetadataIdAndTagId(
      @Param("fileMetadataId") Long fileMetadataId, @Param("tagId") Long tagId);

  void deleteByTagId(Long tagId);

  /**
   * Ids of the files for which {@code tagId} is the one and only tag. Deleting that tag would leave
   * them bare, and a bare file is a hidden one (D79), so the caller re-hides them first.
   */
  @Query(
      "SELECT it.fileMetadata.id FROM ImageTag it WHERE it.tag.id = :tagId AND NOT EXISTS ("
          + "SELECT o.id FROM ImageTag o WHERE o.fileMetadata.id = it.fileMetadata.id"
          + " AND o.tag.id <> :tagId)")
  List<Long> findFileIdsWhereTagIsTheOnlyOne(@Param("tagId") Long tagId);
}
