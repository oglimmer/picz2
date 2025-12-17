/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.model.FileInfo;
import com.oglimmer.photoupload.model.FilesResponse;
import com.oglimmer.photoupload.model.MessageResponse;
import com.oglimmer.photoupload.model.ReorderRequest;
import com.oglimmer.photoupload.model.TagOperationResponse;
import com.oglimmer.photoupload.model.TagRequest;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.service.FileStorageService;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/files")
@Slf4j
@RequiredArgsConstructor
public class FileController {

  private final FileStorageService fileStorageService;
  private final FileMetadataRepository fileMetadataRepository;

  @GetMapping()
  public ResponseEntity<FilesResponse> listFiles(
      @RequestParam(required = true) Long albumId, @RequestParam(required = false) String tag) {
    List<FileInfo> files;
    // Get files for the album
    files = fileStorageService.listFilesByAlbum(albumId);

    // Optionally filter by tag within the album
    if (tag != null && !tag.isEmpty()) {
      final String filterTag = tag;
      files =
          files.stream().filter(f -> f.getTags().contains(filterTag)).collect(Collectors.toList());
    }

    long totalSize = files.stream().mapToLong(FileInfo::getSize).sum();

    FilesResponse response =
        FilesResponse.builder()
            .success(true)
            .files(files)
            .count(files.size())
            .totalSize(totalSize)
            .build();

    return ResponseEntity.ok(response);
  }

  @GetMapping("/{filename:.+}")
  public ResponseEntity<?> downloadFile(@PathVariable String filename) {
    try {
      Path filePath = fileStorageService.getFile(filename);
      Resource resource = new UrlResource(filePath.toUri());

      if (!resource.exists()) {
        throw new ResourceNotFoundException("File not found");
      }

      return ResponseEntity.ok()
          .contentType(MediaType.APPLICATION_OCTET_STREAM)
          .header(
              HttpHeaders.CONTENT_DISPOSITION,
              "attachment; filename=\"" + resource.getFilename() + "\"")
          .body(resource);

    } catch (ResourceNotFoundException e) {
      throw e;
    } catch (Exception e) {
      log.error("Error downloading file", e);
      throw new RuntimeException("Error downloading file: " + e.getMessage(), e);
    }
  }

  @DeleteMapping("/{id}")
  public ResponseEntity<MessageResponse> deleteFile(@PathVariable Long id) {
    fileStorageService.deleteFile(id);

    MessageResponse response =
        MessageResponse.builder().success(true).message("File deleted successfully").build();

    return ResponseEntity.ok(response);
  }

  @PostMapping("/{id}/tags")
  public ResponseEntity<TagOperationResponse> addTagToFile(
      @PathVariable Long id, @RequestBody TagRequest tagRequest) {
    if (tagRequest.getTagName() == null || tagRequest.getTagName().isEmpty()) {
      throw new ValidationException("Tag name is required");
    }

    List<String> updatedTags = fileStorageService.addTagToFile(id, tagRequest.getTagName());

    TagOperationResponse response =
        TagOperationResponse.builder()
            .success(true)
            .message("Tag added successfully")
            .tags(updatedTags)
            .build();

    return ResponseEntity.ok(response);
  }

  @DeleteMapping("/{id}/tags/{tagName}")
  public ResponseEntity<TagOperationResponse> removeTagFromFile(
      @PathVariable Long id, @PathVariable String tagName) {
    List<String> updatedTags = fileStorageService.removeTagFromFile(id, tagName);

    TagOperationResponse response =
        TagOperationResponse.builder()
            .success(true)
            .message("Tag removed successfully")
            .tags(updatedTags)
            .build();

    return ResponseEntity.ok(response);
  }

  @PutMapping("/reorder")
  public ResponseEntity<MessageResponse> reorderFiles(@RequestBody ReorderRequest reorderRequest) {
    if (reorderRequest.getFileIds() == null || reorderRequest.getFileIds().isEmpty()) {
      throw new ValidationException("File IDs are required");
    }

    fileStorageService.reorderFiles(reorderRequest.getFileIds());

    MessageResponse response =
        MessageResponse.builder().success(true).message("Files reordered successfully").build();

    return ResponseEntity.ok(response);
  }

  @PostMapping("/{id}/rotate")
  public ResponseEntity<MessageResponse> rotateImage(@PathVariable Long id) {
    fileStorageService.rotateImageLeft(id);

    MessageResponse response =
        MessageResponse.builder().success(true).message("Image rotated successfully").build();

    return ResponseEntity.ok(response);
  }
}
