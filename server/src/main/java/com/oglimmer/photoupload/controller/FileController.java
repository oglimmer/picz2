/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.model.CaptionRequest;
import com.oglimmer.photoupload.model.FileInfo;
import com.oglimmer.photoupload.model.FilesResponse;
import com.oglimmer.photoupload.model.MessageResponse;
import com.oglimmer.photoupload.model.ReorderRequest;
import com.oglimmer.photoupload.model.TagOperationResponse;
import com.oglimmer.photoupload.model.TagRequest;
import com.oglimmer.photoupload.service.FileStorageService;
import java.util.List;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.core.io.InputStreamResource;
import org.springframework.core.io.Resource;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
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
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;

@Profile(Profiles.API)
@RestController
@RequestMapping("/api/files")
@Slf4j
@RequiredArgsConstructor
public class FileController {

  private final FileStorageService fileStorageService;

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

  /**
   * Set or clear the owner's caption on one asset (D69). Synchronous — nothing has to be
   * re-rendered, so the updated asset comes straight back and the client can swap it in place.
   */
  @PutMapping("/{id}/caption")
  public ResponseEntity<FileInfo> updateCaption(
      @PathVariable Long id, @RequestBody CaptionRequest request) {
    return ResponseEntity.ok(fileStorageService.updateCaption(id, request.getCaption()));
  }

  @PostMapping("/{id}/rotate")
  public ResponseEntity<MessageResponse> rotateImage(@PathVariable Long id) {
    // Async since Phase 4.5: enqueues a ROTATE_LEFT job for the worker pod. Clients poll
    // GET /api/assets/{id}/status until processingStatus=DONE before refreshing the gallery.
    fileStorageService.rotateImageLeft(id);

    MessageResponse response =
        MessageResponse.builder().success(true).message("Rotation queued").build();

    return ResponseEntity.status(HttpStatus.ACCEPTED).body(response);
  }

  /**
   * Step one of the enhance flow (D82): ask for a preview. 202; the worker builds it, the client
   * polls {@code GET /api/assets/{id}/status} until DONE and then fetches it below.
   */
  @PostMapping("/{id}/enhance-preview")
  public ResponseEntity<MessageResponse> requestEnhancePreview(@PathVariable Long id) {
    fileStorageService.enqueueEnhancePreview(id);
    return ResponseEntity.status(HttpStatus.ACCEPTED)
        .body(MessageResponse.builder().success(true).message("Preview queued").build());
  }

  /**
   * Step two: the preview itself, a LARGE-sized JPEG, owner-only. {@code no-store} because the
   * same URL answers differently before the job, after it, and after a decision; the client
   * fetches it exactly once per review anyway.
   */
  @GetMapping("/{id}/enhance-preview")
  public ResponseEntity<Resource> getEnhancePreview(@PathVariable Long id) {
    ResponseInputStream<GetObjectResponse> stream = fileStorageService.openEnhancePreview(id);
    ResponseEntity.BodyBuilder builder =
        ResponseEntity.ok().contentType(MediaType.IMAGE_JPEG).cacheControl(CacheControl.noStore());
    Long contentLength = stream.response().contentLength();
    if (contentLength != null) {
      builder.contentLength(contentLength);
    }
    return builder.body(new InputStreamResource(stream));
  }

  /** Declining: throw the preview away. 204 whether or not one existed. */
  @DeleteMapping("/{id}/enhance-preview")
  public ResponseEntity<Void> discardEnhancePreview(@PathVariable Long id) {
    fileStorageService.discardEnhancePreview(id);
    return ResponseEntity.noContent().build();
  }

  /**
   * Accepting (D82), or the one-tap auto-enhance without a look (D81) — the endpoint does not
   * care. Async like rotate: enqueues an ENHANCE job for the worker pod, which rewrites the
   * original, rebuilds the derivatives and drops any preview. Clients poll {@code GET
   * /api/assets/{id}/status} until DONE and then reload, because the {@code publicToken} changes.
   */
  @PostMapping("/{id}/enhance")
  public ResponseEntity<MessageResponse> enhanceImage(@PathVariable Long id) {
    fileStorageService.enhanceImage(id);

    MessageResponse response =
        MessageResponse.builder().success(true).message("Enhancement queued").build();

    return ResponseEntity.status(HttpStatus.ACCEPTED).body(response);
  }
}
