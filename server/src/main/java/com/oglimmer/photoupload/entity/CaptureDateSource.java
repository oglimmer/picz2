/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.entity;

/**
 * How {@code file_metadata.exif_date_time_original} was derived. Persisted alongside the value so
 * the capture-date re-extract sweep can tell rows written by the current extractor from legacy rows
 * (source {@code NULL}), which were stored as a wall clock relabelled UTC.
 */
public enum CaptureDateSource {
  /** Image: EXIF DateTimeOriginal + OffsetTimeOriginal (0x9011) — an unambiguous instant. */
  EXIF_OFFSET_TIME,
  /** Image: EXIF DateTimeOriginal only, interpreted in {@code capture-date.fallback-zone}. */
  EXIF_FALLBACK_ZONE,
  /** Video: {@code com.apple.quicktime.creationdate} — local time plus an explicit UTC offset. */
  QUICKTIME_LOCAL,
  /** Video: {@code format_tags=creation_time} from the {@code mvhd} atom, already UTC. */
  MVHD_UTC,
  /** Nothing readable in the file; {@code exif_date_time_original} stays null. */
  NONE
}
