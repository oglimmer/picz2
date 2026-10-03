/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * Pins where the video thumbnail frame is taken. A seek past the clip's end makes ffmpeg exit 0
 * with no output file, and the video is left without a thumbnail.
 */
class FfmpegServiceThumbnailSeekTest {

  @Test
  void normalClipSeeksOneSecondIn() {
    assertThat(FfmpegService.thumbnailSeekSeconds(12.5)).isEqualTo(1.0);
  }

  @Test
  void subSecondClipSeeksToItsMiddle() {
    // Asset 10908: a 0.73 s iPhone clip got no thumbnail from a 1 s seek.
    assertThat(FfmpegService.thumbnailSeekSeconds(0.731667)).isEqualTo(0.3658335);
  }

  @Test
  void unknownLengthKeepsOneSecond() {
    assertThat(FfmpegService.thumbnailSeekSeconds(null)).isEqualTo(1.0);
  }
}
