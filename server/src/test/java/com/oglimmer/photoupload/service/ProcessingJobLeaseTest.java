/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.oglimmer.photoupload.entity.JobStatus;
import com.oglimmer.photoupload.entity.ProcessingJob;
import com.oglimmer.photoupload.repository.ProcessingJobRepository;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.testcontainers.containers.MariaDBContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Integration test that exercises the {@code processing_jobs} lease semantics against a real
 * MariaDB 11.8 container. Unit tests cover the state machine; this verifies that {@code SELECT ...
 * FOR UPDATE SKIP LOCKED} and the lease-expiry recovery actually behave as expected on the engine
 * we deploy to.
 *
 * <p>The dispatcher is disabled here so its scheduled poll does not race with the test harness.
 */
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.NONE,
    properties = {
      "jobs.dispatcher.enabled=false",
      "app.apns.enabled=false",
      "app.mail.enabled=false",
      "spring.mail.host=localhost"
    })
@Testcontainers
@EnabledIfSystemProperty(
    named = "run.testcontainers",
    matches = "true",
    disabledReason =
        "Requires Docker access for Testcontainers. Run with `mvn test -Drun.testcontainers=true`")
class ProcessingJobLeaseTest {

  @Container @ServiceConnection
  static final MariaDBContainer<?> MARIADB =
      new MariaDBContainer<>("mariadb:11.8").withReuse(false);

  @Autowired private JobLeaseService jobLeaseService;
  @Autowired private ProcessingJobRepository jobRepository;
  @Autowired private JdbcTemplate jdbcTemplate;

  private Long userId;
  private Long albumId;

  @BeforeEach
  void seedFixtures() {
    jdbcTemplate.update(
        "INSERT INTO users (email, password) VALUES (?, ?)", "it@example.com", "irrelevant");
    userId = jdbcTemplate.queryForObject("SELECT id FROM users WHERE email = ?", Long.class, "it@example.com");

    jdbcTemplate.update(
        "INSERT INTO albums (user_id, name) VALUES (?, ?)", userId, "it-album");
    albumId =
        jdbcTemplate.queryForObject(
            "SELECT id FROM albums WHERE user_id = ? AND name = ?", Long.class, userId, "it-album");
  }

  @AfterEach
  void cleanup() {
    // Cascade chain: deleting users cascades into albums → file_metadata → processing_jobs.
    jdbcTemplate.update("DELETE FROM processing_jobs");
    jdbcTemplate.update("DELETE FROM file_metadata");
    jdbcTemplate.update("DELETE FROM albums WHERE user_id = ?", userId);
    jdbcTemplate.update("DELETE FROM users WHERE id = ?", userId);
  }

  /**
   * Twenty assets, five worker threads pounding the queue. The strict invariant is "no asset
   * processed twice"; with {@code SKIP LOCKED} that holds even when the workers fire in lockstep.
   */
  @Test
  void manyWorkersNeverDoubleProcess() throws Exception {
    final int jobCount = 20;
    final int workerCount = 5;
    List<Long> assetIds = new ArrayList<>();
    for (int i = 0; i < jobCount; i++) {
      assetIds.add(insertQueuedJob());
    }

    ExecutorService pool = Executors.newFixedThreadPool(workerCount);
    CountDownLatch start = new CountDownLatch(1);
    List<Set<Long>> perWorker = new ArrayList<>();
    for (int i = 0; i < workerCount; i++) {
      perWorker.add(new HashSet<>());
    }

    List<java.util.concurrent.Future<?>> futures = new ArrayList<>();
    for (int w = 0; w < workerCount; w++) {
      final int workerIdx = w;
      futures.add(
          pool.submit(
              () -> {
                try {
                  start.await();
                  while (true) {
                    ProcessingJob job = jobLeaseService.leaseNext("worker-" + workerIdx, 60);
                    if (job == null) {
                      return null;
                    }
                    perWorker.get(workerIdx).add(job.getAssetId());
                    jobLeaseService.markDone(job.getId());
                  }
                } catch (InterruptedException ie) {
                  Thread.currentThread().interrupt();
                  return null;
                }
              }));
    }

    start.countDown();
    for (java.util.concurrent.Future<?> f : futures) {
      f.get(60, TimeUnit.SECONDS);
    }
    pool.shutdown();

    Set<Long> union = new HashSet<>();
    int total = 0;
    for (Set<Long> s : perWorker) {
      total += s.size();
      union.addAll(s);
    }

    assertThat(total).as("each lease must succeed exactly once").isEqualTo(jobCount);
    assertThat(union).as("no duplicates across workers").hasSize(jobCount).containsAll(assetIds);
    assertThat(jobRepository.countByStatus(JobStatus.DONE)).isEqualTo(jobCount);
    assertThat(jobRepository.countByStatus(JobStatus.QUEUED)).isZero();
  }

