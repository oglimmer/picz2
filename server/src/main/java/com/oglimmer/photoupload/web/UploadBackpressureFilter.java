/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.web;

import com.oglimmer.photoupload.config.AsyncConfig;
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
 * Rejects uploads with HTTP 503 + Retry-After when the async processing queue is full, before
 * Tomcat parses the multipart body. Rejecting at the filter layer — rather than after the
 * controller has read the upload into memory — is what turns backpressure from a semantic signal
 * into an actual memory safeguard.
 */
@Component
@Slf4j
public class UploadBackpressureFilter extends OncePerRequestFilter {

  private static final int RETRY_AFTER_SECONDS = 30;

  private final ThreadPoolTaskExecutor fileProcessingExecutor;

  public UploadBackpressureFilter(
      @Qualifier(AsyncConfig.FILE_PROCESSING_EXECUTOR)
          ThreadPoolTaskExecutor fileProcessingExecutor) {
    this.fileProcessingExecutor = fileProcessingExecutor;
  }

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain chain)
      throws ServletException, IOException {

    if (!isUploadRequest(request)) {
      chain.doFilter(request, response);
      return;
    }

    ThreadPoolExecutor raw = fileProcessingExecutor.getThreadPoolExecutor();
    if (raw.getQueue().remainingCapacity() == 0) {
      log.warn(
          "Rejecting upload at filter — processing queue full (active={}, queued={})",
          raw.getActiveCount(),
          raw.getQueue().size());
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

  private boolean isUploadRequest(HttpServletRequest request) {
    if (!"POST".equalsIgnoreCase(request.getMethod())) {
      return false;
    }
    String uri = request.getRequestURI();
    return uri != null && uri.startsWith("/api/upload");
  }
}
