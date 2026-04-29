/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.health;

import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.stereotype.Component;

/**
 * Reflects the MinIO circuit-breaker state into Spring Boot's readiness group. When the breaker
 * is OPEN, this indicator goes DOWN — K8s removes the api pod from the Service for the duration,
 * so traffic stops reaching it until the breaker auto-transitions back to HALF_OPEN/CLOSED.
 *
 * <p>HALF_OPEN reports {@link Health#unknown()} (warning, not down) so a brief recovery doesn't
 * cause readiness flapping; CLOSED is healthy.
 */
@Component
public class MinioHealthIndicator implements HealthIndicator {

  private final CircuitBreaker minioCircuitBreaker;

  public MinioHealthIndicator(CircuitBreaker minioCircuitBreaker) {
    this.minioCircuitBreaker = minioCircuitBreaker;
  }

  @Override
  public Health health() {
    CircuitBreaker.State state = minioCircuitBreaker.getState();
    return switch (state) {
      case CLOSED -> Health.up().withDetail("breaker", "CLOSED").build();
      case HALF_OPEN ->
          Health.unknown().withDetail("breaker", "HALF_OPEN").build();
      case OPEN, FORCED_OPEN ->
          Health.down().withDetail("breaker", state.name()).build();
      case DISABLED, METRICS_ONLY -> Health.up().withDetail("breaker", state.name()).build();
    };
  }
}
