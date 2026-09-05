/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.profile;

import static org.assertj.core.api.Assertions.assertThat;

import com.oglimmer.photoupload.testsupport.TestObjectStorage;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.ApplicationContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.MinIOContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.mariadb.MariaDBContainer;

/**
 * Asserts the api profile loads only the upload/serve-side beans. Phase 4a regression guard: any
 * future change that drops a {@code @Profile(API)} or wires worker-only types into the api graph
 * (without {@code Optional<>}) fails here.
 */
// MOCK, not NONE: SecurityConfig's filter chain asks for a CorsConfigurationSource, which only
// exists once the WebMvc infrastructure is loaded. With NONE the context failed to start at all,
// so this guard could never actually check a bean — it reported a CORS error instead.
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.MOCK,
    properties = {"app.apns.enabled=false", "app.mail.enabled=false", "spring.mail.host=localhost"})
@ActiveProfiles("api")
@Testcontainers
@EnabledIfSystemProperty(
    named = "run.testcontainers",
    matches = "true",
    disabledReason =
        "Requires Docker access for Testcontainers. Run with `mvn test -Drun.testcontainers=true`")
class ApiProfileContextTest {

  @Container @ServiceConnection
  static final MariaDBContainer MARIADB = new MariaDBContainer("mariadb:11.8").withReuse(false);

  @Container static final MinIOContainer MINIO = TestObjectStorage.newMinio();

  @DynamicPropertySource
  static void objectStorage(DynamicPropertyRegistry registry) {
    TestObjectStorage.register(registry, MINIO);
  }

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
    // Reverse geocoding (D38). Also the guard that caught what a compile cannot: this graph once
    // asked for a RestClient.Builder bean that Boot 4 only ships in a starter we don't depend on,
    // and the api pod refused to boot.
    assertThat(context.containsBean("geocodeController")).isTrue();
    assertThat(context.containsBean("reverseGeocodeService")).isTrue();
    assertThat(context.containsBean("appleMapsGeocodeClient")).isTrue();
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
