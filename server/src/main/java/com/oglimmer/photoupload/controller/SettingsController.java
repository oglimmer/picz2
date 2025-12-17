/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.model.MessageResponse;
import com.oglimmer.photoupload.model.SettingRequest;
import com.oglimmer.photoupload.model.SettingResponse;
import com.oglimmer.photoupload.model.TargetAlbumRequest;
import com.oglimmer.photoupload.model.TargetAlbumResponse;
import com.oglimmer.photoupload.service.GallerySettingService;
import com.oglimmer.photoupload.service.UserSettingService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/settings")
@Slf4j
@RequiredArgsConstructor
public class SettingsController {

  private final GallerySettingService gallerySettingService;
  private final UserSettingService userSettingService;

  @GetMapping("/languages")
  public ResponseEntity<SettingResponse> getLanguageSettings() {
    String language1 = gallerySettingService.getLanguage1Name();
    String language2 = gallerySettingService.getLanguage2Name();

    SettingResponse response =
        SettingResponse.builder().success(true).language1(language1).language2(language2).build();

    return ResponseEntity.ok(response);
  }

  @PutMapping("/languages/1")
  public ResponseEntity<MessageResponse> setLanguage1Name(
      @RequestBody SettingRequest settingRequest) {
    if (settingRequest.getValue() == null || settingRequest.getValue().trim().isEmpty()) {
      throw new ValidationException("Language name is required");
    }

    gallerySettingService.setLanguage1Name(settingRequest.getValue());

    MessageResponse response =
        MessageResponse.builder()
            .success(true)
            .message("Language 1 name updated successfully")
            .build();

    return ResponseEntity.ok(response);
  }

  @PutMapping("/languages/2")
  public ResponseEntity<MessageResponse> setLanguage2Name(
      @RequestBody SettingRequest settingRequest) {
    if (settingRequest.getValue() == null || settingRequest.getValue().trim().isEmpty()) {
      throw new ValidationException("Language name is required");
    }

    gallerySettingService.setLanguage2Name(settingRequest.getValue());

    MessageResponse response =
        MessageResponse.builder()
            .success(true)
            .message("Language 2 name updated successfully")
            .build();

    return ResponseEntity.ok(response);
  }

  @GetMapping("/target-album")
  public ResponseEntity<TargetAlbumResponse> getTargetAlbum() {
    Long albumId = userSettingService.getTargetAlbum();

    TargetAlbumResponse response =
        TargetAlbumResponse.builder().success(true).albumId(albumId).build();

    return ResponseEntity.ok(response);
  }

  @PutMapping("/target-album")
  public ResponseEntity<MessageResponse> setTargetAlbum(@RequestBody TargetAlbumRequest request) {
    if (request.getAlbumId() == null) {
      throw new ValidationException("Album ID is required");
    }

    userSettingService.setTargetAlbum(request.getAlbumId());

    MessageResponse response =
        MessageResponse.builder()
            .success(true)
            .message("Target album updated successfully")
            .build();

    return ResponseEntity.ok(response);
  }

  @DeleteMapping("/target-album")
  public ResponseEntity<MessageResponse> clearTargetAlbum() {
    userSettingService.clearTargetAlbum();

    MessageResponse response =
        MessageResponse.builder()
            .success(true)
            .message("Sync paused - target album cleared")
            .build();

    return ResponseEntity.ok(response);
  }
}
