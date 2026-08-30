/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Outcome of a connection check. Returned with HTTP 200 even when {@code ok} is false: the request
 * itself succeeded, and the client renders the reason next to the form rather than as an error.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class StorageBackendTestResult {

  private boolean ok;

  /** Which step failed ({@code connect}, {@code write}, {@code read}, {@code delete}), or null. */
  private String failedStep;

  /** Human-readable reason, safe to show to the user. Null when {@code ok}. */
  private String message;
}
