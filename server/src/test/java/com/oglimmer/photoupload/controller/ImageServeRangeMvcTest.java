/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.model.FileServeInfo;
import com.oglimmer.photoupload.service.FileStorageService;
import com.oglimmer.photoupload.service.ObjectStorageService;
import com.oglimmer.photoupload.storage.BackendStorage;
import java.time.Instant;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.RequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

/**
 * Drives the controller through Spring's real return-value handling, which unit-calling the method
 * cannot do.
 *
 * <p>This exists because the first cut of the Range support passed every direct-call test and still
 * 500'd in production: the range branch lived inside a handler declared {@code ResponseEntity<?>},
 * so {@code StreamingResponseBodyReturnValueHandler} never claimed it and {@code
 * HttpEntityMethodProcessor} went looking for a message converter for a lambda — "No converter for
 * [...$$Lambda] with preset Content-Type 'video/mp4'". Only the dispatcher shows that, so any
 * change to how these responses are typed belongs under MockMvc.
 */
@ExtendWith(MockitoExtension.class)
class ImageServeRangeMvcTest {

  private static final Instant UPLOADED_AT = Instant.parse("2026-04-27T00:00:00Z");
  private static final String KEY = "derivatives/1/transcoded.mp4";
  private static final String CLIP = "0123456789";

  @Mock FileStorageService fileStorageService;
  @Mock ObjectStorageService objectStorage;
  @Mock BackendStorage bucket;

  private MockMvc mockMvc;

  @BeforeEach
  void setUp() {
    FileServeInfo info =
        new FileServeInfo(
            "video/mp4", "abc", UPLOADED_AT, "clip.mp4", ProcessingStatus.DONE, false, KEY, 1L);
    when(fileStorageService.getFileServeInfoByPublicToken("tok", null)).thenReturn(info);
    when(objectStorage.forAlbumId(1L)).thenReturn(bucket);
    mockMvc =
        MockMvcBuilders.standaloneSetup(new ImageServeController(fileStorageService, objectStorage))
            .build();
  }

  /** MinIO does the slicing; the controller only mirrors what came back. */
  private void ranged(int from, int to) {
    when(bucket.openStream(KEY, "bytes=" + from + "-" + to))
        .thenReturn(
            ImageServeControllerTest.object(
                CLIP.substring(from, to + 1), "bytes " + from + "-" + to + "/" + CLIP.length()));
  }

  /**
   * A {@code StreamingResponseBody} is written from a worker thread, so the response buffer is
   * still empty when {@code perform()} returns — asserting on it directly passes or fails by luck.
   * {@code getAsyncResult()} blocks until the callable that writes the bytes has finished.
   */
  private MockHttpServletResponse completed(RequestBuilder request) throws Exception {
    MvcResult result = mockMvc.perform(request).andReturn();
    if (result.getRequest().isAsyncStarted()) {
      result.getAsyncResult();
    }
    return result.getResponse();
  }

  @Test
  void aRangedGetIsWrittenAsPartialContent() throws Exception {
    ranged(2, 5);

    MockHttpServletResponse response =
        completed(get("/api/i/tok").header(HttpHeaders.RANGE, "bytes=2-5"));

    assertEquals(HttpStatus.PARTIAL_CONTENT.value(), response.getStatus());
    assertEquals("bytes 2-5/10", response.getHeader(HttpHeaders.CONTENT_RANGE));
    assertEquals("bytes", response.getHeader(HttpHeaders.ACCEPT_RANGES));
    assertEquals("2345", response.getContentAsString());
  }

  @Test
  void anOpeningProbeRangeIsAnswered() throws Exception {
    // AVPlayer's first request. If this 500s, the iOS app shows "Failed" and never retries.
    ranged(0, 1);

    MockHttpServletResponse response =
        completed(get("/api/i/tok").header(HttpHeaders.RANGE, "bytes=0-1"));

    assertEquals(HttpStatus.PARTIAL_CONTENT.value(), response.getStatus());
    assertEquals("01", response.getContentAsString());
  }

  @Test
  void anUnrangedGetStillGoesDownTheWholeBodyPath() throws Exception {
    when(bucket.openStream(KEY)).thenReturn(ImageServeControllerTest.object(CLIP, null));

    MockHttpServletResponse response = completed(get("/api/i/tok"));

    assertEquals(HttpStatus.OK.value(), response.getStatus());
    assertEquals("bytes", response.getHeader(HttpHeaders.ACCEPT_RANGES));
    assertEquals(CLIP, response.getContentAsString());
  }
}
