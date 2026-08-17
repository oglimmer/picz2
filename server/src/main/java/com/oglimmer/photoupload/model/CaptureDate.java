/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import com.oglimmer.photoupload.entity.CaptureDateSource;
import java.time.Instant;

/**
 * A capture time resolved to a true instant, plus the tag it came from.
 *
 * <p>{@code instant} is null exactly when {@code source} is {@link CaptureDateSource#NONE}.
 */
public record CaptureDate(Instant instant, CaptureDateSource source) {

  private static final CaptureDate NONE = new CaptureDate(null, CaptureDateSource.NONE);

  public static CaptureDate none() {
    return NONE;
  }

  public static CaptureDate of(Instant instant, CaptureDateSource source) {
    return instant == null ? NONE : new CaptureDate(instant, source);
  }

  public boolean isPresent() {
    return instant != null;
  }
}
