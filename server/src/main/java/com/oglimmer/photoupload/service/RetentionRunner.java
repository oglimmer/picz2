/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Profile;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

/**
 * Phase 6 / Gap 4-finish — entry point for the nightly retention CronJob. Spring Boot starts under
 * the {@code retention} profile (via {@code SPRING_PROFILES_ACTIVE=retention} on the CronJob pod),
 * runs the sweep once, then asks Spring to exit so K8s reports the Job as Completed. Exit code is
 * the number of {@code failed} rows so a partial-failure run is visible in cron history without
 * masking it as success.
 */
@Profile(Profiles.RETENTION)
@Component
@RequiredArgsConstructor
@Slf4j
@Order(0)
public class RetentionRunner implements CommandLineRunner {

  private final RetentionService retentionService;
  private final ApplicationContext context;

  @Override
  public void run(String... args) {
    int exitCode;
    try {
      RetentionService.Result originals = retentionService.run();
      // Phase 5 follow-up — TUS upload prefix sweep runs as a second pass after the originals
      // sweep. Independent failures: a stuck S3 delete on the originals side mustn't block the
      // TUS cleanup, and vice versa. Both failure counts contribute to the exit code.
      RetentionService.Result tusCleanup = retentionService.runTusCleanup();
      exitCode = Math.min(originals.failed() + tusCleanup.failed(), 125);
    } catch (Exception e) {
      log.error("Retention sweep aborted with an unhandled exception", e);
      exitCode = 1;
    }
    final int finalExitCode = exitCode;
    System.exit(SpringApplication.exit(context, () -> finalExitCode));
  }
}
