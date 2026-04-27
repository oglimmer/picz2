/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.model.AssetProcessingStatusResponse;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.time.Instant;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class AssetStatusControllerTest {

  @Mock FileMetadataRepository fileMetadataRepository;
  @Mock UserContext userContext;

  @InjectMocks AssetStatusController controller;

  @Test
  void returnsCurrentStatus() {
    FileMetadata md = new FileMetadata();
    md.setId(7L);
    md.setProcessingStatus(ProcessingStatus.PROCESSING);
    md.setProcessingAttempts(2);
    Instant completed = Instant.parse("2026-04-27T10:00:00Z");
    md.setProcessingCompletedAt(completed);
    md.setProcessingError(null);

    when(userContext.getCurrentUserId()).thenReturn(42L);
    when(fileMetadataRepository.findByIdAndUserId(7L, 42L)).thenReturn(Optional.of(md));

    ResponseEntity<AssetProcessingStatusResponse> resp = controller.getStatus(7L);
    AssetProcessingStatusResponse body = resp.getBody();
    assertEquals(200, resp.getStatusCode().value());
    assertEquals(7L, body.getId());
    assertEquals(ProcessingStatus.PROCESSING, body.getProcessingStatus());
    assertEquals(2, body.getAttempts());
    assertEquals(completed, body.getCompletedAt());
  }

  @Test
  void notFoundForOtherUser() {
    when(userContext.getCurrentUserId()).thenReturn(42L);
    when(fileMetadataRepository.findByIdAndUserId(7L, 42L)).thenReturn(Optional.empty());

    assertThrows(ResourceNotFoundException.class, () -> controller.getStatus(7L));
  }
}
