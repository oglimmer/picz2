/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

/**
 * A saved map viewport: where the map is centred and how much of the world it shows.
 *
 * <p>This is MapKit's {@code CoordinateRegion} — centre plus a span in degrees — and not a zoom
 * level, because MapKit JS has no integer zoom. {@code map.region} is both what you can read back
 * after the user pans or pinches and what you write to restore it, so the value round-trips
 * untouched. The span *is* the zoom: a smaller span shows less ground, i.e. is zoomed in.
 */
public record MapView(double centerLat, double centerLng, double spanLat, double spanLng) {

  /**
   * The smallest span we will store. Below roughly this the map is inside a single building and a
   * saved view becomes useless the moment one photo sits a street away; it is also where a mis-sent
   * 0 would land, which would otherwise persist a region no pan can escape.
   */
  private static final double MIN_SPAN_DEGREES = 0.0001d;

  /**
   * A span covering the whole world. Anything larger is the same view, so clamp rather than reject.
   */
  private static final double MAX_SPAN_LAT = 180.0d;

  private static final double MAX_SPAN_LNG = 360.0d;

  /**
   * Builds a view from raw client input, or returns null if it is not usable.
   *
   * <p>Null rather than an exception: "no saved view" is a perfectly normal state (it means frame
   * every pin), so a caller clearing the view and a caller sending nonsense want the same
   * behaviour. Out-of-range spans are clamped rather than rejected — a fully zoomed-out map
   * legitimately reports a span at the limit, and a browser rounding it a hair past should not fail
   * the save.
   */
  public static MapView of(Double centerLat, Double centerLng, Double spanLat, Double spanLng) {
    if (centerLat == null || centerLng == null || spanLat == null || spanLng == null) {
      return null;
    }
    if (!isFinite(centerLat) || !isFinite(centerLng) || !isFinite(spanLat) || !isFinite(spanLng)) {
      return null;
    }
    if (centerLat < -90 || centerLat > 90 || centerLng < -180 || centerLng > 180) {
      return null;
    }
    if (spanLat < MIN_SPAN_DEGREES || spanLng < MIN_SPAN_DEGREES) {
      return null;
    }
    return new MapView(
        centerLat, centerLng, Math.min(spanLat, MAX_SPAN_LAT), Math.min(spanLng, MAX_SPAN_LNG));
  }

  private static boolean isFinite(double value) {
    return !Double.isNaN(value) && !Double.isInfinite(value);
  }
}
