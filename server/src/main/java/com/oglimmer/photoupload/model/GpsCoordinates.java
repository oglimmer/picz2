/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import com.oglimmer.photoupload.entity.GpsSource;

/**
 * A capture location in signed decimal degrees (WGS 84), plus the tag it came from.
 *
 * <p>{@code latitude} and {@code longitude} are both null exactly when {@code source} is {@link
 * GpsSource#NONE}.
 */
public record GpsCoordinates(Double latitude, Double longitude, GpsSource source) {

  private static final GpsCoordinates NONE = new GpsCoordinates(null, null, GpsSource.NONE);

  public static GpsCoordinates none() {
    return NONE;
  }

  /**
   * Rejects anything outside the valid coordinate ranges and the 0/0 null-island sentinel that
   * cameras write when they have a GPS chip but no fix — plotting those would drop a marker in the
   * Gulf of Guinea for every unlocated photo.
   */
  public static GpsCoordinates of(Double latitude, Double longitude, GpsSource source) {
    if (latitude == null || longitude == null) {
      return NONE;
    }
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      return NONE;
    }
    if (latitude == 0.0d && longitude == 0.0d) {
      return NONE;
    }
    return new GpsCoordinates(latitude, longitude, source);
  }

  public boolean isPresent() {
    return latitude != null && longitude != null;
  }
}
