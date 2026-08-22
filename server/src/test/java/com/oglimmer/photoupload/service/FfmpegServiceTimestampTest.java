/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * Covers the two pure helpers behind {@code extractVideoCreationDate}. The colon-less offset case
 * is the whole point: {@code Instant.parse} rejects it, and the old code turned that rejection into
 * a null capture date, which dropped the video to the end of every EXIF-sorted album.
 */
class FfmpegServiceTimestampTest {

  @Test
  void parsesMvhdStyleUtcTimestamp() {
    assertThat(FfmpegService.parseTimestamp("2026-08-17T12:23:11.000000Z"))
        .isEqualTo(Instant.parse("2026-08-17T12:23:11Z"));
  }

  @Test
  void parsesAppleColonLessOffset() {
    assertThat(FfmpegService.parseTimestamp("2026-08-17T14:23:11+0200"))
        .isEqualTo(Instant.parse("2026-08-17T12:23:11Z"));
  }

  @Test
  void parsesIsoOffsetWithColon() {
    assertThat(FfmpegService.parseTimestamp("2026-08-17T14:23:11+02:00"))
        .isEqualTo(Instant.parse("2026-08-17T12:23:11Z"));
  }

  @Test
  void readsTheOffsetApplePutsOnCreationdate() {
    assertThat(FfmpegService.parseOffsetSeconds("2026-08-17T14:23:11+0200")).isEqualTo(2 * 3600);
    assertThat(FfmpegService.parseOffsetSeconds("2026-08-17T09:23:11-05:00")).isEqualTo(-5 * 3600);
  }

  /** A zone-less mvhd value has no local clock to recover, so no offset is invented for it. */
  @Test
  void reportsNoOffsetForZonelessOrUnparseableValues() {
    assertThat(FfmpegService.parseOffsetSeconds("2026-08-17 12:23:11")).isNull();
    assertThat(FfmpegService.parseOffsetSeconds("2026-08-17T12:23:11.000000Z")).isEqualTo(0);
    assertThat(FfmpegService.parseOffsetSeconds(null)).isNull();
    assertThat(FfmpegService.parseOffsetSeconds("nonsense")).isNull();
  }

  @Test
  void treatsZonelessTimestampAsUtc() {
    assertThat(FfmpegService.parseTimestamp("2026-08-17 12:23:11"))
        .isEqualTo(Instant.parse("2026-08-17T12:23:11Z"));
  }

  @Test
  void returnsNullForAbsentOrUnparseableValues() {
    assertThat(FfmpegService.parseTimestamp(null)).isNull();
    assertThat(FfmpegService.parseTimestamp("   ")).isNull();
    assertThat(FfmpegService.parseTimestamp("0000-00-00 00:00:00")).isNull();
    assertThat(FfmpegService.parseTimestamp("not a date")).isNull();
  }

  @Test
  void parsesFormatTagsBlock() {
    String output =
        """
        TAG:major_brand=qt
        TAG:creation_time=2026-08-17T12:23:11.000000Z
        TAG:com.apple.quicktime.make=Apple
        TAG:com.apple.quicktime.creationdate=2026-08-17T14:23:11+0200

        not-a-tag-line
        """;

    Map<String, String> tags = FfmpegService.parseFormatTags(output);

    assertThat(tags)
        .containsEntry("creation_time", "2026-08-17T12:23:11.000000Z")
        .containsEntry("com.apple.quicktime.creationdate", "2026-08-17T14:23:11+0200")
        .containsEntry("com.apple.quicktime.make", "Apple")
        .hasSize(4);
  }

  @Test
  void parseFormatTagsToleratesEmptyOutput() {
    assertThat(FfmpegService.parseFormatTags("")).isEmpty();
  }
}
