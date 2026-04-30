/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.JobStatus;
import com.oglimmer.photoupload.repository.ProcessingJobRepository;
import jakarta.annotation.PostConstruct;
import java.util.EnumMap;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * Cached per-status counts of the {@code processing_jobs} table. One scheduled query refreshes a
 * volatile snapshot consumed by:
 *
 * <ul>
 *   <li>{@link com.oglimmer.photoupload.web.UploadBackpressureFilter} — sums QUEUED + PROCESSING
 *       so the upload hot path never hits the DB.
 *   <li>The Prometheus gauge for {@code photoupload.jobs.queued{status=...}} — exposed via
 *       Micrometer so alerts can fire on QUEUED depth or any DEAD_LETTER row.
 * </ul>
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class JobQueueDepthService {

  private final ProcessingJobRepository jobRepository;

  /**
   * Snapshot map. Replaced atomically (not mutated in place) so readers either see the previous
   * tick or the new one — never a half-updated map.
   */
  private volatile Map<JobStatus, Long> snapshot = emptySnapshot();

  @PostConstruct
  void primeOnStartup() {
    refresh();
  }

  @Scheduled(fixedDelayString = "${jobs.backpressure.refresh-ms:1000}")
  public void refresh() {
    try {
      Map<JobStatus, Long> next = emptySnapshot();
      for (Object[] row : jobRepository.countAllByStatusGrouped()) {
        JobStatus status = (JobStatus) row[0];
        Long count = (Long) row[1];
        next.put(status, count);
      }
      snapshot = next;
    } catch (Exception e) {
      // A DB blip should not crash the scheduler. Stale snapshot for one tick is acceptable.
      log.warn("Failed to refresh job-queue depth: {}", e.getMessage());
    }
  }

  /** Sum of QUEUED + PROCESSING — the figure backpressure cares about. */
  public long getDepth() {
    Map<JobStatus, Long> s = snapshot;
    return s.getOrDefault(JobStatus.QUEUED, 0L) + s.getOrDefault(JobStatus.PROCESSING, 0L);
  }

  /** Per-status count read by the Prometheus gauge. Never null; absent statuses report 0. */
  public long getCount(JobStatus status) {
    return snapshot.getOrDefault(status, 0L);
  }

  private static Map<JobStatus, Long> emptySnapshot() {
    Map<JobStatus, Long> m = new EnumMap<>(JobStatus.class);
    for (JobStatus s : JobStatus.values()) {
      m.put(s, 0L);
    }
    return m;
  }
}
