/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.model.SyncChecksumsResponse;
import com.oglimmer.photoupload.model.SyncContentIdsResponse;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Service
@Slf4j
@RequiredArgsConstructor
public class SyncService {

  private final FileMetadataRepository fileMetadataRepository;
  private final UserContext userContext;

  /**
   * ContentIds this user has uploaded in the last {@code days} days.
   *
   * <p>The reconciliation that survives a reinstall. {@link #getUploadedChecksums(Integer)} is only
   * useful to a client that still has its local checksum→asset map, which a freshly installed app
   * does not — so it did nothing in exactly the situation it existed for. Both are kept: rows
   * uploaded before the client sent a contentId have none, and only the checksum path can recognise
   * those.
   */
  public SyncContentIdsResponse getUploadedContentIds(Integer days) {
    User currentUser = userContext.getCurrentUser();
    Instant cutoffDate = Instant.now().minus(days, ChronoUnit.DAYS);

    List<String> contentIds =
        fileMetadataRepository
            .findContentIdsByUserAndUploadedAtAfter(currentUser.getId(), cutoffDate)
            .stream()
            .filter(contentId -> contentId != null && !contentId.isBlank())
            .toList();

    log.info(
        "Found {} contentIds for user {} in last {} days",
        contentIds.size(),
        currentUser.getEmail(),
        days);

    return SyncContentIdsResponse.builder()
        .success(true)
        .contentIds(contentIds)
        .count(contentIds.size())
        .build();
  }

  public SyncChecksumsResponse getUploadedChecksums(Integer days) {
    User currentUser = userContext.getCurrentUser();

    // Calculate the cutoff date
    Instant cutoffDate = Instant.now().minus(days, ChronoUnit.DAYS);

    log.info(
        "Fetching checksums for user {} uploaded since {}", currentUser.getEmail(), cutoffDate);

    // Fetch checksums for files uploaded by this user since the cutoff date
    List<String> checksums =
        fileMetadataRepository.findChecksumsByUserAndUploadedAtAfter(
            currentUser.getId(), cutoffDate);

    // Filter out null checksums
    checksums =
        checksums.stream().filter(checksum -> checksum != null && !checksum.isEmpty()).toList();

    log.info(
        "Found {} checksums for user {} in last {} days",
        checksums.size(),
        currentUser.getEmail(),
        days);

    return SyncChecksumsResponse.builder()
        .success(true)
        .checksums(checksums)
        .count(checksums.size())
        .build();
  }
}
