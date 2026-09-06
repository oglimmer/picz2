/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

import org.junit.jupiter.api.Test;

/** The pure arithmetic behind the one-tap enhance (D81); the ImageMagick call itself is not run. */
class ThumbnailServiceEnhanceTest {

  @Test
  void midGreyNeedsNoGamma() {
    assertThat(ThumbnailService.enhanceGammaFor(0.5)).isCloseTo(1.0, within(1e-9));
  }

  @Test
  void darkImagesBrightenButOnlySoFar() {
    // Half the full correction: ln(0.3)/ln(0.5) = 1.737, softened to 1.368, clamped to 1.3.
    assertThat(ThumbnailService.enhanceGammaFor(0.3)).isEqualTo(1.3);
    // ln(0.4)/ln(0.5) = 1.322, softened to 1.161 — inside the clamp.
    assertThat(ThumbnailService.enhanceGammaFor(0.4)).isCloseTo(1.161, within(1e-3));
    assertThat(ThumbnailService.enhanceGammaFor(0.05)).isEqualTo(1.3);
  }

  @Test
  void brightImagesDarkenButOnlySoFar() {
    // ln(0.6)/ln(0.5) = 0.737, softened to 0.868 — inside the clamp.
    assertThat(ThumbnailService.enhanceGammaFor(0.6)).isCloseTo(0.868, within(1e-3));
    assertThat(ThumbnailService.enhanceGammaFor(0.9)).isEqualTo(0.85);
  }

  @Test
  void degenerateMeansLeaveTheImageAlone() {
    assertThat(ThumbnailService.enhanceGammaFor(0.0)).isEqualTo(1.0);
    assertThat(ThumbnailService.enhanceGammaFor(1.0)).isEqualTo(1.0);
    assertThat(ThumbnailService.enhanceGammaFor(Double.NaN)).isEqualTo(1.0);
    assertThat(ThumbnailService.enhanceGammaFor(-0.2)).isEqualTo(1.0);
  }

  @Test
  void lastNumberSkipsReaderWarningsThatShareTheStream() {
    assertThat(ThumbnailService.lastNumber("0.41273\n")).isEqualTo(0.41273);
    assertThat(
            ThumbnailService.lastNumber(
                "convert: iCCP: known incorrect sRGB profile `x.png' @ warning/png.c/123.\n0.5"))
        .isEqualTo(0.5);
    assertThat(ThumbnailService.lastNumber("convert: no decode delegate\n")).isNull();
    assertThat(ThumbnailService.lastNumber("")).isNull();
  }

  @Test
  void lastTwoIntegersReadsTheSizePastAnyWarning() {
    assertThat(ThumbnailService.lastTwoIntegers("4032 3024\n")).containsExactly(4032, 3024);
    assertThat(
            ThumbnailService.lastTwoIntegers(
                "WARNING: The identify command is deprecated in IMv7, use \"magick identify\"\n\n4032 3024"))
        .containsExactly(4032, 3024);
    assertThat(ThumbnailService.lastTwoIntegers("identify: no decode delegate\n")).isNull();
    assertThat(ThumbnailService.lastTwoIntegers("4032")).isNull();
  }
}
