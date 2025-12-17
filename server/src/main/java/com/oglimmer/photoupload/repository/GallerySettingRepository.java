/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.GallerySetting;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface GallerySettingRepository extends JpaRepository<GallerySetting, Long> {

  Optional<GallerySetting> findBySettingKey(String settingKey);
}
