/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.model.MessageResponse;
import com.oglimmer.photoupload.model.StorageBackendRequest;
import com.oglimmer.photoupload.model.StorageBackendResponse;
import com.oglimmer.photoupload.model.StorageBackendTestResult;
import com.oglimmer.photoupload.service.StorageBackendService;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * "Bring your own storage": a user registers an S3-compatible endpoint they pay for, and points new
 * albums at it. The instance keeps the metadata; the bytes are theirs.
 *
 * <p>The list always contains the instance's own storage as a read-only entry so a client can
 * render one picker without special-casing the default.
 */
@Profile(Profiles.API)
@RestController
@RequestMapping("/api/storage-backends")
@Slf4j
@RequiredArgsConstructor
public class StorageBackendController {

  private final StorageBackendService storageBackendService;

  @GetMapping
  public ResponseEntity<List<StorageBackendResponse>> list() {
    return ResponseEntity.ok(storageBackendService.listSelectable());
  }

  @GetMapping("/{id}")
  public ResponseEntity<StorageBackendResponse> get(@PathVariable Long id) {
    return ResponseEntity.ok(storageBackendService.get(id));
  }

  @PostMapping
  public ResponseEntity<StorageBackendResponse> create(@RequestBody StorageBackendRequest request) {
    return ResponseEntity.status(HttpStatus.CREATED).body(storageBackendService.create(request));
  }

  @PutMapping("/{id}")
  public ResponseEntity<StorageBackendResponse> update(
      @PathVariable Long id, @RequestBody StorageBackendRequest request) {
    return ResponseEntity.ok(storageBackendService.update(id, request));
  }

  @DeleteMapping("/{id}")
  public ResponseEntity<MessageResponse> delete(@PathVariable Long id) {
    storageBackendService.delete(id);
    return ResponseEntity.ok(new MessageResponse(true, "Storage removed"));
  }

  /**
   * Check settings without saving. Answers 200 with {@code ok=false} on a bad endpoint — the
   * request worked, the storage did not, and the form shows the reason inline.
   */
  @PostMapping("/test")
  public ResponseEntity<StorageBackendTestResult> test(@RequestBody StorageBackendRequest request) {
    return ResponseEntity.ok(storageBackendService.test(null, request));
  }

  @PostMapping("/{id}/test")
  public ResponseEntity<StorageBackendTestResult> testExisting(
      @PathVariable Long id, @RequestBody StorageBackendRequest request) {
    return ResponseEntity.ok(storageBackendService.test(id, request));
  }
}
