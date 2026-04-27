/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.JobsProperties;
import com.oglimmer.photoupload.entity.JobStatus;
import com.oglimmer.photoupload.entity.ProcessingJob;
import com.oglimmer.photoupload.repository.ProcessingJobRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
@Slf4j
public class JobEnqueueService {

  private final ProcessingJobRepository jobRepository;
  private final JobsProperties jobsProperties;

  /**
   * Insert a QUEUED job row for the given asset. Must be called inside the same transaction as the
   * {@code FileMetadata} insert so the queue and the asset row are atomic — either both visible to
   * the dispatcher or neither.
   */
  public ProcessingJob enqueue(Long assetId) {
    ProcessingJob job = new ProcessingJob();
    job.setAssetId(assetId);
    job.setStatus(JobStatus.QUEUED);
    job.setMaxAttempts(jobsProperties.getMaxAttempts());
    ProcessingJob saved = jobRepository.save(job);
    log.debug("Enqueued processing job {} for asset {}", saved.getId(), assetId);
    return saved;
  }
}
