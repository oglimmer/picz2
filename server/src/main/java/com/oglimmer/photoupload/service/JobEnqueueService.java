/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.JobsProperties;
import com.oglimmer.photoupload.entity.JobStatus;
import com.oglimmer.photoupload.entity.JobType;
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
   * Insert a QUEUED PROCESS job row for the given asset. Must be called inside the same transaction
   * as the {@code FileMetadata} insert so the queue and the asset row are atomic — either both
   * visible to the dispatcher or neither.
   */
  public ProcessingJob enqueue(Long assetId) {
    return enqueue(assetId, JobType.PROCESS);
  }

  /** Insert a QUEUED job row of the given type. Used by admin actions like rotate. */
  public ProcessingJob enqueue(Long assetId, JobType jobType) {
    ProcessingJob job = new ProcessingJob();
    job.setAssetId(assetId);
    job.setJobType(jobType);
    job.setStatus(JobStatus.QUEUED);
    job.setMaxAttempts(jobsProperties.getMaxAttempts());
    ProcessingJob saved = jobRepository.save(job);
    log.debug("Enqueued {} job {} for asset {}", jobType, saved.getId(), assetId);
    return saved;
  }

  /**
   * Insert a QUEUED job row against a slideshow recording rather than an asset. Only {@link
   * JobType#TRANSCODE_AUDIO_AAC} uses this: {@code asset_id} carries a foreign key into {@code
   * file_metadata}, so a recording id cannot be smuggled through it.
   */
  public ProcessingJob enqueueForRecording(Long recordingId, JobType jobType) {
    ProcessingJob job = new ProcessingJob();
    job.setRecordingId(recordingId);
    job.setJobType(jobType);
    job.setStatus(JobStatus.QUEUED);
    job.setMaxAttempts(jobsProperties.getMaxAttempts());
    ProcessingJob saved = jobRepository.save(job);
    log.debug("Enqueued {} job {} for recording {}", jobType, saved.getId(), recordingId);
    return saved;
  }
}
