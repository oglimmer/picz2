/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.util;

/**
 * Pure mime-type classifiers used by both api and worker profiles. Lives outside
 * {@code ThumbnailService} so the api pod can decide image-vs-video without pulling
 * Vips/Heic/Ffmpeg beans into the context (those are worker-only).
 */
public final class MimeTypePredicates {

  private MimeTypePredicates() {}

  public static boolean isImageFile(String mimeType) {
    if (mimeType == null) {
      return false;
    }
    return mimeType.startsWith("image/")
        && !mimeType.equals("image/heic")
        && !mimeType.equals("image/heif");
  }

  public static boolean isHeicFile(String mimeType) {
    if (mimeType == null) {
      return false;
    }
    return mimeType.equals("image/heic") || mimeType.equals("image/heif");
  }

  public static boolean isVideoFile(String mimeType) {
    if (mimeType == null) {
      return false;
    }
    return mimeType.startsWith("video/");
  }
}
