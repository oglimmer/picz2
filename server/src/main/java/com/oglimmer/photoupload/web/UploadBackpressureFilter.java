/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.web;

import com.oglimmer.photoupload.config.JobsProperties;
import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.service.JobQueueDepthService;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Optional;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Rejects uploads with HTTP 503 + Retry-After when the processing queue is full, before Tomcat
 * parses the multipart body. Rejecting at the filter layer — rather than after the controller has
 * read the upload into memory — is what turns backpressure from a semantic signal into an actual
 * memory safeguard. Depth is read from the cached {@link JobQueueDepthService} gauge so the upload
 * hot path never hits the DB.
 */
@Profile(Profiles.API)
@Component
@Slf4j
public class UploadBackpressureFilter extends OncePerRequestFilter {

  private static final int RETRY_AFTER_SECONDS = 30;

  private final JobQueueDepthService jobQueueDepthService;
  private final JobsProperties jobsProperties;
  // Optional: present when Resilience4j is on the classpath AND a "minio" breaker is configured
  // (always true in current builds). If MinIO is OPEN we 503 the upload before parsing the body,
  // saving the multipart staging cost during an outage.
  private final Optional<CircuitBreaker> minioCircuitBreaker;

  public UploadBackpressureFilter(
      JobQueueDepthService jobQueueDepthService,
      JobsProperties jobsProperties,
      Optional<CircuitBreaker> minioCircuitBreaker) {
    this.jobQueueDepthService = jobQueueDepthService;
    this.jobsProperties = jobsProperties;
    this.minioCircuitBreaker = minioCircuitBreaker;
  }

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain chain)
      throws ServletException, IOException {

    if (!isUploadRequest(request)) {
      chain.doFilter(request, response);
      return;
    }

    if (shouldReject()) {
      response.setStatus(HttpServletResponse.SC_SERVICE_UNAVAILABLE);
      response.setHeader("Retry-After", String.valueOf(RETRY_AFTER_SECONDS));
      response.setContentType("application/json");
      response
          .getWriter()
          .write(
              "{\"status\":503,\"error\":\"Service Unavailable\","
                  + "\"message\":\"Server is currently busy processing uploads. Please retry shortly.\"}");
      return;
    }

    chain.doFilter(request, response);
  }

  private boolean shouldReject() {
    // Fail fast on MinIO outages BEFORE we look at queue depth or read the multipart body.
    // The breaker stays CLOSED in the steady state so this is a single volatile read per upload.
    if (minioCircuitBreaker.isPresent()
        && minioCircuitBreaker.get().getState() == CircuitBreaker.State.OPEN) {
      log.warn("Rejecting upload — minio circuit breaker is OPEN");
      return true;
    }

    long depth = jobQueueDepthService.getDepth();
    int threshold = jobsProperties.getBackpressure().getQueueDepthThreshold();
    if (depth >= threshold) {
      log.warn("Rejecting upload — jobs queue depth {} ≥ threshold {}", depth, threshold);
      return true;
    }
    return false;
  }

  private boolean isUploadRequest(HttpServletRequest request) {
    if (!"POST".equalsIgnoreCase(request.getMethod())) {
      return false;
    }
    String uri = request.getRequestURI();
    return uri != null && uri.startsWith("/api/upload");
  }
}
