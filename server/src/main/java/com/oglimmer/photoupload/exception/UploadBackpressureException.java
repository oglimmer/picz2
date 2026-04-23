/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.exception;

/** Signals that the server's processing backlog is full and the client should retry later. */
public class UploadBackpressureException extends RuntimeException {

  private final int retryAfterSeconds;

  public UploadBackpressureException(String message, int retryAfterSeconds) {
    super(message);
    this.retryAfterSeconds = retryAfterSeconds;
  }

  public int getRetryAfterSeconds() {
    return retryAfterSeconds;
  }
}
