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
 * Asserts the api profile loads only the upload/serve-side beans. Phase 4a regression guard: any
 * future change that drops a {@code @Profile(API)} or wires worker-only types into the api graph
 * (without {@code Optional<>}) fails here.
 */
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.NONE,
    properties = {
      // Dispatcher must be enabled on api-only deploys; the legacy @Async branch in
      // FileStorageService would otherwise demand the worker-only FileProcessingService.
      "jobs.dispatcher.enabled=true",
      "app.apns.enabled=false",
      "app.mail.enabled=false",
      "spring.mail.host=localhost"
    })
@ActiveProfiles("api")
@Testcontainers
@EnabledIfSystemProperty(
    named = "run.testcontainers",
    matches = "true",
    disabledReason =
        "Requires Docker access for Testcontainers. Run with `mvn test -Drun.testcontainers=true`")
class ApiProfileContextTest {

  @Container @ServiceConnection
  static final MariaDBContainer<?> MARIADB =
      new MariaDBContainer<>("mariadb:11.8").withReuse(false);

  @Autowired private ApplicationContext context;

  @Test
  void apiBeansArePresent() {
    assertThat(context.containsBean("uploadController")).isTrue();
    assertThat(context.containsBean("imageServeController")).isTrue();
    assertThat(context.containsBean("fileStorageService")).isTrue();
    assertThat(context.containsBean("slideshowRecordingService")).isTrue();
    assertThat(context.containsBean("uploadBackpressureFilter")).isTrue();
    assertThat(context.containsBean("deviceTokenService")).isTrue();
    assertThat(context.containsBean("albumSubscriptionNotificationService")).isTrue();
  }

  @Test
  void workerBeansAreAbsent() {
    assertThat(context.containsBean("jobDispatcher")).isFalse();
    assertThat(context.containsBean("fileProcessingService")).isFalse();
    assertThat(context.containsBean("thumbnailService")).isFalse();
    assertThat(context.containsBean("vipsThumbnailService")).isFalse();
    assertThat(context.containsBean("heicConversionService")).isFalse();
    assertThat(context.containsBean("ffmpegService")).isFalse();
    assertThat(context.containsBean("jobLeaseService")).isFalse();
  }

  @Test
  void sharedBeansArePresent() {
    assertThat(context.containsBean("jobEnqueueService")).isTrue();
    assertThat(context.containsBean("jobQueueDepthService")).isTrue();
    assertThat(context.containsBean("jobMetricsConfig")).isTrue();
  }
}
