/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.entity;

/**
 * Where {@code file_metadata.gps_latitude} / {@code gps_longitude} came from. Persisted alongside
 * the values so the EXTRACT_GPS sweep can tell "never looked" ({@code NULL}) apart from "looked,
 * the file carries no location" ({@link #NONE}) — without it every pass would re-enqueue every
 * location-less asset forever.
 */
public enum GpsSource {
  /** Image: the EXIF GPS IFD (GPSLatitude/GPSLongitude plus their N/S/E/W refs). */
  EXIF_GPS,
  /** Video: {@code com.apple.quicktime.location.ISO6709}, an ISO 6709 signed-degrees string. */
  QUICKTIME_ISO6709,
  /** Nothing readable in the file; both coordinate columns stay null. */
  NONE
}
