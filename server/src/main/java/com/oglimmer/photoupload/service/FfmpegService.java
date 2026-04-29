/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import java.io.File;
import java.io.IOException;
import java.nio.file.Path;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.concurrent.TimeUnit;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

/**
 * Wraps {@code ffmpeg}/{@code ffprobe}. Each invocation has a hard timeout — earlier code blocked
 * forever on the rare hung encode, which jammed the worker pool.
 */
@Service
@Profile(Profiles.WORKER)
@Slf4j
public class FfmpegService {

  private static final long TRANSCODE_TIMEOUT_MINUTES = 15;
  private static final long THUMBNAIL_TIMEOUT_SECONDS = 60;
  private static final long PROBE_TIMEOUT_SECONDS = 30;

  public boolean transcodeVideo(Path originalFile, Path outputPath) {
    File outputFile = outputPath.toFile();
    outputFile.getParentFile().mkdirs();

    List<String> cmd =
        List.of(
            "ffmpeg",
            "-i",
            originalFile.toAbsolutePath().toString(),
            "-c:v",
            "libx264",
            "-profile:v",
            "main",
            "-level",
            "4.0",
            "-preset",
            "medium",
            "-c:a",
            "aac",
            "-b:a",
            "128k",
            "-movflags",
            "+faststart",
            "-y",
            outputPath.toAbsolutePath().toString());

    try {
      log.debug(
          "Transcoding video: {} -> {}", originalFile.getFileName(), outputPath.getFileName());
      ProcessRunner.Result r = ProcessRunner.run(cmd, TRANSCODE_TIMEOUT_MINUTES, TimeUnit.MINUTES);
      if (r.success() && outputFile.exists()) {
        log.info("Transcoded {} -> {}", originalFile.getFileName(), outputPath.getFileName());
        return true;
      }
      log.error(
          "ffmpeg transcode failed (exit {}, timedOut={}) for {}: {}",
          r.exitCode(),
          r.timedOut(),
          originalFile.getFileName(),
          r.output());
      return false;
    } catch (IOException e) {
      log.error("IO error during transcode for {}: {}", originalFile, e.getMessage());
      return false;
    }
  }

  public boolean generateVideoThumbnail(Path videoFile, Path outputPath) {
    File outputFile = outputPath.toFile();
    outputFile.getParentFile().mkdirs();

    List<String> cmd =
        List.of(
            "ffmpeg",
            "-ss",
            "1",
            "-i",
            videoFile.toAbsolutePath().toString(),
            "-vframes",
            "1",
            "-vf",
            "scale=600:-1",
            "-q:v",
            "2",
            "-y",
            outputPath.toAbsolutePath().toString());

    try {
      ProcessRunner.Result r = ProcessRunner.run(cmd, THUMBNAIL_TIMEOUT_SECONDS, TimeUnit.SECONDS);
      if (r.success() && outputFile.exists()) {
        log.info("Generated video thumbnail: {}", videoFile.getFileName());
        return true;
      }
      log.error(
          "Video thumbnail failed (exit {}, timedOut={}) for {}: {}",
          r.exitCode(),
          r.timedOut(),
          videoFile.getFileName(),
          r.output());
      return false;
    } catch (IOException e) {
      log.error("IO error generating video thumbnail for {}: {}", videoFile, e.getMessage());
      return false;
    }
  }

  public Instant extractVideoCreationDate(Path videoFile) {
    List<String> cmd =
        List.of(
            "ffprobe",
            "-v",
            "quiet",
            "-show_entries",
            "format_tags=creation_time",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            videoFile.toAbsolutePath().toString());

    try {
      ProcessRunner.Result r = ProcessRunner.run(cmd, PROBE_TIMEOUT_SECONDS, TimeUnit.SECONDS);
      String value = r.output().trim();
      if (!r.success() || value.isEmpty()) {
        log.debug("No creation_time found in video: {}", videoFile.getFileName());
        return null;
      }
      Instant instant = Instant.parse(value);
      log.info("🎬 Extracted video creation_time: {} for {}", instant, videoFile.getFileName());
      return instant;
    } catch (DateTimeParseException e) {
      log.debug(
          "Could not parse video creation_time from {}: {}",
          videoFile.getFileName(),
          e.getMessage());
      return null;
    } catch (IOException e) {
      log.debug(
          "Could not read video metadata from {}: {}", videoFile.getFileName(), e.getMessage());
      return null;
    }
  }
}
