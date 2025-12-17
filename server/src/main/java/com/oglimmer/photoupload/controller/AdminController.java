/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.model.AdminOperationResponse;
import com.oglimmer.photoupload.service.FileStorageService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin")
@Slf4j
@RequiredArgsConstructor
public class AdminController {

  private final FileStorageService fileStorageService;

  @PostMapping("/generate-thumbnails")
  public ResponseEntity<AdminOperationResponse> generateThumbnails(
      @RequestParam(value = "overwrite", required = false, defaultValue = "false")
          boolean overwrite) {
    if (overwrite) {
      log.info("Starting batch thumbnail generation for all existing images (overwrite mode)...");
    } else {
      log.info("Starting batch thumbnail generation for all existing images...");
    }
    var result = fileStorageService.generateMissingThumbnails(overwrite);

    AdminOperationResponse response =
        AdminOperationResponse.builder()
            .success(true)
            .message("Thumbnail generation complete")
            .stats(result)
            .build();

    return ResponseEntity.ok(response);
  }

  @PostMapping("/update-transcoded-videos")
  public ResponseEntity<AdminOperationResponse> updateTranscodedVideos() {
    log.info("Starting scan for transcoded videos...");
    var result = fileStorageService.updateTranscodedVideoPaths();

    AdminOperationResponse response =
        AdminOperationResponse.builder()
            .success(true)
            .message("Transcoded video paths updated successfully")
            .stats(result)
            .build();

    return ResponseEntity.ok(response);
  }

  @PostMapping("/update-video-thumbnails")
  public ResponseEntity<AdminOperationResponse> updateVideoThumbnails() {
    log.info("Starting scan for video thumbnails...");
    var result = fileStorageService.updateVideoThumbnailPaths();

    AdminOperationResponse response =
        AdminOperationResponse.builder()
            .success(true)
            .message("Video thumbnail paths updated successfully")
            .stats(result)
            .build();

    return ResponseEntity.ok(response);
  }
}
