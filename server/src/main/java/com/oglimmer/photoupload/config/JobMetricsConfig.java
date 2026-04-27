/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import com.oglimmer.photoupload.entity.JobStatus;
import com.oglimmer.photoupload.service.JobQueueDepthService;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Configuration;

/**
 * Registers one Micrometer {@link Gauge} per {@link JobStatus} value, all sharing the metric name
 * {@code photoupload.jobs.queued} and tagged by {@code status}. Each gauge is pull-driven: when
 * Prometheus scrapes {@code /actuator/prometheus}, Micrometer asks the supplier for the current
 * value, which reads the cached snapshot in {@link JobQueueDepthService}. There's no per-scrape
 * DB cost.
 */
@Configuration
@RequiredArgsConstructor
public class JobMetricsConfig {

  static final String METRIC_NAME = "photoupload.jobs.queued";

  private final MeterRegistry meterRegistry;
  private final JobQueueDepthService jobQueueDepthService;

  @PostConstruct
  void registerGauges() {
    for (JobStatus status : JobStatus.values()) {
      Gauge.builder(METRIC_NAME, jobQueueDepthService, svc -> svc.getCount(status))
          .description("Number of processing_jobs rows in the given lifecycle status")
          .tag("status", status.name())
          .register(meterRegistry);
    }
  }
}
