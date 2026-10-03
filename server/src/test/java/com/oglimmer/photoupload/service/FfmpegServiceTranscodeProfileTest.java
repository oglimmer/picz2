/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.oglimmer.photoupload.service.FfmpegService.TranscodeProfile;
import org.junit.jupiter.api.Test;

/**
 * Pins the length thresholds behind {@code transcodeVideo}. A clip put in a profile that is too
 * slow for it runs into the 40 min timeout and is left with no web-playable derivative.
 */
class FfmpegServiceTranscodeProfileTest {

  @Test
  void shortClipKeepsTheOriginalSettings() {
    TranscodeProfile profile = FfmpegService.profileFor(60.0);

    assertThat(profile).isEqualTo(TranscodeProfile.SHORT);
    assertThat(profile.preset).isEqualTo("medium");
    assertThat(profile.maxWidth).isEqualTo(1920);
    assertThat(profile.fpsMax).isNull();
  }

  @Test
  void threeMinuteClipGetsTheFastPreset() {
    // Asset 10677: 180.6 s at 1080p60 timed out on 'medium'.
    TranscodeProfile profile = FfmpegService.profileFor(180.58);

    assertThat(profile).isEqualTo(TranscodeProfile.LONG);
    assertThat(profile.preset).isEqualTo("veryfast");
    assertThat(profile.maxWidth).isEqualTo(1920);
    assertThat(profile.fpsMax).isEqualTo(30);
  }

  @Test
  void halfHourClipAlsoDropsTo720p() {
    TranscodeProfile profile = FfmpegService.profileFor(1841.83);

    assertThat(profile).isEqualTo(TranscodeProfile.VERY_LONG);
    assertThat(profile.maxWidth).isEqualTo(1280);
    assertThat(profile.fpsMax).isEqualTo(30);
  }

  @Test
  void tenMinutesIsStillLong() {
    assertThat(FfmpegService.profileFor(600.0)).isEqualTo(TranscodeProfile.LONG);
    assertThat(FfmpegService.profileFor(600.1)).isEqualTo(TranscodeProfile.VERY_LONG);
  }

  @Test
  void unknownLengthIsTreatedAsLong() {
    assertThat(FfmpegService.profileFor(null)).isEqualTo(TranscodeProfile.LONG);
  }

  @Test
  void parsesFfprobeDuration() {
    assertThat(FfmpegService.parseDuration("180.583333\n")).isEqualTo(180.583333);
  }

  @Test
  void parsesTheLastLineWhenStderrPrecedesIt() {
    assertThat(FfmpegService.parseDuration("[mov] some warning\n42.5\n")).isEqualTo(42.5);
  }

  @Test
  void unreadableDurationIsNull() {
    assertThat(FfmpegService.parseDuration("N/A")).isNull();
    assertThat(FfmpegService.parseDuration("")).isNull();
    assertThat(FfmpegService.parseDuration(null)).isNull();
    assertThat(FfmpegService.parseDuration("0.000000")).isNull();
  }
}
