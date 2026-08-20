/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.oglimmer.photoupload.entity.GpsSource;
import com.oglimmer.photoupload.model.GpsCoordinates;
import org.junit.jupiter.api.Test;

/**
 * Covers the ISO 6709 parser behind {@code extractVideoLocation}. Sign handling is the part worth
 * pinning down: dropping a leading minus mirrors a clip into the wrong hemisphere, which puts the
 * pin thousands of kilometres away while still looking like a plausible coordinate.
 */
class FfmpegServiceLocationTest {

  @Test
  void parsesAppleQuickTimeLocationWithAltitude() {
    GpsCoordinates coordinates = FfmpegService.parseIso6709("+48.1372+011.5756+509.000/");

    assertThat(coordinates.latitude()).isEqualTo(48.1372);
    assertThat(coordinates.longitude()).isEqualTo(11.5756);
    assertThat(coordinates.source()).isEqualTo(GpsSource.QUICKTIME_ISO6709);
  }

  @Test
  void parsesSouthernAndWesternHemispheres() {
    GpsCoordinates coordinates = FfmpegService.parseIso6709("-33.8688-151.2093/");

    assertThat(coordinates.latitude()).isEqualTo(-33.8688);
    assertThat(coordinates.longitude()).isEqualTo(-151.2093);
  }

  @Test
  void parsesLocationWithoutAltitudeOrTrailingSolidus() {
    assertThat(FfmpegService.parseIso6709("+52.5200+013.4050").isPresent()).isTrue();
  }

  @Test
  void rejectsNullIslandBecauseItMeansNoFix() {
    assertThat(FfmpegService.parseIso6709("+00.0000+000.0000/").source()).isEqualTo(GpsSource.NONE);
  }

  @Test
  void rejectsAbsentAndUnparseableValues() {
    assertThat(FfmpegService.parseIso6709(null).isPresent()).isFalse();
    assertThat(FfmpegService.parseIso6709("").isPresent()).isFalse();
    assertThat(FfmpegService.parseIso6709("somewhere nice").isPresent()).isFalse();
  }
}
