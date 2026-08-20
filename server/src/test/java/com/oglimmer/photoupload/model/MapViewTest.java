/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

class MapViewTest {

  @Test
  void acceptsAViewTheBrowserActuallySends() {
    MapView view = MapView.of(43.6532d, -79.3832d, 0.35d, 0.5d);

    assertNotNull(view);
    assertEquals(43.6532d, view.centerLat());
    assertEquals(-79.3832d, view.centerLng());
    assertEquals(0.35d, view.spanLat());
    assertEquals(0.5d, view.spanLng());
  }

  @Test
  void rejectsAPartialView() {
    // A field dropped in transit must not become 0 — that centres the map on null island, or
    // stores a zero span no pan can escape.
    assertNull(MapView.of(null, -79.3832d, 0.35d, 0.5d));
    assertNull(MapView.of(43.6532d, null, 0.35d, 0.5d));
    assertNull(MapView.of(43.6532d, -79.3832d, null, 0.5d));
    assertNull(MapView.of(43.6532d, -79.3832d, 0.35d, null));
  }

  @Test
  void rejectsCoordinatesOffTheGlobe() {
    assertNull(MapView.of(91d, 0d, 1d, 1d));
    assertNull(MapView.of(-91d, 0d, 1d, 1d));
    assertNull(MapView.of(0d, 181d, 1d, 1d));
    assertNull(MapView.of(0d, -181d, 1d, 1d));
  }

  @Test
  void rejectsASpanTooSmallToPanOutOf() {
    assertNull(MapView.of(43.6532d, -79.3832d, 0d, 0.5d));
    assertNull(MapView.of(43.6532d, -79.3832d, 0.5d, 0d));
    assertNull(MapView.of(43.6532d, -79.3832d, -1d, 0.5d));
  }

  @Test
  void rejectsNonFiniteValues() {
    assertNull(MapView.of(Double.NaN, 0d, 1d, 1d));
    assertNull(MapView.of(0d, Double.POSITIVE_INFINITY, 1d, 1d));
    assertNull(MapView.of(0d, 0d, Double.NaN, 1d));
  }

  @Test
  void clampsAnOversizedSpanRatherThanFailingTheSave() {
    // A fully zoomed-out map legitimately reports a span at the limit, and a browser rounding it a
    // hair past should still save.
    MapView view = MapView.of(0d, 0d, 400d, 900d);

    assertNotNull(view);
    assertEquals(180d, view.spanLat());
    assertEquals(360d, view.spanLng());
  }
}
