/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.entity;

/**
 * Lifecycle of a {@code processing_jobs} row. A failed attempt goes back to QUEUED, not to a FAILED
 * state — that constant existed once, was never leased or listed again, and was folded into
 * DEAD_LETTER by V51 (D76).
 */
public enum JobStatus {
  QUEUED,
  PROCESSING,
  DONE,
  /** Every retry is spent (or the failure is permanent); an operator has to look. */
  DEAD_LETTER
}
