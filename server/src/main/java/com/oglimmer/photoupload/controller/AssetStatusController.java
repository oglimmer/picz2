/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import org.springframework.context.annotation.Profile;

import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.model.AssetProcessingStatusResponse;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.security.UserContext;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Profile(Profiles.API)
@RestController
@RequestMapping("/api/assets")
@RequiredArgsConstructor
public class AssetStatusController {

  private final FileMetadataRepository fileMetadataRepository;
  private final UserContext userContext;

  @GetMapping("/{id}/status")
  @Transactional(readOnly = true)
  public ResponseEntity<AssetProcessingStatusResponse> getStatus(@PathVariable Long id) {
    Long userId = userContext.getCurrentUserId();
    FileMetadata metadata =
        fileMetadataRepository
            .findByIdAndUserId(id, userId)
            .orElseThrow(() -> new ResourceNotFoundException("File", "id", id));

    return toResponse(metadata);
  }

  /**
   * Phase 5 follow-up — resolve the server-side asset id from the client's contentId. TUS
   * PATCH responses don't carry the asset id (only TUS protocol headers), so iOS needs this
   * lookup to start {@code ProcessingStatusPoller} for a freshly-uploaded TUS file.
   *
   * <p>Scoped to {@code (albumId, contentId, currentUser)} so the same source asset uploaded
   * to two albums resolves deterministically. Returns the same shape as {@link
   * #getStatus(Long)} so the caller can immediately use the result for polling without a
   * second round-trip.
   *
   * <p>404 means the row hasn't appeared yet — most likely the post-finish hook is still
   * running (the race documented in the bug-fix notes for Phase 5b). Caller is expected to
   * retry briefly with backoff.
   */
  @GetMapping("/by-content")
  @Transactional(readOnly = true)
  public ResponseEntity<AssetProcessingStatusResponse> getStatusByContentId(
      @RequestParam Long albumId, @RequestParam String contentId) {
    Long userId = userContext.getCurrentUserId();
    FileMetadata metadata =
        fileMetadataRepository.findByContentIdAndUserId(contentId, userId).stream()
            .filter(fm -> fm.getAlbum() != null && albumId.equals(fm.getAlbum().getId()))
            .findFirst()
            .orElseThrow(
                () -> new ResourceNotFoundException("Asset by contentId", "contentId", contentId));

    return toResponse(metadata);
  }

  private static ResponseEntity<AssetProcessingStatusResponse> toResponse(FileMetadata metadata) {
    return ResponseEntity.ok(
        AssetProcessingStatusResponse.builder()
            .id(metadata.getId())
            .processingStatus(metadata.getProcessingStatus())
            .attempts(metadata.getProcessingAttempts())
            .completedAt(metadata.getProcessingCompletedAt())
            .error(metadata.getProcessingError())
            .build());
  }
}
