/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.profile;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.ApplicationContext;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.containers.MariaDBContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Asserts the worker profile loads only the processing-side beans. Phase 4a regression guard: any
 * future change that drops a {@code @Profile(WORKER)} or moves heavy code onto the api graph fails
 * here loudly.
 */
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.NONE,
    properties = {
      "jobs.dispatcher.enabled=false",
      "app.apns.enabled=false",
      "app.mail.enabled=false",
      "spring.mail.host=localhost"
    })
@ActiveProfiles("worker")
@Testcontainers
@EnabledIfSystemProperty(
    named = "run.testcontainers",
    matches = "true",
    disabledReason =
        "Requires Docker access for Testcontainers. Run with `mvn test -Drun.testcontainers=true`")
class WorkerProfileContextTest {

  @Container @ServiceConnection
  static final MariaDBContainer<?> MARIADB =
      new MariaDBContainer<>("mariadb:11.8").withReuse(false);

  @Autowired private ApplicationContext context;

  @Test
  void workerBeansArePresent() {
    assertThat(context.containsBean("jobDispatcher")).isTrue();
    assertThat(context.containsBean("fileProcessingService")).isTrue();
    assertThat(context.containsBean("thumbnailService")).isTrue();
    assertThat(context.containsBean("vipsThumbnailService")).isTrue();
    assertThat(context.containsBean("heicConversionService")).isTrue();
    assertThat(context.containsBean("ffmpegService")).isTrue();
    assertThat(context.containsBean("jobLeaseService")).isTrue();
  }

  @Test
  void apiBeansAreAbsent() {
    assertThat(context.containsBean("uploadController")).isFalse();
    assertThat(context.containsBean("imageServeController")).isFalse();
    assertThat(context.containsBean("fileStorageService")).isFalse();
    assertThat(context.containsBean("slideshowRecordingService")).isFalse();
    assertThat(context.containsBean("uploadBackpressureFilter")).isFalse();
    assertThat(context.containsBean("deviceTokenService")).isFalse();
    assertThat(context.containsBean("albumSubscriptionNotificationService")).isFalse();
  }

  @Test
  void sharedBeansArePresent() {
    assertThat(context.containsBean("jobEnqueueService")).isTrue();
    assertThat(context.containsBean("jobQueueDepthService")).isTrue();
    assertThat(context.containsBean("jobMetricsConfig")).isTrue();
  }
}
