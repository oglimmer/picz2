/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.drew.imaging.ImageMetadataReader;
import com.drew.lang.GeoLocation;
import com.drew.metadata.Metadata;
import com.drew.metadata.exif.GpsDirectory;
import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.GpsSource;
import com.oglimmer.photoupload.model.GpsCoordinates;
import com.oglimmer.photoupload.util.MimeTypePredicates;
import java.nio.file.Path;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

/**
 * Resolves where a photo or video was taken, in signed decimal degrees (WGS 84).
 *
 * <p>Deliberately mirrors {@link CaptureDateExtractor}: same dispatch on mime type, same "always
 * return a source, never throw" contract. The location lives only in the original file — no
 * derivative carries the EXIF GPS IFD or the QuickTime location atom — so this can only ever run
 * while {@code file_path} is still set.
 *
 * <p>An image's coordinates are read straight from the GPS IFD rather than reconstructed from the
 * rational degree/minute/second triples: metadata-extractor's {@code getGeoLocation()} already
 * applies the N/S and E/W reference tags, and getting those signs wrong mirrors a photo into the
 * wrong hemisphere.
 */
@Service
@Profile(Profiles.WORKER)
@Slf4j
@RequiredArgsConstructor
public class GpsExtractor {

  private final ThumbnailService thumbnailService;

  /** Dispatches on mime type; anything that is neither image nor video has no location. */
  public GpsCoordinates extract(Path file, String mimeType) {
    if (MimeTypePredicates.isImageFile(mimeType)) {
      return fromImageExif(file);
    }
    if (MimeTypePredicates.isVideoFile(mimeType)) {
      return thumbnailService.extractVideoLocation(file);
    }
    return GpsCoordinates.none();
  }

  private GpsCoordinates fromImageExif(Path imagePath) {
    try {
      Metadata metadata = ImageMetadataReader.readMetadata(imagePath.toFile());
      GpsDirectory directory = metadata.getFirstDirectoryOfType(GpsDirectory.class);
      if (directory == null) {
        return GpsCoordinates.none();
      }
      GeoLocation location = directory.getGeoLocation();
      if (location == null || location.isZero()) {
        return GpsCoordinates.none();
      }
      log.info(
          "🌍 EXIF GPS {}/{} for {}",
          location.getLatitude(),
          location.getLongitude(),
          imagePath.getFileName());
      return GpsCoordinates.of(location.getLatitude(), location.getLongitude(), GpsSource.EXIF_GPS);
    } catch (Exception e) {
      log.debug("Could not read EXIF GPS from {}: {}", imagePath.getFileName(), e.getMessage());
      return GpsCoordinates.none();
    }
  }
}
