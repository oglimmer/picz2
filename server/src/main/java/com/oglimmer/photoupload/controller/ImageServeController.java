/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import org.springframework.context.annotation.Profile;

import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.model.FileServeInfo;
import com.oglimmer.photoupload.service.FileStorageService;
import com.oglimmer.photoupload.service.ObjectStorageService;
import java.util.Optional;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.InputStreamResource;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;

@Profile(Profiles.API)
@RestController
@RequestMapping("/api/i")
@Slf4j
public class ImageServeController {

  private static final String RETRY_AFTER_SECONDS = "2";

  private final FileStorageService fileStorageService;
  // Optional: only populated when storage.s3.enabled=true. Older deployments without MinIO still
  // boot; serving an S3-keyed row in that mode is impossible by definition.
  private final Optional<ObjectStorageService> objectStorage;

  public ImageServeController(
      FileStorageService fileStorageService, Optional<ObjectStorageService> objectStorage) {
    this.fileStorageService = fileStorageService;
    this.objectStorage = objectStorage;
  }

  @GetMapping("/{token}")
  public ResponseEntity<?> downloadFileByToken(
      @PathVariable String token, @RequestParam(value = "size", required = false) String size) {
    try {
      FileServeInfo fileInfo = fileStorageService.getFileServeInfoByPublicToken(token, size);

      // Caller asked for a derivative (thumb/medium/large) but processing hasn't produced it
      // yet. Returning the original here would either ship a HEIC the browser can't render or
      // waste bandwidth on the full-res image. Instead, return 202 Accepted with Retry-After
      // and let the client poll /api/assets/{id}/status.
      if (!fileInfo.isDerivativeReady()
          && fileInfo.getProcessingStatus() != ProcessingStatus.DONE) {
        return ResponseEntity.status(HttpStatus.ACCEPTED)
            .header(HttpHeaders.RETRY_AFTER, RETRY_AFTER_SECONDS)
            .cacheControl(CacheControl.noStore())
            .build();
      }

      if (fileInfo.getStorageKey() != null) {
        return serveFromObjectStorage(fileInfo);
      }
      return serveFromDisk(token, fileInfo);
    } catch (ResourceNotFoundException e) {
      throw e;
    } catch (Exception e) {
      log.error("Error downloading file by token", e);
      throw new RuntimeException("Error downloading file: " + e.getMessage(), e);
    }
  }

  private ResponseEntity<Resource> serveFromDisk(String token, FileServeInfo fileInfo)
      throws Exception {
    Resource resource = new UrlResource(fileInfo.getFilePath().toUri());
    if (!resource.exists()) {
      // Derivative metadata exists but the file is missing on disk — fall back to the
      // original. This shouldn't normally happen but keeps the gallery functional if a
      // derivative is deleted out-of-band.
      fileInfo = fileStorageService.getFileServeInfoByPublicToken(token, "original");
      if (fileInfo.getStorageKey() != null) {
        return serveFromObjectStorage(fileInfo);
      }
      resource = new UrlResource(fileInfo.getFilePath().toUri());
      if (!resource.exists()) {
        throw new ResourceNotFoundException("File not found");
      }
    }

    MediaType mediaType = parseMediaType(fileInfo.getMimeType());
    return ResponseEntity.ok()
        .contentType(mediaType)
        .cacheControl(CacheControl.maxAge(365, java.util.concurrent.TimeUnit.DAYS).cachePublic())
        .eTag(fileInfo.getChecksum())
        .lastModified(fileInfo.getUploadedAt())
        .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + resource.getFilename() + "\"")
        .body(resource);
  }

  private ResponseEntity<Resource> serveFromObjectStorage(FileServeInfo fileInfo) {
    ObjectStorageService os =
        objectStorage.orElseThrow(
            () ->
                new IllegalStateException(
                    "Asset path is an S3 key but ObjectStorageService is not enabled — "
                        + "check storage.s3.enabled"));

    ResponseInputStream<GetObjectResponse> stream = os.openStream(fileInfo.getStorageKey());
    GetObjectResponse meta = stream.response();
    Long contentLength = meta.contentLength();
    MediaType mediaType = parseMediaType(fileInfo.getMimeType());

    ResponseEntity.BodyBuilder builder =
        ResponseEntity.ok()
            .contentType(mediaType)
            .cacheControl(CacheControl.maxAge(365, java.util.concurrent.TimeUnit.DAYS).cachePublic())
            .eTag(fileInfo.getChecksum())
            .lastModified(fileInfo.getUploadedAt())
            .header(
                HttpHeaders.CONTENT_DISPOSITION,
                "inline; filename=\"" + safeFilenameForKey(fileInfo) + "\"");
    if (contentLength != null) {
      builder.contentLength(contentLength);
    }
    return builder.body(new InputStreamResource(stream));
  }

  private MediaType parseMediaType(String mime) {
    if (mime == null) {
      return MediaType.APPLICATION_OCTET_STREAM;
    }
    try {
      return MediaType.parseMediaType(mime);
    } catch (Exception ignored) {
      return MediaType.APPLICATION_OCTET_STREAM;
    }
  }

  private String safeFilenameForKey(FileServeInfo fileInfo) {
    // The Content-Disposition filename is for the user agent's "Save as..." dialog; the stored
    // filename is more meaningful here than the S3 key's basename (which for derivatives is
    // generic — thumb.jpg etc).
    String name = fileInfo.getFilename();
    return name != null ? name : "download";
  }
}
