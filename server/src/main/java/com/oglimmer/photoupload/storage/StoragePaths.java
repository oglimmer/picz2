/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.storage;

import com.oglimmer.photoupload.entity.FileMetadata;

/**
 * Single source of truth for the S3 key convention. Keeps the prefix check co-located with the
 * key generators so they cannot drift.
 *
 * <pre>
 *   originals/{stored_filename}
 *   derivatives/{assetId}/thumb.jpg
 *   derivatives/{assetId}/medium.jpg
 *   derivatives/{assetId}/large.jpg
 *   derivatives/{assetId}/transcoded.mp4
 *   audio/{audio_filename}
 * </pre>
 */
public final class StoragePaths {

  public static final String ORIGINALS_PREFIX = "originals/";
  public static final String DERIVATIVES_PREFIX = "derivatives/";
  public static final String AUDIO_PREFIX = "audio/";

  private StoragePaths() {}

  public static boolean isS3Key(String path) {
    if (path == null) {
      return false;
    }
    return path.startsWith(ORIGINALS_PREFIX) || path.startsWith(DERIVATIVES_PREFIX);
  }

  public static boolean isAudioS3Key(String path) {
    return path != null && path.startsWith(AUDIO_PREFIX);
  }

  public static String audioKey(String audioFilename) {
    return AUDIO_PREFIX + audioFilename;
  }

  /**
   * Key for the original file. Uses {@code stored_filename} which already carries a UUID +
   * timestamp suffix, so collisions are not a concern.
   */
  public static String originalKey(FileMetadata metadata) {
    return ORIGINALS_PREFIX + metadata.getStoredFilename();
  }

  public static String derivativeThumbnailKey(Long assetId) {
    return DERIVATIVES_PREFIX + assetId + "/thumb.jpg";
  }

  public static String derivativeMediumKey(Long assetId) {
    return DERIVATIVES_PREFIX + assetId + "/medium.jpg";
  }

  public static String derivativeLargeKey(Long assetId) {
    return DERIVATIVES_PREFIX + assetId + "/large.jpg";
  }

  public static String derivativeTranscodedKey(Long assetId) {
    return DERIVATIVES_PREFIX + assetId + "/transcoded.mp4";
  }
}
