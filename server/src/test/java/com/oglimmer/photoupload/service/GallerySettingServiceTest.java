/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.oglimmer.photoupload.entity.GallerySetting;
import com.oglimmer.photoupload.repository.GallerySettingRepository;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class GallerySettingServiceTest {

  @Mock private GallerySettingRepository repository;

  @InjectMocks private GallerySettingService service;

  @Test
  void getLanguageDefaultsWhenMissing() {
    when(repository.findBySettingKey("language_1_name")).thenReturn(Optional.empty());
    when(repository.findBySettingKey("language_2_name")).thenReturn(Optional.empty());

    assertEquals("German", service.getLanguage1Name());
    assertEquals("English", service.getLanguage2Name());
  }

  @Test
  void getLanguageReturnsStoredValue() {
    when(repository.findBySettingKey("language_1_name"))
        .thenReturn(Optional.of(newSetting("language_1_name", "Deutsch")));
    when(repository.findBySettingKey("language_2_name"))
        .thenReturn(Optional.of(newSetting("language_2_name", "Englisch")));

    assertEquals("Deutsch", service.getLanguage1Name());
    assertEquals("Englisch", service.getLanguage2Name());
  }

  @Test
  void setLanguage1PersistsSetting() {
    when(repository.findBySettingKey("language_1_name")).thenReturn(Optional.empty());

    service.setLanguage1Name("Deutsch");

    ArgumentCaptor<GallerySetting> captor = ArgumentCaptor.forClass(GallerySetting.class);
    verify(repository).save(captor.capture());

    GallerySetting saved = captor.getValue();
    assertEquals("language_1_name", saved.getSettingKey());
    assertEquals("Deutsch", saved.getSettingValue());
  }

  @Test
  void setLanguage2PersistsSetting() {
    when(repository.findBySettingKey("language_2_name")).thenReturn(Optional.empty());

    service.setLanguage2Name("English");

    ArgumentCaptor<GallerySetting> captor = ArgumentCaptor.forClass(GallerySetting.class);
    verify(repository).save(captor.capture());

    GallerySetting saved = captor.getValue();
    assertEquals("language_2_name", saved.getSettingKey());
    assertEquals("English", saved.getSettingValue());
  }

  private static GallerySetting newSetting(String key, String value) {
    GallerySetting s = new GallerySetting();
    s.setSettingKey(key);
    s.setSettingValue(value);
    return s;
  }
}
