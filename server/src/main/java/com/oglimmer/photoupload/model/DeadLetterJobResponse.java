/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import com.oglimmer.photoupload.entity.ProcessingJob;
import java.time.Instant;
import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class DeadLetterJobResponse {

  private Long jobId;
  private Long assetId;
  private Integer attempts;
  private Integer maxAttempts;
  private String lastError;
  private Instant createdAt;
  private Instant startedAt;
  private Instant finishedAt;

  public static DeadLetterJobResponse from(ProcessingJob job) {
    return DeadLetterJobResponse.builder()
        .jobId(job.getId())
        .assetId(job.getAssetId())
        .attempts(job.getAttempts())
        .maxAttempts(job.getMaxAttempts())
        .lastError(job.getLastError())
        .createdAt(job.getCreatedAt())
        .startedAt(job.getStartedAt())
        .finishedAt(job.getFinishedAt())
        .build();
  }
}
