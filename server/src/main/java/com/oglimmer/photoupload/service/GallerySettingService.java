/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.GallerySetting;
import com.oglimmer.photoupload.repository.GallerySettingRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Slf4j
@RequiredArgsConstructor
public class GallerySettingService {

  private final GallerySettingRepository settingRepository;

  public String getLanguage1Name() {
    return settingRepository
        .findBySettingKey("language_1_name")
        .map(GallerySetting::getSettingValue)
        .orElse("German");
  }

  @Transactional
  public void setLanguage1Name(String name) {
    GallerySetting setting =
        settingRepository.findBySettingKey("language_1_name").orElse(new GallerySetting());

    setting.setSettingKey("language_1_name");
    setting.setSettingValue(name);
    settingRepository.save(setting);

    log.info("Language 1 name updated to: {}", name);
  }

  public String getLanguage2Name() {
    return settingRepository
        .findBySettingKey("language_2_name")
        .map(GallerySetting::getSettingValue)
        .orElse("English");
  }

  @Transactional
  public void setLanguage2Name(String name) {
    GallerySetting setting =
        settingRepository.findBySettingKey("language_2_name").orElse(new GallerySetting());

    setting.setSettingKey("language_2_name");
    setting.setSettingValue(name);
    settingRepository.save(setting);

    log.info("Language 2 name updated to: {}", name);
  }
}
