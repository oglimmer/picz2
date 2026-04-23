/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.util;

import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.nio.file.Files;
import java.nio.file.Path;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

/**
 * Utility class to handle HTTP range requests for media files. This is essential for Safari/iOS
 * audio and video playback, which requires proper support for partial content requests (HTTP 206).
 */
@Slf4j
public class RangeRequestHandler {

  private static final int BUFFER_SIZE = 8192;

  public static ResponseEntity<StreamingResponseBody> serveFileWithRangeSupport(
      Path filePath, String rangeHeader, String contentType, String filename) throws IOException {

    if (!Files.exists(filePath)) {
      throw new IOException("File not found: " + filePath);
    }

    long fileSize = Files.size(filePath);

    if (rangeHeader == null || rangeHeader.trim().isEmpty()) {
      log.debug("Serving full file: {} (size: {})", filename, fileSize);
      return serveFullFile(filePath, contentType, filename, fileSize);
    }

    try {
      RangeInfo rangeInfo = parseRangeHeader(rangeHeader, fileSize);
      log.debug(
          "Serving partial content for {}: bytes {}-{}/{}",
          filename,
          rangeInfo.start,
          rangeInfo.end,
          fileSize);

      return servePartialFile(filePath, rangeInfo, contentType, filename, fileSize);
    } catch (IllegalArgumentException e) {
      log.warn("Invalid range header '{}' for file {}: {}", rangeHeader, filename, e.getMessage());
      HttpHeaders headers = new HttpHeaders();
      headers.add(HttpHeaders.CONTENT_RANGE, "bytes */" + fileSize);
      return ResponseEntity.status(HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
          .headers(headers)
          .build();
    }
  }

  private static ResponseEntity<StreamingResponseBody> serveFullFile(
      Path filePath, String contentType, String filename, long fileSize) {

    HttpHeaders headers = buildBaseHeaders(contentType, filename, fileSize);

    StreamingResponseBody body =
        out -> {
          try (InputStream in = filePath.toUri().toURL().openStream()) {
            in.transferTo(out);
          }
        };

    return ResponseEntity.ok().headers(headers).body(body);
  }

  private static ResponseEntity<StreamingResponseBody> servePartialFile(
      Path filePath, RangeInfo rangeInfo, String contentType, String filename, long fileSize) {

    long start = rangeInfo.start;
    long end = rangeInfo.end;
    long contentLength = end - start + 1;

    HttpHeaders headers = buildBaseHeaders(contentType, filename, fileSize);
    headers.setContentLength(contentLength);
    headers.add(HttpHeaders.CONTENT_RANGE, String.format("bytes %d-%d/%d", start, end, fileSize));

    StreamingResponseBody body =
        out -> {
          try (RandomAccessFile raf = new RandomAccessFile(filePath.toFile(), "r")) {
            raf.seek(start);
            byte[] buffer = new byte[BUFFER_SIZE];
            long remaining = contentLength;
            int read;
            while (remaining > 0
                && (read = raf.read(buffer, 0, (int) Math.min(buffer.length, remaining))) != -1) {
              out.write(buffer, 0, read);
              remaining -= read;
            }
          }
        };

    return ResponseEntity.status(HttpStatus.PARTIAL_CONTENT).headers(headers).body(body);
  }

  private static HttpHeaders buildBaseHeaders(String contentType, String filename, long fileSize) {
    HttpHeaders headers = new HttpHeaders();
    headers.setContentType(MediaType.parseMediaType(contentType));
    headers.setContentLength(fileSize);
    headers.add(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + filename + "\"");
    headers.add(HttpHeaders.ACCEPT_RANGES, "bytes");
    headers.add(HttpHeaders.CONTENT_ENCODING, "identity");
    headers.add(HttpHeaders.CACHE_CONTROL, "public, max-age=31536000, immutable");
    return headers;
  }

  private static RangeInfo parseRangeHeader(String rangeHeader, long fileSize) {
    if (!rangeHeader.startsWith("bytes=")) {
      throw new IllegalArgumentException("Range header must start with 'bytes='");
    }

    String rangeValue = rangeHeader.substring(6).trim();

    long start;
    long end;

    try {
      if (rangeValue.startsWith("-")) {
        long suffixLength = Long.parseLong(rangeValue.substring(1));
        if (suffixLength <= 0) {
          throw new IllegalArgumentException("Invalid suffix length");
        }
        start = Math.max(0, fileSize - suffixLength);
        end = fileSize - 1;
      } else {
        String[] parts = rangeValue.split("-", 2);
        if (parts.length == 0 || parts.length > 2) {
          throw new IllegalArgumentException("Invalid range format");
        }

        start = Long.parseLong(parts[0]);
        end = (parts.length == 1 || parts[1].isEmpty()) ? (fileSize - 1) : Long.parseLong(parts[1]);
      }

      if (start < 0 || end < 0 || start > end || start >= fileSize) {
        throw new IllegalArgumentException("Invalid range values");
      }

      if (end >= fileSize) {
        end = fileSize - 1;
      }

      return new RangeInfo(start, end);

    } catch (NumberFormatException e) {
      throw new IllegalArgumentException("Invalid range number format", e);
    }
  }

  private record RangeInfo(long start, long end) {}
}
