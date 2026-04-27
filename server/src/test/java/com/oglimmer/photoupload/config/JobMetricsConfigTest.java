/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.entity.JobStatus;
import com.oglimmer.photoupload.service.JobQueueDepthService;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

class JobMetricsConfigTest {

  @Test
  void registersOneGaugePerStatusAndReadsFromCache() {
    SimpleMeterRegistry registry = new SimpleMeterRegistry();
    JobQueueDepthService depth = mock(JobQueueDepthService.class);
    when(depth.getCount(JobStatus.QUEUED)).thenReturn(7L);
    when(depth.getCount(JobStatus.PROCESSING)).thenReturn(1L);
    when(depth.getCount(JobStatus.DEAD_LETTER)).thenReturn(2L);
    when(depth.getCount(JobStatus.DONE)).thenReturn(0L);
    when(depth.getCount(JobStatus.FAILED)).thenReturn(0L);

    JobMetricsConfig config = new JobMetricsConfig(registry, depth);
    config.registerGauges();

    for (JobStatus status : JobStatus.values()) {
      Gauge g =
          registry
              .find(JobMetricsConfig.METRIC_NAME)
              .tag("status", status.name())
              .gauge();
      assertThat(g).as("gauge for status %s", status).isNotNull();
    }

    Gauge queued =
        registry.find(JobMetricsConfig.METRIC_NAME).tag("status", "QUEUED").gauge();
    Gauge deadLetter =
        registry.find(JobMetricsConfig.METRIC_NAME).tag("status", "DEAD_LETTER").gauge();
    assertThat(queued.value()).isEqualTo(7.0);
    assertThat(deadLetter.value()).isEqualTo(2.0);
  }
}
