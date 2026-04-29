/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import java.io.File;
import java.nio.file.Path;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Best-effort local-disk cleanup helpers (thumbnail / transcoded video). Carries no Vips/Heic/Ffmpeg
 * dependency so the api pod can wire it without dragging in worker-only beans.
 */
@Service
@Slf4j
public class LocalFileCleanupService {

  public void deleteThumbnails(Path thumbnailPath, Path mediumPath, Path largePath) {
    deleteIfExists(thumbnailPath, "thumbnail");
    deleteIfExists(mediumPath, "thumbnail");
    deleteIfExists(largePath, "thumbnail");
  }

  public void deleteTranscodedVideo(Path transcodedVideoPath) {
    deleteIfExists(transcodedVideoPath, "transcoded video");
  }

  private void deleteIfExists(Path path, String label) {
    if (path == null) {
      return;
    }
    try {
      File file = path.toFile();
      if (file.exists()) {
        file.delete();
        log.debug("Deleted {}: {}", label, path);
      }
    } catch (Exception e) {
      log.warn("Failed to delete {} {}: {}", label, path, e.getMessage());
    }
  }
}
