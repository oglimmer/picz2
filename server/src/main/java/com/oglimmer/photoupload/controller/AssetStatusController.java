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
