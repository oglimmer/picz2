/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.CaptureDateSource;
import com.oglimmer.photoupload.entity.GpsSource;
import com.oglimmer.photoupload.model.CaptureDate;
import com.oglimmer.photoupload.model.GpsCoordinates;
import java.io.File;
import java.io.IOException;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
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
  private static final String TAG_CREATION_TIME = "creation_time";
  private static final String TAG_QUICKTIME_CREATIONDATE = "com.apple.quicktime.creationdate";
  private static final String TAG_QUICKTIME_LOCATION = "com.apple.quicktime.location.ISO6709";
  private static final String TAG_LOCATION = "location";

  /**
   * The ISO 6709 form every phone actually writes into the QuickTime location atom: signed decimal
   * degrees, latitude then longitude, with an optional altitude and a trailing solidus — e.g.
   * {@code +48.1372+011.5756+509.000/}. The spec also allows degrees-minutes-seconds packing
   * ({@code +4808.23+01134.53/}), which no camera in this pipeline emits; such values fail the
   * match and are logged rather than silently misplaced by two degrees.
   */
  private static final java.util.regex.Pattern ISO6709 =
      java.util.regex.Pattern.compile("^([+-]\\d{1,2}(?:\\.\\d+)?)([+-]\\d{1,3}(?:\\.\\d+)?)");

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
            // Force 8-bit output. iPhone HDR/Dolby Vision clips are 10-bit HEVC, and without
            // this ffmpeg picks a matching 10-bit pixel format (yuv420p10le) for the encoder —
            // which x264's `main` profile cannot represent, so the encode dies with
            // "main profile doesn't support a bit depth of 10" and the asset ends up with no
            // web-playable derivative. The failure is silent: the job still completes DONE.
            "-pix_fmt",
            "yuv420p",
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

  /**
   * Reads the capture time of a video as a true instant.
   *
   * <p>Probes <em>all</em> format tags rather than naming one: an iPhone .MOV carries both {@code
   * com.apple.quicktime.creationdate} (local time with an explicit offset) and {@code
   * creation_time} (the mvhd atom, which ffmpeg emits already normalised to UTC). The Apple tag is
   * preferred — it is the value the Photos app shows — but both resolve to the same instant, so the
   * mvhd fallback is equally usable for sorting.
   */
  public CaptureDate extractVideoCreationDate(Path videoFile) {
    List<String> cmd =
        List.of(
            "ffprobe",
            "-v",
            "quiet",
            "-show_entries",
            "format_tags",
            "-of",
            "default=noprint_wrappers=1",
            videoFile.toAbsolutePath().toString());

    try {
      ProcessRunner.Result r = ProcessRunner.run(cmd, PROBE_TIMEOUT_SECONDS, TimeUnit.SECONDS);
      if (!r.success()) {
        log.debug("ffprobe returned no format tags for {}", videoFile.getFileName());
        return CaptureDate.none();
      }
      Map<String, String> tags = parseFormatTags(r.output());

      CaptureDate quicktime =
          CaptureDate.of(
              parseTimestamp(tags.get(TAG_QUICKTIME_CREATIONDATE)),
              CaptureDateSource.QUICKTIME_LOCAL,
              parseOffsetSeconds(tags.get(TAG_QUICKTIME_CREATIONDATE)));
      if (quicktime.isPresent()) {
        log.info(
            "🎬 {} = {} → {} for {}",
            TAG_QUICKTIME_CREATIONDATE,
            tags.get(TAG_QUICKTIME_CREATIONDATE),
            quicktime.instant(),
            videoFile.getFileName());
        return quicktime;
      }

      // No offset: mvhd is UTC by definition and the container keeps no local clock, so there is
      // nothing to recover. Consumers fall back rather than being told a wrong offset.
      CaptureDate mvhd =
          CaptureDate.of(parseTimestamp(tags.get(TAG_CREATION_TIME)), CaptureDateSource.MVHD_UTC);
      if (mvhd.isPresent()) {
        log.info(
            "🎬 creation_time = {} → {} for {}",
            tags.get(TAG_CREATION_TIME),
            mvhd.instant(),
            videoFile.getFileName());
        return mvhd;
      }
      log.debug("No usable creation timestamp in video: {}", videoFile.getFileName());
      return CaptureDate.none();
    } catch (IOException e) {
      log.debug(
          "Could not read video metadata from {}: {}", videoFile.getFileName(), e.getMessage());
      return CaptureDate.none();
    }
  }

  /**
   * Reads where a video was shot from its container tags.
   *
   * <p>Apple writes {@code com.apple.quicktime.location.ISO6709}; Android and most other writers
   * use the plain {@code location} tag in the same format, so both are tried. One ffprobe call,
   * same {@code format_tags} section the capture-date probe reads — kept separate rather than
   * merged so a location failure can never cost us a capture date.
   *
   * @return the coordinates, or {@link GpsCoordinates#none()} if the container carries no usable
   *     location
   */
  public GpsCoordinates extractVideoLocation(Path videoFile) {
    List<String> cmd =
        List.of(
            "ffprobe",
            "-v",
            "quiet",
            "-show_entries",
            "format_tags",
            "-of",
            "default=noprint_wrappers=1",
            videoFile.toAbsolutePath().toString());

    try {
      ProcessRunner.Result r = ProcessRunner.run(cmd, PROBE_TIMEOUT_SECONDS, TimeUnit.SECONDS);
      if (!r.success()) {
        log.debug("ffprobe returned no format tags for {}", videoFile.getFileName());
        return GpsCoordinates.none();
      }
      Map<String, String> tags = parseFormatTags(r.output());
      String raw = tags.get(TAG_QUICKTIME_LOCATION);
      if (raw == null || raw.isBlank()) {
        raw = tags.get(TAG_LOCATION);
      }
      GpsCoordinates coordinates = parseIso6709(raw);
      if (coordinates.isPresent()) {
        log.info(
            "🌍 video location '{}' → {}/{} for {}",
            raw,
            coordinates.latitude(),
            coordinates.longitude(),
            videoFile.getFileName());
      }
      return coordinates;
    } catch (IOException e) {
      log.debug(
          "Could not read video location from {}: {}", videoFile.getFileName(), e.getMessage());
      return GpsCoordinates.none();
    }
  }

  /**
   * Parses an ISO 6709 location string into signed decimal degrees. Returns {@link
   * GpsCoordinates#none()} for absent, unrecognised, or out-of-range values — range and null-island
   * checks live in {@link GpsCoordinates#of}.
   */
  static GpsCoordinates parseIso6709(String raw) {
    if (raw == null || raw.isBlank()) {
      return GpsCoordinates.none();
    }
    java.util.regex.Matcher matcher = ISO6709.matcher(raw.trim());
    if (!matcher.find()) {
      log.debug("Unrecognised ISO 6709 location '{}'", raw);
      return GpsCoordinates.none();
    }
    try {
      return GpsCoordinates.of(
          Double.parseDouble(matcher.group(1)),
          Double.parseDouble(matcher.group(2)),
          GpsSource.QUICKTIME_ISO6709);
    } catch (NumberFormatException e) {
      log.debug("Unparseable ISO 6709 location '{}'", raw);
      return GpsCoordinates.none();
    }
  }

  /**
   * Turns ffprobe's {@code default=noprint_wrappers=1} output into a tag map. Each line is {@code
   * TAG:key=value}; anything else (blank lines, a stray section wrapper) is skipped.
   */
  static Map<String, String> parseFormatTags(String output) {
    Map<String, String> tags = new LinkedHashMap<>();
    for (String line : output.split("\\R")) {
      String trimmed = line.trim();
      if (!trimmed.startsWith("TAG:")) {
        continue;
      }
      int eq = trimmed.indexOf('=');
      if (eq < 0) {
        continue;
      }
      tags.put(trimmed.substring("TAG:".length(), eq), trimmed.substring(eq + 1).trim());
    }
    return tags;
  }

  /**
   * The UTC offset carried by an ffprobe timestamp, in seconds, or null when the value has none
   * (or does not parse). Apple's {@code creationdate} is a local wall clock plus offset, e.g.
   * "2026-05-04T19:12:33-0400"; that offset is what puts the video on the right calendar day.
   */
  static Integer parseOffsetSeconds(String raw) {
    if (raw == null || raw.isBlank()) {
      return null;
    }
    String value = raw.trim().replace(' ', 'T').replaceFirst("([+-]\\d{2})(\\d{2})$", "$1:$2");
    try {
      return OffsetDateTime.parse(value).getOffset().getTotalSeconds();
    } catch (DateTimeParseException noOffset) {
      return null;
    }
  }

  /**
   * Parses the timestamp forms ffprobe emits. {@code Instant.parse} alone is not enough: it rejects
   * the colon-less offset Apple writes ({@code 2026-08-17T14:23:11+0200}), and a bare {@code
   * DateTimeParseException} there would have silently dropped the date. A value with no zone at all
   * is treated as UTC, which is what the mvhd atom is defined to hold.
   *
   * @return the instant, or null if the value is absent or in no recognised form
   */
  static Instant parseTimestamp(String raw) {
    if (raw == null || raw.isBlank()) {
      return null;
    }
    String value = raw.trim().replace(' ', 'T');
    // "+0200" → "+02:00" so the ISO parsers accept it.
    value = value.replaceFirst("([+-]\\d{2})(\\d{2})$", "$1:$2");
    try {
      return OffsetDateTime.parse(value).toInstant();
    } catch (DateTimeParseException withOffset) {
      try {
        return LocalDateTime.parse(value).toInstant(ZoneOffset.UTC);
      } catch (DateTimeParseException withoutOffset) {
        log.debug("Unrecognised ffprobe timestamp '{}'", raw);
        return null;
      }
    }
  }
}
