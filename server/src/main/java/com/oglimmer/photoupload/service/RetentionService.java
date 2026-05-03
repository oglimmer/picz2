/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.config.RetentionProperties;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.storage.StoragePaths;
import java.time.Duration;
import java.time.Instant;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
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

  /**
   * Phase 5 follow-up — second pass that deletes abandoned TUS uploads under the
   * {@code tus-uploads/} prefix. tusd 2.x has no in-process expiry and our MinIO is single-drive
   * (no bucket lifecycle), so this is the only GC mechanism for stale incomplete uploads.
   *
   * <p>Self-healing: a successful TUS upload's tus-uploads/{uuid} is deleted by the post-finish
   * hook in {@link FileStorageService#registerTusUpload}, so the prefix is normally near-empty.
   * Anything still here older than {@link RetentionProperties#getTusUploadDays()} is something
   * the client never finished — safe to delete.
   *
   * <p>No DB side: this is purely an S3 operation. Delete failures are counted but don't abort
   * the sweep — the next nightly run will retry.
   */
  public Result runTusCleanup() {
    int days = properties.getTusUploadDays();
    if (days <= 0) {
      log.warn(
          "retention.tus-upload-days={} — refusing to run a same-day TUS sweep. Set a positive value.",
          days);
      return new Result(0, 0, 0, properties.isDryRun());
    }

    Instant cutoff = Instant.now().minus(Duration.ofDays(days));
    int maxRows = properties.getMaxRowsPerRun();
    log.info(
        "TUS cleanup sweep starting — prefix=tus-uploads/, cutoff={}, maxRows={}, dryRun={}",
        cutoff,
        maxRows,
        properties.isDryRun());

    List<String> candidates = objectStorage.listKeysOlderThan("tus-uploads/", cutoff);
    if (candidates.size() > maxRows) {
      log.warn(
          "TUS cleanup eligibility ({}) exceeds maxRowsPerRun ({}) — truncating to cap",
          candidates.size(),
          maxRows);
      candidates = candidates.subList(0, maxRows);
    }

    int purged = 0;
    int failed = 0;
    for (String key : candidates) {
      try {
        if (properties.isDryRun()) {
          log.info("Dry run — would delete tus-uploads object {}", key);
        } else {
          objectStorage.delete(key);
          purged++;
        }
      } catch (Exception e) {
        failed++;
        log.warn("Failed to delete tus-uploads object {}: {}", key, e.getMessage(), e);
      }
    }

    log.info(
        "TUS cleanup sweep complete — eligible={}, purged={}, failed={}, dryRun={}",
        candidates.size(),
        purged,
        failed,
        properties.isDryRun());
    return new Result(candidates.size(), purged, failed, properties.isDryRun());
  }

  /**
   * Phase 5 follow-up — third pass that deletes orphan {@code originals/} keys: bytes that exist
   * in MinIO but no {@code file_metadata.file_path} row points at them. Two known failure modes
   * produce orphans:
   * <ul>
   *   <li>TUS post-finish hook crashes between the {@code S3 COPY} (tus-uploads → originals) and
   *       the row-insert TX. {@code FileStorageService.registerTusUpload} explicitly defers
   *       cleanup to "the orphan job".</li>
   *   <li>Multipart upload {@code FileStorageService.storeFile} crashes between the streaming PUT
   *       and the same row-insert TX.</li>
   * </ul>
   * Algorithm: load the set of every {@code originals/} key currently referenced by any row, list
   * {@code originals/} from S3 with a {@code lastModified < now - graceHours} filter, and delete
   * the difference. The grace window prevents false positives from racing in-flight uploads.
   *
   * <p>The originals-purge sweep ({@link #run()}) leaves {@code file_path = NULL} on rows whose
   * S3 object it has deleted, so retention-purged rows correctly do not appear in the live-key
   * set — but their S3 keys are gone too, so they don't appear in the listing either. No
   * interference between the two passes.
   *
   * <p>No DB side: pure S3 operation. Failures are counted but don't abort.
   */
  public Result runOriginalsOrphanCleanup() {
    int graceHours = properties.getOrphanGraceHours();
    if (graceHours <= 0) {
      log.warn(
          "retention.orphan-grace-hours={} — refusing to run orphan sweep. Set a positive value.",
          graceHours);
      return new Result(0, 0, 0, properties.isDryRun());
    }

    Instant cutoff = Instant.now().minus(Duration.ofHours(graceHours));
    int maxRows = properties.getMaxRowsPerRun();
    log.info(
        "Orphan-detection sweep starting — prefix={}, graceCutoff={}, maxRows={}, dryRun={}",
        StoragePaths.ORIGINALS_PREFIX,
        cutoff,
        maxRows,
        properties.isDryRun());

    Set<String> liveKeys = new HashSet<>(metadataRepository.findAllOriginalsKeys());
    List<String> aged = objectStorage.listKeysOlderThan(StoragePaths.ORIGINALS_PREFIX, cutoff);

    List<String> orphans = new java.util.ArrayList<>();
    for (String key : aged) {
      if (!liveKeys.contains(key)) {
        orphans.add(key);
      }
    }
    if (orphans.size() > maxRows) {
      log.warn(
          "Orphan eligibility ({}) exceeds maxRowsPerRun ({}) — truncating to cap",
          orphans.size(),
          maxRows);
      orphans = orphans.subList(0, maxRows);
    }

    int purged = 0;
    int failed = 0;
    for (String key : orphans) {
      try {
        if (properties.isDryRun()) {
          log.info("Dry run — would delete orphan original {}", key);
        } else {
          objectStorage.delete(key);
          purged++;
          log.info("Deleted orphan original {}", key);
        }
      } catch (Exception e) {
        failed++;
        log.warn("Failed to delete orphan original {}: {}", key, e.getMessage(), e);
      }
    }

    log.info(
        "Orphan-detection sweep complete — listed={}, liveRows={}, eligible={}, purged={}, failed={}, dryRun={}",
        aged.size(),
        liveKeys.size(),
        orphans.size(),
        purged,
        failed,
        properties.isDryRun());
    return new Result(orphans.size(), purged, failed, properties.isDryRun());
  }
}
