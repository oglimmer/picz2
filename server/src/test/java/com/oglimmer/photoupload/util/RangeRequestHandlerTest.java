/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.util;

import static org.junit.jupiter.api.Assertions.*;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

class RangeRequestHandlerTest {

  private Path createTempFileWithSize(Path dir, int size) throws IOException {
    byte[] data = new byte[size];
    Arrays.fill(data, (byte) 1);
    Path file = dir.resolve("test.bin");
    Files.write(file, data);
    return file;
  }

  @Test
  void serveFullFileWithoutRangeReturns200(@TempDir Path tempDir) throws IOException {
    Path file = createTempFileWithSize(tempDir, 2048);

    ResponseEntity<Resource> resp =
        RangeRequestHandler.serveFileWithRangeSupport(
            file, null, "application/octet-stream", "test.bin");

    assertEquals(HttpStatus.OK, resp.getStatusCode());
    assertEquals("application/octet-stream", resp.getHeaders().getFirst(HttpHeaders.CONTENT_TYPE));
    assertEquals("bytes", resp.getHeaders().getFirst(HttpHeaders.ACCEPT_RANGES));
    assertEquals("identity", resp.getHeaders().getFirst(HttpHeaders.CONTENT_ENCODING));
    assertEquals(
        "inline; filename=\"test.bin\"",
        resp.getHeaders().getFirst(HttpHeaders.CONTENT_DISPOSITION));
    assertEquals(2048L, resp.getHeaders().getContentLength());
  }

  @Test
  void servePartialFixedRangeReturns206(@TempDir Path tempDir) throws IOException {
    Path file = createTempFileWithSize(tempDir, 1000);

    ResponseEntity<Resource> resp =
        RangeRequestHandler.serveFileWithRangeSupport(
            file, "bytes=0-99", "application/octet-stream", "test.bin");

    assertEquals(HttpStatus.PARTIAL_CONTENT, resp.getStatusCode());
    assertEquals(100L, resp.getHeaders().getContentLength());
    assertEquals("bytes 0-99/1000", resp.getHeaders().getFirst(HttpHeaders.CONTENT_RANGE));
    assertEquals("bytes", resp.getHeaders().getFirst(HttpHeaders.ACCEPT_RANGES));
    assertEquals("identity", resp.getHeaders().getFirst(HttpHeaders.CONTENT_ENCODING));
  }

  @Test
  void servePartialSuffixRangeReturnsLastBytes(@TempDir Path tempDir) throws IOException {
    Path file = createTempFileWithSize(tempDir, 300);

    ResponseEntity<Resource> resp =
        RangeRequestHandler.serveFileWithRangeSupport(
            file, "bytes=-50", "application/octet-stream", "test.bin");

    assertEquals(HttpStatus.PARTIAL_CONTENT, resp.getStatusCode());
    assertEquals(50L, resp.getHeaders().getContentLength());
    assertEquals("bytes 250-299/300", resp.getHeaders().getFirst(HttpHeaders.CONTENT_RANGE));
  }

  @Test
  void servePartialOpenEndedRangeReturnsToEnd(@TempDir Path tempDir) throws IOException {
    Path file = createTempFileWithSize(tempDir, 512);

    ResponseEntity<Resource> resp =
        RangeRequestHandler.serveFileWithRangeSupport(
            file, "bytes=100-", "application/octet-stream", "test.bin");

    assertEquals(HttpStatus.PARTIAL_CONTENT, resp.getStatusCode());
    assertEquals(412L, resp.getHeaders().getContentLength());
    assertEquals("bytes 100-511/512", resp.getHeaders().getFirst(HttpHeaders.CONTENT_RANGE));
  }

  @Test
  void invalidRangeReturns416(@TempDir Path tempDir) throws IOException {
    Path file = createTempFileWithSize(tempDir, 256);

    ResponseEntity<Resource> resp =
        RangeRequestHandler.serveFileWithRangeSupport(
            file, "bytes=abc-def", "application/octet-stream", "test.bin");

    assertEquals(HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE, resp.getStatusCode());
    assertEquals("bytes */256", resp.getHeaders().getFirst(HttpHeaders.CONTENT_RANGE));
  }

  @Test
  void invalidUnitReturns416(@TempDir Path tempDir) throws IOException {
    Path file = createTempFileWithSize(tempDir, 128);

    ResponseEntity<Resource> resp =
        RangeRequestHandler.serveFileWithRangeSupport(
            file, "items=0-10", "application/octet-stream", "test.bin");

    assertEquals(HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE, resp.getStatusCode());
    assertEquals("bytes */128", resp.getHeaders().getFirst(HttpHeaders.CONTENT_RANGE));
  }
}
