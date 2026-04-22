/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.AlbumEnabledTag;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface AlbumEnabledTagRepository extends JpaRepository<AlbumEnabledTag, Long> {

  List<AlbumEnabledTag> findByAlbumId(Long albumId);

  boolean existsByAlbumIdAndTagId(Long albumId, Long tagId);

  void deleteByAlbumIdAndTagId(Long albumId, Long tagId);

  void deleteByAlbumId(Long albumId);
}
