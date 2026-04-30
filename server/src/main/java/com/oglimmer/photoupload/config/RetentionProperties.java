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
}
