/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.JobsProperties;
import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.JobType;
import com.oglimmer.photoupload.entity.ProcessingJob;
import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import java.lang.management.ManagementFactory;
import java.util.concurrent.Semaphore;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Polls the {@code processing_jobs} table at a fixed interval, leases the next available row, and
 * runs {@link FileProcessingService#processFile(Long)} synchronously. The lease ({@code
 * status=PROCESSING}, {@code leased_until=NOW()+lease.seconds}) is committed before the work
 * starts, so a crashed worker's job becomes leaseable again once the lease expires.
 *
 * <p>A {@link Semaphore} of size 1 per pod guarantees we never run two encodes in parallel — image
 * and video tooling already saturates the Pi's memory budget at {@code Semaphore(1)}, per D13.
 */
@Component
@Profile(Profiles.WORKER)
@Slf4j
public class JobDispatcher {

  private final JobLeaseService jobLeaseService;
  private final FileProcessingService fileProcessingService;
  private final FileMetadataRepository fileMetadataRepository;
  private final JobsProperties jobsProperties;
  private final Semaphore semaphore = new Semaphore(1);
  private final String workerId;

  public JobDispatcher(
      JobLeaseService jobLeaseService,
      FileProcessingService fileProcessingService,
      FileMetadataRepository fileMetadataRepository,
      JobsProperties jobsProperties) {
    this.jobLeaseService = jobLeaseService;
    this.fileProcessingService = fileProcessingService;
    this.fileMetadataRepository = fileMetadataRepository;
    this.jobsProperties = jobsProperties;
    this.workerId = computeWorkerId();
    log.info("JobDispatcher initialised (workerId={})", this.workerId);
  }

  @Scheduled(fixedDelayString = "${jobs.poll.interval-ms:2000}")
  public void poll() {
    if (!jobsProperties.getDispatcher().isEnabled()) {
      return;
    }
    if (!semaphore.tryAcquire()) {
      // Previous tick is still running. Spring's @Scheduled with fixedDelay already serialises
      // invocations on a single scheduler thread, but the explicit guard makes the intent clear
      // and survives a future move to a thread-pooled scheduler.
      return;
    }
    try {
      pollOnce();
    } catch (Exception e) {
      log.error("JobDispatcher tick failed", e);
    } finally {
      semaphore.release();
    }
  }

  private void pollOnce() {
    ProcessingJob job =
        jobLeaseService.leaseNext(workerId, jobsProperties.getLease().getSeconds());
    if (job == null) {
      return;
    }
    JobType jobType = job.getJobType() != null ? job.getJobType() : JobType.PROCESS;
    log.info(
        "Leased {} job {} (asset {}, attempt {}/{})",
        jobType,
        job.getId(),
        job.getAssetId(),
        job.getAttempts(),
        job.getMaxAttempts());

    try {
      switch (jobType) {
        case PROCESS -> fileProcessingService.processFile(job.getAssetId());
        case ROTATE_LEFT -> fileProcessingService.rotateAndReprocess(job.getAssetId());
      }
    } catch (Exception e) {
      // The service-layer methods catch their own exceptions today, but treat any leak
      // defensively so the lease is released cleanly.
      log.error(
          "{} threw for asset {}: {}", jobType, job.getAssetId(), e.getMessage(), e);
      jobLeaseService.markFailedOrDeadLetter(job.getId(), e.toString());
      return;
    }

    // FileProcessingService updates FileMetadata.processingStatus to DONE / FAILED. Mirror that
    // onto the job row so the queue and the asset row agree.
    FileMetadata asset = fileMetadataRepository.findById(job.getAssetId()).orElse(null);
    if (asset == null) {
      log.warn("Asset {} disappeared during processing of job {}", job.getAssetId(), job.getId());
      jobLeaseService.markFailedOrDeadLetter(job.getId(), "Asset disappeared during processing");
      return;
    }
    if (asset.getProcessingStatus() == ProcessingStatus.DONE) {
      jobLeaseService.markDone(job.getId());
    } else {
      String error = asset.getProcessingError();
      jobLeaseService.markFailedOrDeadLetter(
          job.getId(), error != null ? error : "Unknown processing failure");
    }
  }

  /**
   * Identifies the worker that holds a lease so we can correlate logs across replicas. {@code
   * HOSTNAME-PID} is enough — the audit trail is in app logs, not the row itself.
   */
  private String computeWorkerId() {
    String host = System.getenv().getOrDefault("HOSTNAME", "unknown");
    String jvmName = ManagementFactory.getRuntimeMXBean().getName();
    String pid = jvmName.contains("@") ? jvmName.substring(0, jvmName.indexOf('@')) : jvmName;
    String id = host + "-" + pid;
    return id.length() > 128 ? id.substring(0, 128) : id;
  }
}
