/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.util;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.file.Files;
import java.nio.file.Path;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.InputStreamResource;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;

/**
 * Utility class to handle HTTP range requests for media files. This is essential for Safari/iOS
 * audio and video playback, which requires proper support for partial content requests (HTTP 206).
 */
@Slf4j
public class RangeRequestHandler {

  /**
   * Serves a file with proper HTTP range request support.
   *
   * @param filePath Path to the file to serve
   * @param rangeHeader The Range header value from the request (can be null)
   * @param contentType The MIME type of the file
   * @param filename The filename to use in Content-Disposition header
   * @return ResponseEntity with appropriate status code (200 or 206) and content
   * @throws IOException if file cannot be read
   */
  public static ResponseEntity<Resource> serveFileWithRangeSupport(
      Path filePath, String rangeHeader, String contentType, String filename) throws IOException {

    if (!Files.exists(filePath)) {
      throw new IOException("File not found: " + filePath);
    }

    long fileSize = Files.size(filePath);

    // No range header - serve entire file
    if (rangeHeader == null || rangeHeader.trim().isEmpty()) {
      log.debug("Serving full file: {} (size: {})", filename, fileSize);
      return serveFullFile(filePath, contentType, filename, fileSize);
    }

    // Parse range header
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
      // If range is invalid, return 416 Range Not Satisfiable
      HttpHeaders headers = new HttpHeaders();
      headers.add(HttpHeaders.CONTENT_RANGE, "bytes */" + fileSize);
      return ResponseEntity.status(HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
          .headers(headers)
          .build();
    }
  }

  /** Serves the complete file (HTTP 200). */
  private static ResponseEntity<Resource> serveFullFile(
      Path filePath, String contentType, String filename, long fileSize) throws IOException {

    org.springframework.core.io.Resource resource =
        new org.springframework.core.io.UrlResource(filePath.toUri());

    HttpHeaders headers = new HttpHeaders();
    headers.setContentType(MediaType.parseMediaType(contentType));
    headers.setContentLength(fileSize);
    headers.add(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + filename + "\"");
    headers.add(HttpHeaders.ACCEPT_RANGES, "bytes");

    // Prevent compression - critical for Safari audio/video playback
    headers.add(HttpHeaders.CONTENT_ENCODING, "identity");

    // Add cache headers for better Safari behavior
    headers.add(HttpHeaders.CACHE_CONTROL, "public, max-age=31536000, immutable");

    return ResponseEntity.ok().headers(headers).body(resource);
  }

  /** Serves a partial file range (HTTP 206). */
  private static ResponseEntity<Resource> servePartialFile(
      Path filePath, RangeInfo rangeInfo, String contentType, String filename, long fileSize)
      throws IOException {

    long start = rangeInfo.start;
    long end = rangeInfo.end;
    long rangeLength = end - start + 1;

    // Read the requested byte range from the file
    byte[] data = new byte[(int) rangeLength];
    try (RandomAccessFile randomAccessFile = new RandomAccessFile(filePath.toFile(), "r")) {
      randomAccessFile.seek(start);
      randomAccessFile.readFully(data);
    }

    InputStreamResource resource = new InputStreamResource(new ByteArrayInputStream(data));

    HttpHeaders headers = new HttpHeaders();
    headers.setContentType(MediaType.parseMediaType(contentType));
    headers.setContentLength(rangeLength);
    headers.add(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + filename + "\"");
    headers.add(HttpHeaders.ACCEPT_RANGES, "bytes");
    headers.add(HttpHeaders.CONTENT_RANGE, String.format("bytes %d-%d/%d", start, end, fileSize));

    // Prevent compression - critical for Safari audio/video playback
    headers.add(HttpHeaders.CONTENT_ENCODING, "identity");

    // Add cache headers for better Safari behavior
    headers.add(HttpHeaders.CACHE_CONTROL, "public, max-age=31536000, immutable");

    return ResponseEntity.status(HttpStatus.PARTIAL_CONTENT).headers(headers).body(resource);
  }

  /**
   * Parses the Range header and validates it.
   *
   * @param rangeHeader Range header value (e.g., "bytes=0-1023" or "bytes=0-")
   * @param fileSize Total size of the file
   * @return RangeInfo with start and end positions
   * @throws IllegalArgumentException if range is invalid
   */
  private static RangeInfo parseRangeHeader(String rangeHeader, long fileSize) {
    if (!rangeHeader.startsWith("bytes=")) {
      throw new IllegalArgumentException("Range header must start with 'bytes='");
    }

    String rangeValue = rangeHeader.substring(6).trim();

    long start;
    long end;

    try {
      // Suffix-byte-range-spec: "bytes=-N" (last N bytes)
      if (rangeValue.startsWith("-")) {
        long suffixLength = Long.parseLong(rangeValue.substring(1));
        if (suffixLength <= 0) {
          throw new IllegalArgumentException("Invalid suffix length");
        }
        start = Math.max(0, fileSize - suffixLength);
        end = fileSize - 1;
      } else {
        // byte-range-spec: "bytes=N-M" or open-ended "bytes=N-"
        String[] parts = rangeValue.split("-", 2);
        if (parts.length == 0 || parts.length > 2) {
          throw new IllegalArgumentException("Invalid range format");
        }

        start = Long.parseLong(parts[0]);
        end = (parts.length == 1 || parts[1].isEmpty()) ? (fileSize - 1) : Long.parseLong(parts[1]);
      }

      // Validate range
      if (start < 0 || end < 0 || start > end || start >= fileSize) {
        throw new IllegalArgumentException("Invalid range values");
      }

      // Clamp end to file size
      if (end >= fileSize) {
        end = fileSize - 1;
      }

      return new RangeInfo(start, end);

    } catch (NumberFormatException e) {
      throw new IllegalArgumentException("Invalid range number format", e);
    }
  }

  /** Simple data class to hold range information. */
  private record RangeInfo(long start, long end) {}
}
