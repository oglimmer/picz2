/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.model.StorageUsageResponse;
import com.oglimmer.photoupload.security.UserContext;
import com.oglimmer.photoupload.service.StorageQuotaService;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * How full the signed-in user's share of the instance's own storage is.
 *
 * <p>Exists so the web and iOS apps can keep a persistent "storage full" warning on screen for as
 * long as uploads to the default storage are refused (507), and take it down the moment there is
 * room again. Polled, so it stays cheap: three sums over the user's rows and nothing else.
 */
@Profile(Profiles.API)
@RestController
@RequestMapping("/api/storage-usage")
@RequiredArgsConstructor
public class StorageUsageController {

  private final StorageQuotaService storageQuotaService;
  private final UserContext userContext;

  @GetMapping
  public ResponseEntity<StorageUsageResponse> current() {
    StorageQuotaService.Usage usage = storageQuotaService.usageFor(userContext.getCurrentUser());
    return ResponseEntity.ok(
        new StorageUsageResponse(
            usage.usedBytes(), usage.quotaBytes(), usage.remainingBytes(), usage.isFull()));
  }
}
