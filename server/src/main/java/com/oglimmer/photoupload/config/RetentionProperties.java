/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * Phase 6 / Gap 4-finish — knobs for the nightly retention CronJob. Only the {@code retention}
 * profile (one-shot RetentionRunner) actually consumes these; loading the bean unconditionally
 * keeps integration-test parity simple.
 */
@Configuration
@ConfigurationProperties(prefix = "retention")
@Data
public class RetentionProperties {

  /**
   * Originals older than this are eligible for purge from MinIO once their derivatives are durable
   * and {@code processing_status='DONE'}. Conservative default per the plan — 7 days gives the
   * alert-first phase room to catch any wrong-shaped backfill before bytes are actually deleted.
   */
  private int originalDays = 7;

  /**
   * Soft cap on rows touched per run. Prevents a runaway purge if the cutoff is misconfigured (e.g.
   * {@code original-days=0}) — operator can review the result and re-run.
   */
  private int maxRowsPerRun = 5000;

  /**
   * When true, log eligible rows and report counts but skip the actual S3 delete + DB update. Use
   * this on the first cron firing in production to validate eligibility before bytes go.
   */
  private boolean dryRun = false;

  /**
   * Phase 5 follow-up — incomplete TUS uploads under the {@code tus-uploads/} prefix that have been
   * sitting longer than this are eligible for deletion. tusd 2.x removed its in-process
   * {@code -expire-after} flag and the platform-side MinIO is single-drive (lifecycle API
   * unsupported), so this server-side sweep is the only GC mechanism for abandoned TUS uploads.
   * Same nightly CronJob as the originals sweep; runs as a second pass after originals.
   */
  private int tusUploadDays = 7;

  /**
   * Phase 5 follow-up — orphan-detection grace window. An {@code originals/} key whose
   * {@code LastModified} is older than this *and* has no {@code file_metadata.file_path} row
   * pointing at it is treated as an orphan and deleted. The grace covers two race windows:
   * <ul>
   *   <li>TUS post-finish hook between {@code S3 COPY} and {@code file_metadata INSERT}
   *       (sub-second normally, ~1s worst-case observed).</li>
   *   <li>Multipart upload between {@code S3 PUT} and the row-insert TX commit (same shape).</li>
   * </ul>
   * Default is hours rather than days so a real orphan from a crashed hook doesn't sit around
   * occupying storage for a week, but it's wide enough that no in-flight upload can be misclassified.
   */
  private int orphanGraceHours = 24;
}
