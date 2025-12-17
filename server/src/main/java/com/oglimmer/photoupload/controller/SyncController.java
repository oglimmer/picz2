/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.model.SyncChecksumsResponse;
import com.oglimmer.photoupload.service.SyncService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/sync")
@Slf4j
@RequiredArgsConstructor
public class SyncController {

  private final SyncService syncService;

  @GetMapping("/uploaded-checksums")
  public ResponseEntity<SyncChecksumsResponse> getUploadedChecksums(
      @RequestParam(required = true) Integer days) {

    log.info("Fetching uploaded checksums for last {} days", days);

    SyncChecksumsResponse response = syncService.getUploadedChecksums(days);

    return ResponseEntity.ok(response);
  }
}
