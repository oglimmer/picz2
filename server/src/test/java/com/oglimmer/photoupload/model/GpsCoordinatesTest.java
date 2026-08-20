/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import static org.assertj.core.api.Assertions.assertThat;

import com.oglimmer.photoupload.entity.GpsSource;
import org.junit.jupiter.api.Test;

/**
 * The validation in {@link GpsCoordinates#of} is the single gate every extractor passes through, so
 * what it rejects is what never reaches the map.
 */
class GpsCoordinatesTest {

  @Test
  void keepsValidCoordinates() {
    GpsCoordinates coordinates = GpsCoordinates.of(48.1372, 11.5756, GpsSource.EXIF_GPS);

    assertThat(coordinates.isPresent()).isTrue();
    assertThat(coordinates.source()).isEqualTo(GpsSource.EXIF_GPS);
  }

  @Test
  void rejectsNullIsland() {
    // Cameras with a GPS chip but no fix write 0/0. Kept as a location it would drop a pin in
    // the Gulf of Guinea for every unlocated photo in the album.
    assertThat(GpsCoordinates.of(0.0, 0.0, GpsSource.EXIF_GPS).source()).isEqualTo(GpsSource.NONE);
  }

  @Test
  void rejectsOutOfRangeValues() {
    assertThat(GpsCoordinates.of(91.0, 11.0, GpsSource.EXIF_GPS).isPresent()).isFalse();
    assertThat(GpsCoordinates.of(48.0, 181.0, GpsSource.EXIF_GPS).isPresent()).isFalse();
  }

  @Test
  void rejectsHalfMissingPairs() {
    assertThat(GpsCoordinates.of(48.1372, null, GpsSource.EXIF_GPS).isPresent()).isFalse();
    assertThat(GpsCoordinates.of(null, 11.5756, GpsSource.EXIF_GPS).isPresent()).isFalse();
  }

  @Test
  void noneCarriesNoCoordinates() {
    assertThat(GpsCoordinates.none().latitude()).isNull();
    assertThat(GpsCoordinates.none().longitude()).isNull();
    assertThat(GpsCoordinates.none().source()).isEqualTo(GpsSource.NONE);
  }
}
