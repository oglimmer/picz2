/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.web;

import com.oglimmer.photoupload.config.AsyncConfig;
import com.oglimmer.photoupload.config.JobsProperties;
import com.oglimmer.photoupload.service.JobQueueDepthService;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.concurrent.ThreadPoolExecutor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Rejects uploads with HTTP 503 + Retry-After when the processing queue is full, before Tomcat
 * parses the multipart body. Rejecting at the filter layer — rather than after the controller has
 * read the upload into memory — is what turns backpressure from a semantic signal into an actual
 * memory safeguard.
 *
 * <p>When the persistent jobs dispatcher is enabled, depth is read from the cached {@link
 * JobQueueDepthService} gauge. When disabled (legacy {@code @Async} path), the filter falls back
 * to the in-memory executor queue.
 */
@Component
@Slf4j
public class UploadBackpressureFilter extends OncePerRequestFilter {

  private static final int RETRY_AFTER_SECONDS = 30;

  private final ThreadPoolTaskExecutor fileProcessingExecutor;
  private final JobQueueDepthService jobQueueDepthService;
  private final JobsProperties jobsProperties;

  public UploadBackpressureFilter(
      @Qualifier(AsyncConfig.FILE_PROCESSING_EXECUTOR)
          ThreadPoolTaskExecutor fileProcessingExecutor,
      JobQueueDepthService jobQueueDepthService,
      JobsProperties jobsProperties) {
    this.fileProcessingExecutor = fileProcessingExecutor;
    this.jobQueueDepthService = jobQueueDepthService;
    this.jobsProperties = jobsProperties;
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
    if (jobsProperties.getDispatcher().isEnabled()) {
      long depth = jobQueueDepthService.getDepth();
      int threshold = jobsProperties.getBackpressure().getQueueDepthThreshold();
      if (depth >= threshold) {
        log.warn("Rejecting upload — jobs queue depth {} ≥ threshold {}", depth, threshold);
        return true;
      }
      return false;
    }

    ThreadPoolExecutor raw = fileProcessingExecutor.getThreadPoolExecutor();
    if (raw.getQueue().remainingCapacity() == 0) {
      log.warn(
          "Rejecting upload at filter — processing queue full (active={}, queued={})",
          raw.getActiveCount(),
          raw.getQueue().size());
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
