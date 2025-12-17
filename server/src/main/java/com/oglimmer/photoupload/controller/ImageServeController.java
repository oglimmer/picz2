/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.model.FileServeInfo;
import com.oglimmer.photoupload.service.FileStorageService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/i")
@Slf4j
@RequiredArgsConstructor
public class ImageServeController {

  private final FileStorageService fileStorageService;

  @GetMapping("/{token}")
  public ResponseEntity<?> downloadFileByToken(
      @PathVariable String token, @RequestParam(value = "size", required = false) String size) {
    try {
      // Get file serve info by public token
      FileServeInfo fileInfo = fileStorageService.getFileServeInfoByPublicToken(token, size);

      Resource resource = new UrlResource(fileInfo.getFilePath().toUri());
      if (!resource.exists()) {
        // Fallback to original if requested size doesn't exist
        fileInfo = fileStorageService.getFileServeInfoByPublicToken(token, "original");
        resource = new UrlResource(fileInfo.getFilePath().toUri());
        if (!resource.exists()) {
          throw new ResourceNotFoundException("File not found");
        }
      }

      MediaType mediaType = MediaType.APPLICATION_OCTET_STREAM;
      try {
        mediaType = MediaType.parseMediaType(fileInfo.getMimeType());
      } catch (Exception ignored) {
      }

      // Add caching headers for performance
      return ResponseEntity.ok()
          .contentType(mediaType)
          .cacheControl(
              org.springframework.http.CacheControl.maxAge(365, java.util.concurrent.TimeUnit.DAYS)
                  .cachePublic())
          .eTag(fileInfo.getChecksum())
          .lastModified(fileInfo.getUploadedAt())
          .header(
              HttpHeaders.CONTENT_DISPOSITION,
              "inline; filename=\"" + resource.getFilename() + "\"")
          .body(resource);
    } catch (ResourceNotFoundException e) {
      throw e;
    } catch (Exception e) {
      log.error("Error downloading file by token", e);
      throw new RuntimeException("Error downloading file: " + e.getMessage(), e);
    }
  }
}
