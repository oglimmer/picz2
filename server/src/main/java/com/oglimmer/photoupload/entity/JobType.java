/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.entity;

public enum JobType {
  PROCESS,
  ROTATE_LEFT,
  /**
   * Phase 4.5 follow-up — regenerate the three image derivatives (thumbnail / medium / large) for
   * an asset whose row says it's DONE but is missing one or more derivative paths. Same fallback
   * chain as ROTATE_LEFT (original → large → medium → thumb), so it works even on retention-purged
   * assets. Same lease/retry/dead-letter machinery; no API contract change.
   */
  REGEN_THUMBNAILS
}
