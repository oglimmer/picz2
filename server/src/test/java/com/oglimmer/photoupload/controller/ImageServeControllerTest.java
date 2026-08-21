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
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.web.context.request.ServletWebRequest;

@ExtendWith(MockitoExtension.class)
class ImageServeControllerTest {

  private static final Instant UPLOADED_AT = Instant.parse("2026-04-27T00:00:00Z");

  @Mock FileStorageService fileStorageService;

  private ImageServeController controller;
  private MockHttpServletRequest request;
  private MockHttpServletResponse response;
  private ServletWebRequest webRequest;

  @BeforeEach
  void setUp() {
    // Optional.empty() mirrors a deployment where storage.s3.enabled=false and the
    // ObjectStorageService bean simply is not in the context.
    controller = new ImageServeController(fileStorageService, Optional.empty());
    request = new MockHttpServletRequest("GET", "/api/i/tok");
    response = new MockHttpServletResponse();
    webRequest = new ServletWebRequest(request, response);
  }

  @Test
  void returnsAcceptedWhenDerivativeMissingAndProcessingNotDone() {
    FileServeInfo info =
        new FileServeInfo(
            "image/heic",
            "abc",
            UPLOADED_AT,
            Paths.get("/nonexistent/photo.heic"),
            "photo.heic",
            ProcessingStatus.PROCESSING,
            false,
            null);
    when(fileStorageService.getFileServeInfoByPublicToken("tok", "thumb")).thenReturn(info);

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", "thumb", webRequest);

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
            UPLOADED_AT,
            file,
            "served.jpg",
            ProcessingStatus.DONE,
            false,
            null);
    when(fileStorageService.getFileServeInfoByPublicToken("tok", "thumb")).thenReturn(info);

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", "thumb", webRequest);

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
            "image/jpeg", "abc", UPLOADED_AT, file, "thumb.jpg", ProcessingStatus.DONE, true, null);
    when(fileStorageService.getFileServeInfoByPublicToken("tok", "thumb")).thenReturn(info);

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", "thumb", webRequest);

    assertEquals(HttpStatus.OK, resp.getStatusCode());
    assertNotNull(resp.getBody());
  }

  @Test
  void matchingIfNoneMatchShortCircuitsToNotModifiedWithoutOpeningTheFile(
      @org.junit.jupiter.api.io.TempDir Path tempDir) throws Exception {
    Path file = tempDir.resolve("thumb.jpg");
    java.nio.file.Files.writeString(file, "x");
    when(fileStorageService.getFileServeInfoByPublicToken("tok", "thumb"))
        .thenReturn(serveInfo(file, ProcessingStatus.DONE, true));
    request.addHeader(HttpHeaders.IF_NONE_MATCH, "\"abc\"");

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", "thumb", webRequest);

    // A null ResponseEntity means "the response is already fully populated" — Spring's
    // HttpEntityMethodProcessor treats it as handled. Crucially no Resource was ever created,
    // which on the S3 path is what stops an unclosed ResponseInputStream leaking a pooled
    // MinIO connection.
    assertNull(resp);
    assertEquals(HttpStatus.NOT_MODIFIED.value(), response.getStatus());
    assertEquals("\"abc\"", response.getHeader(HttpHeaders.ETAG));
  }

  @Test
  void staleIfNoneMatchStillServesTheBody(@org.junit.jupiter.api.io.TempDir Path tempDir)
      throws Exception {
    Path file = tempDir.resolve("thumb.jpg");
    java.nio.file.Files.writeString(file, "x");
    when(fileStorageService.getFileServeInfoByPublicToken("tok", "thumb"))
        .thenReturn(serveInfo(file, ProcessingStatus.DONE, true));
    request.addHeader(HttpHeaders.IF_NONE_MATCH, "\"stale\"");

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", "thumb", webRequest);

    assertEquals(HttpStatus.OK, resp.getStatusCode());
    assertNotNull(resp.getBody());
    // checkNotModified() stamps the validators itself; the builder must not repeat them or the
    // response would carry two ETag headers.
    assertNull(resp.getHeaders().getETag());
    assertEquals("\"abc\"", response.getHeader(HttpHeaders.ETAG));
  }

  @Test
  void notModifiedIsNotEvaluatedWhileProcessingIsStillPending() {
    when(fileStorageService.getFileServeInfoByPublicToken("tok", "thumb"))
        .thenReturn(
            serveInfo(Paths.get("/nonexistent/photo.heic"), ProcessingStatus.PROCESSING, false));
    request.addHeader(HttpHeaders.IF_NONE_MATCH, "\"abc\"");

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", "thumb", webRequest);

    // 202 wins over 304: the client is polling for a derivative that does not exist yet, and a
    // 304 would tell it to keep using a cached copy it never had.
    assertEquals(HttpStatus.ACCEPTED, resp.getStatusCode());
  }

  private FileServeInfo serveInfo(Path path, ProcessingStatus status, boolean derivativeReady) {
    return new FileServeInfo(
        "image/jpeg",
        "abc",
        UPLOADED_AT,
        path,
        path.getFileName().toString(),
        status,
        derivativeReady,
        null);
  }
}
