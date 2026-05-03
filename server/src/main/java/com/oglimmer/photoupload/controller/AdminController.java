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

  /**
   * Finds S3 objects with no corresponding DB row and deletes them. Always run with
   * {@code dryRun=true} first to review what would be removed before committing.
   */
  @PostMapping("/purge-orphaned-s3")
  public ResponseEntity<AdminOperationResponse> purgeOrphanedS3(
      @RequestParam(value = "dryRun", required = false, defaultValue = "true") boolean dryRun) {
    log.info("Starting S3 orphan purge (dryRun={})", dryRun);
    var result = fileStorageService.purgeOrphanedS3Objects(dryRun);

    AdminOperationResponse response =
        AdminOperationResponse.builder()
            .success(true)
            .message(dryRun ? "Dry run complete — no objects deleted" : "Orphaned S3 objects purged")
            .stats(result)
            .build();

    return ResponseEntity.ok(response);
  }

  /**
   * Phase 4.5 follow-up — enqueue {@code REGEN_THUMBNAILS} jobs for image-typed DONE rows that
   * are missing one or more derivatives. Idempotent: assets already queued/processing are skipped
   * by the repository query, so repeat clicks just no-op.
   *
   * <p>{@code maxRows} caps a single batch (default 500, hard upper bound 5000). Caller pages by
   * re-invoking until {@code enqueued == 0}.
   */
  @PostMapping("/regen-missing-thumbnails")
  public ResponseEntity<AdminOperationResponse> regenMissingThumbnails(
      @RequestParam(value = "maxRows", required = false, defaultValue = "500") int maxRows) {
    int enqueued = fileStorageService.enqueueRegenForMissingThumbnails(maxRows);
    AdminOperationResponse response =
        AdminOperationResponse.builder()
            .success(true)
            .message(
                enqueued == 0
                    ? "No eligible assets — nothing to enqueue"
                    : "Enqueued " + enqueued + " regen-thumbnails job(s)")
            .stats(java.util.Map.of("enqueued", enqueued, "maxRows", maxRows))
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
