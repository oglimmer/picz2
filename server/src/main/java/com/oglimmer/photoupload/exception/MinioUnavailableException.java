/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.exception;

/**
 * Thrown when the MinIO circuit breaker is OPEN (or a call fails through the breaker). Maps to
 * HTTP 503 with {@code Retry-After} via {@link GlobalExceptionHandler}, so iOS / web clients fall
 * into their existing back-off path instead of pinning Tomcat threads on the SDK's 90 s default
 * retry budget.
 */
public class MinioUnavailableException extends RuntimeException {

  public MinioUnavailableException(String message) {
    super(message);
  }

  public MinioUnavailableException(String message, Throwable cause) {
    super(message, cause);
  }
}
