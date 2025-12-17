/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.exception.StorageException;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.model.FileInfo;
import com.oglimmer.photoupload.model.UploadFileResponse;
import com.oglimmer.photoupload.model.UploadMultipleResponse;
import com.oglimmer.photoupload.service.FileStorageService;
import java.io.IOException;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/upload")
@Slf4j
@RequiredArgsConstructor
public class UploadController {

  private final FileStorageService fileStorageService;

  @PostMapping()
  public ResponseEntity<UploadFileResponse> uploadFile(
      @RequestParam("file") MultipartFile file,
      @RequestParam(value = "albumId", required = false) Long albumId,
      @RequestParam(value = "contentId", required = false) String contentId) {
    if (file.isEmpty()) {
      throw new ValidationException("No file uploaded");
    }

    try {
      FileInfo fileInfo = fileStorageService.storeFile(file, albumId, contentId);

      UploadFileResponse response =
          UploadFileResponse.builder().success(true).file(fileInfo).build();

      return ResponseEntity.ok(response);
    } catch (IOException e) {
      log.error("Failed to store file", e);
      throw new StorageException("Failed to store file: " + e.getMessage(), e);
    }
  }

  @PostMapping("/multiple")
  public ResponseEntity<UploadMultipleResponse> uploadMultipleFiles(
      @RequestParam("files") MultipartFile[] files,
      @RequestParam(value = "albumId", required = false) Long albumId) {
    if (files == null || files.length == 0) {
      throw new ValidationException("No files uploaded");
    }

    try {
      List<FileInfo> uploadedFiles = new java.util.ArrayList<>();
      for (MultipartFile file : files) {
        if (!file.isEmpty()) {
          // For batch uploads, contentId is not supported yet (would need array of contentIds)
          FileInfo fileInfo = fileStorageService.storeFile(file, albumId, null);
          uploadedFiles.add(fileInfo);
        }
      }

      long totalSize = uploadedFiles.stream().mapToLong(FileInfo::getSize).sum();
      log.info(
          "✅ {} file(s) uploaded (Total: {})",
          uploadedFiles.size(),
          fileStorageService.byteCountToDisplaySize(totalSize));

      UploadMultipleResponse response =
          UploadMultipleResponse.builder()
              .success(true)
              .count(uploadedFiles.size())
              .files(uploadedFiles)
              .build();

      return ResponseEntity.ok(response);
    } catch (IOException e) {
      log.error("Failed to store files", e);
      throw new StorageException("Failed to store files: " + e.getMessage(), e);
    }
  }
}
