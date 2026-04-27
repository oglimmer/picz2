/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import java.io.File;
import java.io.IOException;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.TimeUnit;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Converts HEIC/HEIF input to JPEG.
 *
 * <p>Primary path: {@code heif-convert} from libheif. This is the canonical decoder for HEIC and
 * tolerates the auxiliary image references that modern iOS files attach (depth maps, HDR gainmaps,
 * preview). ImageMagick's HEIC coder rejects those with {@code "Too many auxiliary image
 * references"} on the same files.
 *
 * <p>Fallback path: ImageMagick {@code convert input.heic[0]} — the {@code [0]} selector forces IM
 * to read only the primary image, so the fallback works on the same aux-laden files.
 */
@Service
@Slf4j
public class HeicConversionService {

  private static final long TIMEOUT_SECONDS = 180;
  private static final String JPEG_QUALITY = "95";

  public boolean convertHeicToJpeg(Path originalFile, Path outputPath) {
    File outputFile = outputPath.toFile();
    outputFile.getParentFile().mkdirs();

    if (runHeifConvert(originalFile, outputPath)) {
      return true;
    }
    log.warn(
        "heif-convert path failed for {}, falling back to ImageMagick", originalFile.getFileName());
    return runImageMagick(originalFile, outputPath);
  }

  private boolean runHeifConvert(Path src, Path dst) {
    // heif-convert respects irot/EXIF orientation by default — no separate auto-orient pass needed.
    List<String> cmd =
        List.of(
            "heif-convert",
            "--quality",
            JPEG_QUALITY,
            src.toAbsolutePath().toString(),
            dst.toAbsolutePath().toString());
    try {
      log.info("Converting HEIC via heif-convert: {} -> {}", src.getFileName(), dst.getFileName());
      ProcessRunner.Result r = ProcessRunner.run(cmd, TIMEOUT_SECONDS, TimeUnit.SECONDS);
      File out = dst.toFile();
      if (r.success() && out.exists() && out.length() > 0) {
        log.info("✅ HEIC → JPEG via heif-convert: {} -> {}", src.getFileName(), dst.getFileName());
        return true;
      }
      log.warn(
          "heif-convert failed (exit {}, timedOut={}): {}", r.exitCode(), r.timedOut(), r.output());
      return false;
    } catch (IOException e) {
      log.warn("heif-convert not invokable for {}: {}", src.getFileName(), e.getMessage());
      return false;
    }
  }

  private boolean runImageMagick(Path src, Path dst) {
    // [0] picks the primary image only and skips auxiliary refs (depth, HDR gainmap, preview),
    // which modern iOS HEICs always have. Without it, IM rejects the file outright.
    // -auto-orient bakes any HEIF irot/EXIF orientation into the pixels and clears the tag.
    List<String> cmd =
        List.of(
            "magick",
            "-limit",
            "memory",
            "256MiB",
            "-limit",
            "map",
            "512MiB",
            "-limit",
            "thread",
            "2",
            "-limit",
            "time",
            "120",
            src.toAbsolutePath().toString() + "[0]",
            "-auto-orient",
            "-quality",
            JPEG_QUALITY,
            dst.toAbsolutePath().toString());
    try {
      ProcessRunner.Result r = ProcessRunner.run(cmd, TIMEOUT_SECONDS, TimeUnit.SECONDS);
      File out = dst.toFile();
      if (r.success() && out.exists() && out.length() > 0) {
        log.info("✅ HEIC → JPEG via ImageMagick fallback: {}", src.getFileName());
        return true;
      }
      log.error(
          "ImageMagick HEIC fallback failed (exit {}, timedOut={}): {}",
          r.exitCode(),
          r.timedOut(),
          r.output());
      return false;
    } catch (IOException e) {
      log.error("IO error in ImageMagick HEIC fallback for {}: {}", src, e.getMessage());
      return false;
    }
  }
}
