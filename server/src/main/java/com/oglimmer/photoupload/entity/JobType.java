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
  EXTRACT_CAPTURE_DATE,
  /**
   * Read an asset's capture location from the original and nothing else. Backfills every row that
   * predates the map filter, which had nowhere to store coordinates. Requires the original ({@code
   * file_path}) — the EXIF GPS IFD and the QuickTime location atom exist only there — so
   * retention-purged rows are not eligible.
   */
  EXTRACT_GPS,
  /**
   * Produce the AAC ({@code .m4a}) sibling of a slideshow recording's audio, which is the only
   * rendition Apple clients can decode.
   *
   * <p>Unlike every other job type it works on a recording, not an asset: {@code asset_id} is null
   * and {@code recording_id} (V42) names the {@code slideshow_recordings} row — the queue table is
   * reused rather than duplicated, and the dispatcher special-cases the completion check
   * accordingly. Enqueued by the api pod when an iOS client asks for a recording whose sibling is
   * missing; the transcode runs for about a minute on the Pi, which is why it must never happen
   * inside the request.
   */
  TRANSCODE_AUDIO_AAC
}
