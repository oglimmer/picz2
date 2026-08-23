/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.model.FileServeInfo;
import com.oglimmer.photoupload.service.FileStorageService;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.api.io.TempDir;
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

  @Mock FileStorageService fileStorageService;

  private MockMvc mockMvc(Path file) {
    FileServeInfo info =
        new FileServeInfo(
            "video/mp4", "abc", UPLOADED_AT, file, "clip.mp4", ProcessingStatus.DONE, false, null);
    when(fileStorageService.getFileServeInfoByPublicToken("tok", null)).thenReturn(info);
    return MockMvcBuilders.standaloneSetup(
            new ImageServeController(fileStorageService, Optional.empty()))
        .build();
  }

  /**
   * A {@code StreamingResponseBody} is written from a worker thread, so the response buffer is
   * still empty when {@code perform()} returns — asserting on it directly passes or fails by luck.
   * {@code getAsyncResult()} blocks until the callable that writes the bytes has finished.
   */
  private MockHttpServletResponse completed(MockMvc mockMvc, RequestBuilder request)
      throws Exception {
    MvcResult result = mockMvc.perform(request).andReturn();
    if (result.getRequest().isAsyncStarted()) {
      result.getAsyncResult();
    }
    return result.getResponse();
  }

  private Path clip(Path tempDir) throws Exception {
    Path file = tempDir.resolve("clip.mp4");
    Files.writeString(file, "0123456789");
    return file;
  }

  @Test
  void aRangedGetIsWrittenAsPartialContent(@TempDir Path tempDir) throws Exception {
    Path file = clip(tempDir);

    MockHttpServletResponse response =
        completed(mockMvc(file), get("/api/i/tok").header(HttpHeaders.RANGE, "bytes=2-5"));

    assertEquals(HttpStatus.PARTIAL_CONTENT.value(), response.getStatus());
    assertEquals("bytes 2-5/10", response.getHeader(HttpHeaders.CONTENT_RANGE));
    assertEquals("bytes", response.getHeader(HttpHeaders.ACCEPT_RANGES));
    assertEquals("2345", response.getContentAsString());
  }

  @Test
  void anOpeningProbeRangeIsAnswered(@TempDir Path tempDir) throws Exception {
    // AVPlayer's first request. If this 500s, the iOS app shows "Failed" and never retries.
    Path file = clip(tempDir);

    MockHttpServletResponse response =
        completed(mockMvc(file), get("/api/i/tok").header(HttpHeaders.RANGE, "bytes=0-1"));

    assertEquals(HttpStatus.PARTIAL_CONTENT.value(), response.getStatus());
    assertEquals("01", response.getContentAsString());
  }

  @Test
  void anUnrangedGetStillGoesDownTheWholeBodyPath(@TempDir Path tempDir) throws Exception {
    Path file = clip(tempDir);

    MockHttpServletResponse response = completed(mockMvc(file), get("/api/i/tok"));

    assertEquals(HttpStatus.OK.value(), response.getStatus());
    assertEquals("bytes", response.getHeader(HttpHeaders.ACCEPT_RANGES));
    assertEquals("0123456789", response.getContentAsString());
  }
}
