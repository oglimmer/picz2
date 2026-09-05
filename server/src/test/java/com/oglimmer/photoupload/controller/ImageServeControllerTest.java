/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.model.FileServeInfo;
import com.oglimmer.photoupload.service.FileStorageService;
import com.oglimmer.photoupload.service.ObjectStorageService;
import com.oglimmer.photoupload.storage.BackendStorage;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
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
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.http.AbortableInputStream;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;

@ExtendWith(MockitoExtension.class)
class ImageServeControllerTest {

  private static final Instant UPLOADED_AT = Instant.parse("2026-04-27T00:00:00Z");
  private static final long ALBUM_ID = 1L;

  @Mock FileStorageService fileStorageService;
  @Mock ObjectStorageService objectStorage;
  @Mock BackendStorage bucket;

  private ImageServeController controller;
  private MockHttpServletRequest request;
  private MockHttpServletResponse response;
  private ServletWebRequest webRequest;

  @BeforeEach
  void setUp() {
    controller = new ImageServeController(fileStorageService, objectStorage);
    lenient().when(objectStorage.forAlbumId(ALBUM_ID)).thenReturn(bucket);
    request = new MockHttpServletRequest("GET", "/api/i/tok");
    response = new MockHttpServletResponse();
    webRequest = new ServletWebRequest(request, response);
  }

  /** What the S3 SDK hands back for a GET: the response metadata plus the body stream. */
  static ResponseInputStream<GetObjectResponse> object(String body, String contentRange) {
    GetObjectResponse.Builder meta =
        GetObjectResponse.builder().contentLength((long) body.length());
    if (contentRange != null) {
      meta.contentRange(contentRange);
    }
    return new ResponseInputStream<>(
        meta.build(),
        AbortableInputStream.create(
            new ByteArrayInputStream(body.getBytes(StandardCharsets.UTF_8))));
  }

  @Test
  void returnsAcceptedWhenDerivativeMissingAndProcessingNotDone() {
    when(fileStorageService.getFileServeInfoByPublicToken("tok", "thumb"))
        .thenReturn(
            serveInfo("image/heic", "originals/photo.heic", ProcessingStatus.PROCESSING, false));

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", "thumb", webRequest);

    assertEquals(HttpStatus.ACCEPTED, resp.getStatusCode());
    assertEquals("2", resp.getHeaders().getFirst(HttpHeaders.RETRY_AFTER));
    assertNull(resp.getBody());
    // Cache-Control: no-store so the browser doesn't memoize the empty placeholder response.
    assertNotNull(resp.getHeaders().getCacheControl());
    verify(bucket, never()).openStream(anyString());
  }

  @Test
  void servesOriginalWhenProcessingDoneEvenIfDerivativeFlagFalse() {
    when(fileStorageService.getFileServeInfoByPublicToken("tok", "thumb"))
        .thenReturn(serveInfo("image/jpeg", "originals/served.jpg", ProcessingStatus.DONE, false));
    when(bucket.openStream("originals/served.jpg")).thenReturn(object("x", null));

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", "thumb", webRequest);

    assertEquals(HttpStatus.OK, resp.getStatusCode());
    assertNotNull(resp.getBody());
  }

  @Test
  void servesNormallyWhenDerivativeReady() {
    when(fileStorageService.getFileServeInfoByPublicToken("tok", "thumb"))
        .thenReturn(
            serveInfo("image/jpeg", "derivatives/1/thumb.jpg", ProcessingStatus.DONE, true));
    when(bucket.openStream("derivatives/1/thumb.jpg")).thenReturn(object("x", null));

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", "thumb", webRequest);

    assertEquals(HttpStatus.OK, resp.getStatusCode());
    assertNotNull(resp.getBody());
  }

