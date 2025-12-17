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

  void deleteByFileMetadataIdAndTagId(Long fileMetadataId, Long tagId);

  void deleteByTagId(Long tagId);
}
