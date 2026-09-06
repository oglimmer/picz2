/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.exception;

/**
 * Thrown when a request would add work to a {@code processing_jobs} queue that is already at its
 * backpressure threshold. Maps to HTTP 503 with {@code Retry-After} via {@link
 * GlobalExceptionHandler}.
 *
 * <p>{@code UploadBackpressureFilter} has guarded {@code POST /api/upload} on the same threshold
 * since Phase 4, but that is the legacy multipart path. Everything else that enqueues — the TUS
 * finish hook, rotate, enhance, the enhance preview, a thumbnail regen — went straight past it, so
 * a bulk enhance over a large album could put hundreds of jobs behind two workers in one click.
 * The queue itself copes; the node underneath does not, because each job pulls the original onto
 * the worker's local disk (incident 2026-09-06).
 */
public class JobQueueSaturatedException extends RuntimeException {

  public JobQueueSaturatedException(String message) {
    super(message);
  }
}