  @Test
  void matchingIfNoneMatchShortCircuitsToNotModifiedWithoutOpeningTheObject() {
    when(fileStorageService.getFileServeInfoByPublicToken("tok", "thumb"))
        .thenReturn(
            serveInfo("image/jpeg", "derivatives/1/thumb.jpg", ProcessingStatus.DONE, true));
    request.addHeader(HttpHeaders.IF_NONE_MATCH, "\"abc\"");

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", "thumb", webRequest);

    // A null ResponseEntity means "the response is already fully populated" — Spring's
    // HttpEntityMethodProcessor treats it as handled. Crucially no stream was ever opened, which is
    // what stops an unclosed ResponseInputStream leaking a pooled MinIO connection.
    assertNull(resp);
    assertEquals(HttpStatus.NOT_MODIFIED.value(), response.getStatus());
    assertEquals("\"abc\"", response.getHeader(HttpHeaders.ETAG));
    verify(bucket, never()).openStream(anyString());
  }

  @Test
  void staleIfNoneMatchStillServesTheBody() {
    when(fileStorageService.getFileServeInfoByPublicToken("tok", "thumb"))
        .thenReturn(
            serveInfo("image/jpeg", "derivatives/1/thumb.jpg", ProcessingStatus.DONE, true));
    when(bucket.openStream("derivatives/1/thumb.jpg")).thenReturn(object("x", null));
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
            serveInfo("image/heic", "originals/photo.heic", ProcessingStatus.PROCESSING, false));
    request.addHeader(HttpHeaders.IF_NONE_MATCH, "\"abc\"");

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", "thumb", webRequest);

    // 202 wins over 304: the client is polling for a derivative that does not exist yet, and a
    // 304 would tell it to keep using a cached copy it never had.
    assertEquals(HttpStatus.ACCEPTED, resp.getStatusCode());
  }

  @Test
  void rangedGetOnAVideoAnswersPartialContent() {
    when(fileStorageService.getFileServeInfoByPublicToken("tok", null))
        .thenReturn(
            serveInfo("video/mp4", "derivatives/1/transcoded.mp4", ProcessingStatus.DONE, false));
    when(bucket.openStream("derivatives/1/transcoded.mp4", "bytes=2-5"))
        .thenReturn(object("2345", "bytes 2-5/10"));
    request.addHeader(HttpHeaders.RANGE, "bytes=2-5");

    ResponseEntity<?> resp = controller.streamRangeByToken("tok", null, "bytes=2-5", webRequest);

    // Without 206 + Content-Range, iOS AVPlayer refuses the stream and the app shows "Failed".
    assertEquals(HttpStatus.PARTIAL_CONTENT, resp.getStatusCode());
    assertEquals("bytes 2-5/10", resp.getHeaders().getFirst(HttpHeaders.CONTENT_RANGE));
    assertEquals("bytes", resp.getHeaders().getFirst(HttpHeaders.ACCEPT_RANGES));
    assertEquals(4L, resp.getHeaders().getContentLength());
  }

  @Test
  void unrangedGetStillAdvertisesRangeSupport() {
    when(fileStorageService.getFileServeInfoByPublicToken("tok", null))
        .thenReturn(
            serveInfo("video/mp4", "derivatives/1/transcoded.mp4", ProcessingStatus.DONE, false));
    when(bucket.openStream("derivatives/1/transcoded.mp4")).thenReturn(object("0123456789", null));

    ResponseEntity<?> resp = controller.downloadFileByToken("tok", null, webRequest);

    assertEquals(HttpStatus.OK, resp.getStatusCode());
    // Accept-Ranges is what tells the player it may seek at all.
    assertEquals("bytes", resp.getHeaders().getFirst(HttpHeaders.ACCEPT_RANGES));
  }

  private static FileServeInfo serveInfo(
      String mime, String key, ProcessingStatus status, boolean derivativeReady) {
    return new FileServeInfo(
        mime,
        "abc",
        UPLOADED_AT,
        key.substring(key.lastIndexOf('/') + 1),
        status,
        derivativeReady,
        key,
        ALBUM_ID);
  }
}
