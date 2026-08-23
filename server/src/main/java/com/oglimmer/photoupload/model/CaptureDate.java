/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import com.oglimmer.photoupload.entity.CaptureDateSource;
import java.time.Instant;

/**
 * A capture time resolved to a true instant, plus the tag it came from and the UTC offset that
 * applied where the shutter fired.
 *
 * <p>{@code instant} is null exactly when {@code source} is {@link CaptureDateSource#NONE}.
 *
 * <p>{@code offsetSeconds} is what turns the instant back into the camera's own wall clock, which
 * is the only clock "which day was this taken on" can be answered from. It is null only when the
 * file gave us no way to know it; every extractor that produces an instant also produces the offset
 * it interpreted that instant with, including the fallback zone — undoing a fallback offset
 * recovers the original wall clock exactly, whether or not the fallback zone was the right guess.
 */
public record CaptureDate(Instant instant, CaptureDateSource source, Integer offsetSeconds) {

  private static final CaptureDate NONE = new CaptureDate(null, CaptureDateSource.NONE, null);

  public static CaptureDate none() {
    return NONE;
  }

  public static CaptureDate of(Instant instant, CaptureDateSource source) {
    return of(instant, source, null);
  }

  public static CaptureDate of(Instant instant, CaptureDateSource source, Integer offsetSeconds) {
    return instant == null ? NONE : new CaptureDate(instant, source, offsetSeconds);
  }

  public boolean isPresent() {
    return instant != null;
  }
}
