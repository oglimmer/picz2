/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.micrometer.tagged.TaggedCircuitBreakerMetrics;
import io.micrometer.core.instrument.MeterRegistry;
import java.time.Duration;
import java.util.Map;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Phase 4d wiring. Creates a single named circuit breaker ({@code minio}) that wraps every call to
 * {@link com.oglimmer.photoupload.service.ObjectStorageService}, plus the Micrometer binding so
 * breaker state and call counts surface on {@code /actuator/prometheus}.
 *
 * <p>Defaults intentionally trip aggressively — a stalled MinIO that pins Tomcat threads is a
 * worse failure mode than a couple of false-positive trips on a slow but recovering cluster. The
 * api pod's readiness probe ({@code MinioHealthIndicator}) takes it out of the Service while the
 * breaker is OPEN so retries route to a healthy replica or queue at the LB.
 */
@Configuration
public class ResilienceConfig {

  public static final String MINIO_BREAKER = "minio";

  @Bean
  public CircuitBreakerRegistry circuitBreakerRegistry() {
    CircuitBreakerConfig minioCfg =
        CircuitBreakerConfig.custom()
            // Trip after 50% of recent calls failed OR slowCallRateThreshold=100% were slow (>3s).
            .failureRateThreshold(50)
            .slowCallRateThreshold(100)
            .slowCallDurationThreshold(Duration.ofSeconds(3))
            .minimumNumberOfCalls(5)
            .slidingWindowSize(20)
            .waitDurationInOpenState(Duration.ofSeconds(10))
            .permittedNumberOfCallsInHalfOpenState(2)
            .automaticTransitionFromOpenToHalfOpenEnabled(true)
            .build();
    return CircuitBreakerRegistry.of(Map.of(MINIO_BREAKER, minioCfg));
  }

  @Bean
  public CircuitBreaker minioCircuitBreaker(CircuitBreakerRegistry registry) {
    return registry.circuitBreaker(MINIO_BREAKER);
  }

  /**
   * Binds breaker metrics on bean creation. Returning the binder so it stays a singleton bean is
   * idiomatic; the side-effect happens in this method body.
   */
  @Bean
  public TaggedCircuitBreakerMetrics circuitBreakerMicrometer(
      CircuitBreakerRegistry registry, MeterRegistry meterRegistry) {
    TaggedCircuitBreakerMetrics binder =
        TaggedCircuitBreakerMetrics.ofCircuitBreakerRegistry(registry);
    binder.bindTo(meterRegistry);
    return binder;
  }
}
