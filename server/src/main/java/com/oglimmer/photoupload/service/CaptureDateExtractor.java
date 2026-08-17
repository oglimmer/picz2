/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.drew.imaging.ImageMetadataReader;
import com.drew.metadata.Metadata;
import com.drew.metadata.exif.ExifSubIFDDirectory;
import com.oglimmer.photoupload.config.CaptureDateProperties;
import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.CaptureDateSource;
import com.oglimmer.photoupload.model.CaptureDate;
import com.oglimmer.photoupload.util.MimeTypePredicates;
import java.nio.file.Path;
import java.time.DateTimeException;
import java.time.ZoneOffset;
import java.util.Date;
import java.util.TimeZone;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

/**
 * Resolves when a photo or video was actually taken, as a true instant.
 *
 * <p>Photos and videos record capture time on different clocks, and getting this wrong shears one
 * media type against the other in album sort order:
 *
 * <ul>
 *   <li>EXIF {@code DateTimeOriginal} is a bare wall clock. metadata-extractor's single-argument
 *       {@code getDate(tag)} hardcodes GMT for zone-less strings and never consults {@code
 *       OffsetTimeOriginal}, so it yields the local wall clock relabelled UTC — an instant that is
 *       wrong by the phone's UTC offset. We pass the offset explicitly instead.
 *   <li>QuickTime carries {@code com.apple.quicktime.creationdate} (local time plus offset) and an
 *       {@code mvhd} creation time that ffmpeg already normalises to UTC. Both are real instants.
 * </ul>
 */
@Service
@Profile(Profiles.WORKER)
@Slf4j
@RequiredArgsConstructor
public class CaptureDateExtractor {

  /**
   * EXIF 2.31 {@code OffsetTimeOriginal} — the UTC offset that applies to DateTimeOriginal, e.g.
   * "+02:00". metadata-extractor 2.19 parses the tag but exposes no constant for it.
   */
  private static final int TAG_OFFSET_TIME_ORIGINAL = 0x9011;

  private final CaptureDateProperties properties;
  private final ThumbnailService thumbnailService;

  /** Dispatches on mime type; anything that is neither image nor video has no capture date. */
  public CaptureDate extract(Path file, String mimeType) {
    if (MimeTypePredicates.isImageFile(mimeType)) {
      return fromImageExif(file);
    }
    if (MimeTypePredicates.isVideoFile(mimeType)) {
      return thumbnailService.extractVideoCreationDate(file);
    }
    return CaptureDate.none();
  }

  private CaptureDate fromImageExif(Path imagePath) {
    try {
      Metadata metadata = ImageMetadataReader.readMetadata(imagePath.toFile());
      ExifSubIFDDirectory directory = metadata.getFirstDirectoryOfType(ExifSubIFDDirectory.class);
      if (directory == null || !directory.containsTag(ExifSubIFDDirectory.TAG_DATETIME_ORIGINAL)) {
        return CaptureDate.none();
      }

      ZoneOffset offset = parseExifOffset(directory.getString(TAG_OFFSET_TIME_ORIGINAL));
      TimeZone zone =
          offset != null
              ? TimeZone.getTimeZone(offset)
              : TimeZone.getTimeZone(properties.getFallbackZone());
      CaptureDateSource source =
          offset != null
              ? CaptureDateSource.EXIF_OFFSET_TIME
              : CaptureDateSource.EXIF_FALLBACK_ZONE;

      Date date =
          directory.getDate(
              ExifSubIFDDirectory.TAG_DATETIME_ORIGINAL,
              directory.getString(ExifSubIFDDirectory.TAG_SUBSECOND_TIME_ORIGINAL),
              zone);
      if (date == null) {
        return CaptureDate.none();
      }
      log.info(
          "📷 EXIF DateTimeOriginal '{}' in {} → {}",
          directory.getString(ExifSubIFDDirectory.TAG_DATETIME_ORIGINAL),
          zone.getID(),
          date.toInstant());
      return CaptureDate.of(date.toInstant(), source);
    } catch (Exception e) {
      log.debug("Could not read EXIF from {}: {}", imagePath.getFileName(), e.getMessage());
      return CaptureDate.none();
    }
  }

  /**
   * Parses an {@code OffsetTimeOriginal} value. The tag is specified as "+HH:MM" but is written by
   * enough different toolchains that a colon-less "+HHMM" turns up in the wild too; both parse.
   * Returns null for absent or unparseable values, which routes the caller to the fallback zone.
   */
  private static ZoneOffset parseExifOffset(String raw) {
    if (raw == null || raw.isBlank()) {
      return null;
    }
    String value = raw.trim();
    if (value.matches("[+-]\\d{4}")) {
      value = value.substring(0, 3) + ":" + value.substring(3);
    }
    try {
      return ZoneOffset.of(value);
    } catch (DateTimeException e) {
      log.debug("Ignoring unparseable OffsetTimeOriginal '{}'", raw);
      return null;
    }
  }
}
