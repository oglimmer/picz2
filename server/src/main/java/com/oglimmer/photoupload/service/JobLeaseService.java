/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.JobStatus;
import com.oglimmer.photoupload.entity.ProcessingJob;
import com.oglimmer.photoupload.repository.ProcessingJobRepository;
import java.time.Instant;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Short-lived transactional helpers for the dispatcher. Each method is its own transaction so the
 * long-running processing step in {@link JobDispatcher} runs outside any DB lock.
 */
@Service
@Profile(Profiles.WORKER)
@RequiredArgsConstructor
@Slf4j
public class JobLeaseService {

  private final ProcessingJobRepository jobRepository;

  /**
   * Atomically claim the next leaseable job for {@code workerId}. The native query uses {@code
   * SELECT ... FOR UPDATE SKIP LOCKED} so concurrent workers never race for the same row.
   *
   * @return the leased job (already in PROCESSING with attempts incremented) or {@code null} if
   *     the queue is empty.
   */
  @Transactional
  public ProcessingJob leaseNext(String workerId, int leaseSeconds) {
    Long id = jobRepository.findNextLeaseableId().orElse(null);
    if (id == null) {
      return null;
    }
    int updated = jobRepository.acquireLease(id, workerId, leaseSeconds);
    if (updated != 1) {
      // Should not happen — we just selected this row inside the same TX with SKIP LOCKED.
      log.warn("acquireLease updated {} rows for job {}", updated, id);
      return null;
    }
    // Re-read so the caller sees the updated attempts/leased_until/started_at.
    return jobRepository.findById(id).orElse(null);
  }

  @Transactional
  public void markDone(Long jobId) {
    ProcessingJob job = jobRepository.findById(jobId).orElse(null);
    if (job == null) {
      log.warn("markDone: job {} disappeared (asset deleted?)", jobId);
      return;
    }
    job.setStatus(JobStatus.DONE);
    job.setFinishedAt(Instant.now());
    job.setLeasedUntil(null);
    job.setLeasedBy(null);
    job.setLastError(null);
    jobRepository.save(job);
  }

  /**
   * Mark a failed attempt. If the job is already at {@code max_attempts}, it goes to {@code
   * DEAD_LETTER} instead — the original blob is preserved (per D15) so the admin can re-enqueue.
   */
  @Transactional
  public void markFailedOrDeadLetter(Long jobId, String errorMessage) {
    ProcessingJob job = jobRepository.findById(jobId).orElse(null);
    if (job == null) {
      log.warn("markFailedOrDeadLetter: job {} disappeared", jobId);
      return;
    }
    boolean exhausted = job.getAttempts() != null && job.getAttempts() >= job.getMaxAttempts();
    job.setStatus(exhausted ? JobStatus.DEAD_LETTER : JobStatus.FAILED);
    job.setFinishedAt(Instant.now());
    job.setLeasedUntil(null);
    job.setLeasedBy(null);
    job.setLastError(truncate(errorMessage));
    jobRepository.save(job);
    if (exhausted) {
      log.error("Job {} (asset {}) → DEAD_LETTER after {} attempts", jobId, job.getAssetId(), job.getAttempts());
    }
  }

  private String truncate(String s) {
    if (s == null) {
      return null;
    }
    return s.length() > 4000 ? s.substring(0, 4000) : s;
  }
}
