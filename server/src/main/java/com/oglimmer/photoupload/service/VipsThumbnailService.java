/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.service.ThumbnailService.ThumbnailSize;
import java.io.IOException;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.TimeUnit;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

/**
 * Generates JPEG thumbnails via {@code vipsthumbnail}. vips uses shrink-on-load, so peak memory
 * tracks the output size rather than the input — a 50 MP source costs roughly the same as a 6 MP
 * source for the same target dimensions.
 */
@Service
@Profile(Profiles.WORKER)
@Slf4j
public class VipsThumbnailService {

  private static final long PER_INVOCATION_TIMEOUT_SECONDS = 120;

  /**
   * Run one {@code vipsthumbnail} per target size and return the resulting paths in [thumb, medium,
   * large] order. Missing entries (failed invocations) are left as {@code null}.
   */
  public Path[] generateAllThumbnails(Path originalFile, Path baseOutputPath) {
    Path[] result = new Path[3];
    Path parentDir = baseOutputPath.getParent();
    // vipsthumbnail picks the saver from the destination extension. We always emit JPEG, so force
    // .jpg here — otherwise a .png (or .gif/.webp) source would route to pngsave/gifsave/webpsave,
    // which reject the [Q=N,optimize_coding,strip] save options below.
    String rawName = baseOutputPath.getFileName().toString();
    int dot = rawName.lastIndexOf('.');
    String stem = dot > 0 ? rawName.substring(0, dot) : rawName;
    String baseName = stem + ".jpg";
    parentDir.toFile().mkdirs();

    Path thumb = parentDir.resolve("thumb_" + baseName);
    Path medium = parentDir.resolve("medium_" + baseName);
    Path large = parentDir.resolve("large_" + baseName);

    if (runOne(originalFile, thumb, ThumbnailSize.THUMBNAIL)) {
      result[0] = thumb;
    }
    if (runOne(originalFile, medium, ThumbnailSize.MEDIUM)) {
      result[1] = medium;
    }
    if (runOne(originalFile, large, ThumbnailSize.LARGE)) {
      result[2] = large;
    }
    return result;
  }

  private boolean runOne(Path src, Path dst, ThumbnailSize size) {
    int quality = (int) (size.getJpegQuality() * 100);
    String dim = size.getMaxWidth() + "x" + size.getMaxHeight();
    // vipsthumbnail writes a JPEG. The trailing [Q=N] is a vips save-option, not a shell glob, so
    // it doesn't need quoting when passed as a single ProcessBuilder argument.
    List<String> cmd =
        List.of(
            "vipsthumbnail",
            src.toAbsolutePath().toString(),
            "--size",
            dim,
            "--export-profile",
            "srgb",
            "-o",
            dst.toAbsolutePath().toString() + "[Q=" + quality + ",optimize_coding,strip]");
    try {
      ProcessRunner.Result r =
          ProcessRunner.run(cmd, PER_INVOCATION_TIMEOUT_SECONDS, TimeUnit.SECONDS);
      if (!r.success()) {
        log.error(
            "vipsthumbnail failed for {} → {} (exit {}, timedOut={}): {}",
            src.getFileName(),
            dst.getFileName(),
            r.exitCode(),
            r.timedOut(),
            r.output());
        return false;
      }
      if (!dst.toFile().exists() || dst.toFile().length() == 0) {
        log.error("vipsthumbnail succeeded but produced no output: {}", dst);
        return false;
      }
      return true;
    } catch (IOException e) {
      log.error("IO error invoking vipsthumbnail for {}: {}", src, e.getMessage());
      return false;
    }
  }
}
