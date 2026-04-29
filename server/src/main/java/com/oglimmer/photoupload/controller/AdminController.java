/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import org.springframework.context.annotation.Profile;

import com.oglimmer.photoupload.entity.JobStatus;
import com.oglimmer.photoupload.model.AdminOperationResponse;
import com.oglimmer.photoupload.model.DeadLetterJobResponse;
import com.oglimmer.photoupload.repository.ProcessingJobRepository;
import com.oglimmer.photoupload.service.FileStorageService;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Profile(Profiles.API)
@RestController
@RequestMapping("/api/admin")
@Slf4j
@RequiredArgsConstructor
public class AdminController {

  private final FileStorageService fileStorageService;
  private final ProcessingJobRepository processingJobRepository;

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

  /**
   * Lists processing jobs that have exhausted their retry budget. Surfaces the original asset id
   * and last error so an operator can decide whether to delete the asset, fix the underlying issue,
   * or re-enqueue the job (re-enqueue UI is a future follow-up).
   */
  @GetMapping("/dead-letter")
  public ResponseEntity<List<DeadLetterJobResponse>> listDeadLetterJobs(
      @RequestParam(value = "limit", required = false, defaultValue = "100") int limit) {
    int safeLimit = Math.max(1, Math.min(limit, 500));
    List<DeadLetterJobResponse> body =
        processingJobRepository
            .findByStatusOrderByCreatedAtDesc(JobStatus.DEAD_LETTER, PageRequest.of(0, safeLimit))
            .stream()
            .map(DeadLetterJobResponse::from)
            .toList();
    return ResponseEntity.ok(body);
  }
}
