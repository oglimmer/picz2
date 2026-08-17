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
  REGEN_THUMBNAILS,
  /**
   * Re-read an asset's capture date from the original and nothing else. Backfills rows written by
   * the pre-timezone-aware extractor, which stored a photo's local wall clock as if it were UTC
   * while videos got a true instant — the two clocks sheared photos and videos apart in EXIF sort
   * order. Requires the original ({@code file_path}), so retention-purged rows are not eligible.
   */
  EXTRACT_CAPTURE_DATE
}
