/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.model.FileServeInfo;
import com.oglimmer.photoupload.service.FileStorageService;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class ImageServeControllerTest {

  @Mock FileStorageService fileStorageService;

  @InjectMocks ImageServeController controller;

  @Test
  void returnsAcceptedWhenDerivativeMissingAndProcessingNotDone() {
    FileServeInfo info =
        new FileServeInfo(
            "image/heic",
            "abc",
            Instant.parse("2026-04-27T00:00:00Z"),
            Paths.get("/nonexistent/photo.heic"),
            "photo.heic",
            ProcessingStatus.PROCESSING,
            false);
    when(fileStorageService.getFileServeInfoByPublicToken("tok", "thumb")).thenReturn(info);

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", "thumb");

    assertEquals(HttpStatus.ACCEPTED, resp.getStatusCode());
    assertEquals("2", resp.getHeaders().getFirst(HttpHeaders.RETRY_AFTER));
    assertNull(resp.getBody());
    // Cache-Control: no-store so the browser doesn't memoize the empty placeholder response.
    assertNotNull(resp.getHeaders().getCacheControl());
  }

  @Test
  void servesOriginalWhenProcessingDoneEvenIfDerivativeFlagFalse(
      @org.junit.jupiter.api.io.TempDir Path tempDir) throws Exception {
    Path file = tempDir.resolve("served.jpg");
    java.nio.file.Files.writeString(file, "x");

    FileServeInfo info =
        new FileServeInfo(
            "image/jpeg",
            "abc",
            Instant.parse("2026-04-27T00:00:00Z"),
            file,
            "served.jpg",
            ProcessingStatus.DONE,
            false);
    when(fileStorageService.getFileServeInfoByPublicToken("tok", "thumb")).thenReturn(info);

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", "thumb");

    assertEquals(HttpStatus.OK, resp.getStatusCode());
    assertNotNull(resp.getBody());
  }

  @Test
  void servesNormallyWhenDerivativeReady(@org.junit.jupiter.api.io.TempDir Path tempDir)
      throws Exception {
    Path file = tempDir.resolve("thumb.jpg");
    java.nio.file.Files.writeString(file, "x");

    FileServeInfo info =
        new FileServeInfo(
            "image/jpeg",
            "abc",
            Instant.parse("2026-04-27T00:00:00Z"),
            file,
            "thumb.jpg",
            ProcessingStatus.DONE,
            true);
    when(fileStorageService.getFileServeInfoByPublicToken("tok", "thumb")).thenReturn(info);

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", "thumb");

    assertEquals(HttpStatus.OK, resp.getStatusCode());
    assertNotNull(resp.getBody());
  }
}
