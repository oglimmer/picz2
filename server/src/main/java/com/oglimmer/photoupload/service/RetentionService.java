/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.config.RetentionProperties;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Phase 6 / Gap 4-finish — purges originals from MinIO once their derivatives are durable and the
 * row is older than {@code retention.original-days}. Each row is processed in its own transaction
 * so a single S3 outage doesn't roll back the whole batch.
 *
 * <p>Idempotent: a re-run never matches the same row twice because the eligibility query filters
 * on {@code file_path IS NOT NULL}. Crash-safe in the same way — if the JVM dies between the S3
 * delete and the DB null-out, the next run will see the row again, and the second S3 delete is a
 * no-op (S3 DELETE is naturally idempotent).
 */
@Profile(Profiles.RETENTION)
@Service
@RequiredArgsConstructor
@Slf4j
public class RetentionService {

  private final FileMetadataRepository metadataRepository;
  private final ObjectStorageService objectStorage;
  private final RetentionProperties properties;
  private final PlatformTransactionManager transactionManager;

  /**
   * Result holder for the runner / tests. Counts are after the run; {@code dryRun=true} means no
   * bytes were actually deleted and no rows were updated.
   */
  public record Result(int eligible, int purged, int failed, boolean dryRun) {}

  public Result run() {
    int days = properties.getOriginalDays();
    if (days <= 0) {
      log.warn(
          "retention.original-days={} — refusing to run a same-day purge. Set a positive value.",
          days);
      return new Result(0, 0, 0, properties.isDryRun());
    }

    Instant cutoff = Instant.now().minus(Duration.ofDays(days));
    int maxRows = properties.getMaxRowsPerRun();
    log.info(
        "Retention sweep starting — cutoff={}, maxRows={}, dryRun={}",
        cutoff,
        maxRows,
        properties.isDryRun());

    List<FileMetadata> candidates =
        metadataRepository.findRetentionPurgeCandidates(cutoff, maxRows);

    int purged = 0;
    int failed = 0;
    for (FileMetadata row : candidates) {
      try {
        if (properties.isDryRun()) {
          log.info(
              "Dry run — would purge original of asset {} ({}, key={}, uploaded_at={})",
              row.getId(),
              row.getOriginalName(),
              row.getFilePath(),
              row.getUploadedAt());
        } else {
          purgeOne(row);
          purged++;
        }
      } catch (Exception e) {
        failed++;
        log.warn(
            "Failed to purge original of asset {} (key={}): {}",
            row.getId(),
            row.getFilePath(),
            e.getMessage(),
            e);
      }
    }

    log.info(
        "Retention sweep complete — eligible={}, purged={}, failed={}, dryRun={}",
        candidates.size(),
        purged,
        failed,
        properties.isDryRun());
    return new Result(candidates.size(), purged, failed, properties.isDryRun());
  }

  /**
   * Per-row TX. S3 delete first; on success the column nulls out in its own transaction. The S3
   * delete is idempotent so a crash between the two halves leaves the row purgeable on the next
   * run — which is the intended self-healing behaviour.
   */
  private void purgeOne(FileMetadata row) {
    String key = row.getFilePath();
    objectStorage.delete(key);

    new TransactionTemplate(transactionManager)
        .executeWithoutResult(
            status -> {
              FileMetadata locked =
                  metadataRepository
                      .findById(row.getId())
                      .orElseThrow(
                          () ->
                              new IllegalStateException(
                                  "Asset " + row.getId() + " vanished mid-purge"));
              locked.setFilePath(null);
              metadataRepository.save(locked);
            });
    log.info(
        "Purged original for asset {} ({}, freed S3 key {})",
        row.getId(),
        row.getOriginalName(),
        key);
  }
}
