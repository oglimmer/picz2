/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.config.FileStorageProperties.Thumbnailer;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import org.junit.jupiter.api.Test;

class ThumbnailServiceDispatchTest {

  @Test
  void vipsModeRoutesToVipsService() {
    FileStorageProperties props = new FileStorageProperties();
    props.setThumbnailer(Thumbnailer.VIPS);
    VipsThumbnailService vips = mock(VipsThumbnailService.class);
    HeicConversionService heic = mock(HeicConversionService.class);
    FfmpegService ffmpeg = mock(FfmpegService.class);

    ThumbnailService svc = new ThumbnailService(props, vips, heic, ffmpeg);

    Path src = Paths.get("/tmp/x.jpg");
    Path base = Paths.get("/tmp/x.jpg");
    Path[] expected = new Path[3];
    when(vips.generateAllThumbnails(src, base)).thenReturn(expected);

    Path[] actual = svc.generateAllThumbnails(src, base);

    assertThat(actual).isSameAs(expected);
    verify(vips).generateAllThumbnails(src, base);
  }

  @Test
  void magickModeBypassesVipsService() {
    FileStorageProperties props = new FileStorageProperties();
    props.setThumbnailer(Thumbnailer.MAGICK);
    VipsThumbnailService vips = mock(VipsThumbnailService.class);
    HeicConversionService heic = mock(HeicConversionService.class);
    FfmpegService ffmpeg = mock(FfmpegService.class);

    ThumbnailService svc = new ThumbnailService(props, vips, heic, ffmpeg);

    // Magick path shells out to `convert`, which won't exist in CI; we only need to confirm the
    // vips service is not consulted. The shell-out itself is exercised by integration tests.
    svc.generateAllThumbnails(Paths.get("/tmp/does-not-exist.jpg"), Paths.get("/tmp/x.jpg"));

    verifyNoInteractions(vips);
  }

  @Test
  void heicAndFfmpegCallsForwardToTheirServices() {
    FileStorageProperties props = new FileStorageProperties();
    VipsThumbnailService vips = mock(VipsThumbnailService.class);
    HeicConversionService heic = mock(HeicConversionService.class);
    FfmpegService ffmpeg = mock(FfmpegService.class);
    ThumbnailService svc = new ThumbnailService(props, vips, heic, ffmpeg);

    Path a = Paths.get("/tmp/a");
    Path b = Paths.get("/tmp/b");
    Instant when = Instant.parse("2026-04-27T00:00:00Z");

    when(heic.convertHeicToJpeg(a, b)).thenReturn(true);
    when(ffmpeg.transcodeVideo(a, b)).thenReturn(true);
    when(ffmpeg.generateVideoThumbnail(a, b)).thenReturn(true);
    when(ffmpeg.extractVideoCreationDate(a)).thenReturn(when);

    assertThat(svc.convertHeicToJpeg(a, b)).isTrue();
    assertThat(svc.transcodeVideo(a, b)).isTrue();
    assertThat(svc.generateVideoThumbnail(a, b)).isTrue();
    assertThat(svc.extractVideoCreationDate(a)).isEqualTo(when);

    verify(heic).convertHeicToJpeg(eq(a), eq(b));
    verify(ffmpeg).transcodeVideo(eq(a), eq(b));
    verify(ffmpeg).generateVideoThumbnail(eq(a), eq(b));
    verify(ffmpeg).extractVideoCreationDate(eq(a));
  }

  @Test
  void mimeTypeHelpersClassifyCorrectly() {
    ThumbnailService svc =
        new ThumbnailService(
            new FileStorageProperties(),
            mock(VipsThumbnailService.class),
            mock(HeicConversionService.class),
            mock(FfmpegService.class));

    assertThat(svc.isImageFile("image/jpeg")).isTrue();
    assertThat(svc.isImageFile("image/heic")).isFalse();
    assertThat(svc.isImageFile(null)).isFalse();
    assertThat(svc.isHeicFile("image/heic")).isTrue();
    assertThat(svc.isHeicFile("image/heif")).isTrue();
    assertThat(svc.isHeicFile("image/jpeg")).isFalse();
    assertThat(svc.isVideoFile("video/mp4")).isTrue();
    assertThat(svc.isVideoFile("image/jpeg")).isFalse();
  }
}
