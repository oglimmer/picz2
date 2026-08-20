/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * What the browser sends to save an album's default map view: a straight copy of MapKit's {@code
 * map.region} after the user has panned and zoomed to the view they want.
 *
 * <p>Boxed doubles so a missing field arrives as null and is rejected by {@link MapView#of}, rather
 * than silently defaulting to 0 — which would centre the map on null island.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class MapViewRequest {

  private Double centerLat;
  private Double centerLng;
  private Double spanLat;
  private Double spanLng;
}