  /** A worker died holding the lease; once the lease expires, the job becomes leaseable again. */
  @Test
  void expiredLeaseIsRecovered() {
    Long assetId = insertFileMetadata();
    jdbcTemplate.update(
        "INSERT INTO processing_jobs (asset_id, status, attempts, max_attempts, leased_until, leased_by, created_at, started_at) "
            + "VALUES (?, 'PROCESSING', 1, 3, DATE_SUB(NOW(6), INTERVAL 5 SECOND), 'crashed-worker', NOW(6), NOW(6))",
        assetId);

    ProcessingJob recovered = jobLeaseService.leaseNext("fresh-worker", 60);

    assertThat(recovered).isNotNull();
    assertThat(recovered.getAssetId()).isEqualTo(assetId);
    assertThat(recovered.getAttempts()).isEqualTo(2); // incremented on re-acquire
    assertThat(recovered.getLeasedBy()).isEqualTo("fresh-worker");
    assertThat(recovered.getLeasedUntil()).isAfter(Instant.now());
  }

  /**
   * Re-runs the V31 backfill SQL against a fresh FAILED row to verify the upgrade-time
   * recovery path: every FAILED asset gets a QUEUED job and its own status flips back to QUEUED.
   * Flyway already executed V31 at startup against an empty table, so this exercises the
   * idempotent re-run.
   */
  @Test
  void v31BackfillEnqueuesFailedAssets() {
    Long failedAssetId = insertFileMetadata();
    jdbcTemplate.update(
        "UPDATE file_metadata SET processing_status = 'FAILED' WHERE id = ?", failedAssetId);

    jdbcTemplate.update(
        "INSERT INTO processing_jobs (asset_id, status, attempts, max_attempts, created_at) "
            + "SELECT id, 'QUEUED', 0, 3, NOW(6) FROM file_metadata WHERE processing_status = 'FAILED'");
    jdbcTemplate.update(
        "UPDATE file_metadata SET processing_status = 'QUEUED', processing_attempts = 0, "
            + "processing_error = NULL, processing_completed_at = NULL "
            + "WHERE processing_status = 'FAILED'");

    Long jobCount =
        jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM processing_jobs WHERE asset_id = ?", Long.class, failedAssetId);
    assertThat(jobCount).isEqualTo(1L);

    String resultingStatus =
        jdbcTemplate.queryForObject(
            "SELECT processing_status FROM file_metadata WHERE id = ?",
            String.class,
            failedAssetId);
    assertThat(resultingStatus).isEqualTo("QUEUED");
  }

  /** A still-leased PROCESSING row must NOT be re-acquired by another worker. */
  @Test
  void activeLeaseIsRespected() {
    Long assetId = insertFileMetadata();
    jdbcTemplate.update(
        "INSERT INTO processing_jobs (asset_id, status, attempts, max_attempts, leased_until, leased_by, created_at, started_at) "
            + "VALUES (?, 'PROCESSING', 1, 3, DATE_ADD(NOW(6), INTERVAL 5 MINUTE), 'busy-worker', NOW(6), NOW(6))",
        assetId);

    ProcessingJob result = jobLeaseService.leaseNext("intruder", 60);

    assertThat(result).as("active lease must not be stolen").isNull();
  }

  private Long insertQueuedJob() {
    Long assetId = insertFileMetadata();
    jdbcTemplate.update(
        "INSERT INTO processing_jobs (asset_id, status, attempts, max_attempts, created_at) "
            + "VALUES (?, 'QUEUED', 0, 3, NOW(6))",
        assetId);
    return assetId;
  }

  private Long insertFileMetadata() {
    String suffix = String.valueOf(System.nanoTime());
    jdbcTemplate.update(
        "INSERT INTO file_metadata "
            + "(original_name, stored_filename, file_size, mime_type, file_path, uploaded_at, "
            + "rotation, display_order, album_id, processing_status, processing_attempts) "
            + "VALUES (?, ?, ?, ?, ?, NOW(6), 0, 0, ?, 'INGESTED', 0)",
        "it-" + suffix + ".jpg",
        "stored-" + suffix + ".jpg",
        1024L,
        "image/jpeg",
        "stored-" + suffix + ".jpg",
        albumId);
    return jdbcTemplate.queryForObject(
        "SELECT id FROM file_metadata WHERE stored_filename = ?",
        Long.class,
        "stored-" + suffix + ".jpg");
  }
}
