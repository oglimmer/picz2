/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.config.FileStorageProperties.Thumbnailer;
import com.oglimmer.photoupload.config.Profiles;
import java.io.IOException;
import java.nio.file.Path;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.TimeUnit;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

/**
 * Façade for image/video processing. Routes thumbnail generation to {@link VipsThumbnailService} or
 * the legacy ImageMagick path here based on {@code file.upload.thumbnailer}; HEIC and ffmpeg work
 * is delegated to dedicated services.
 */
@Service
@Profile(Profiles.WORKER)
@Slf4j
@RequiredArgsConstructor
public class ThumbnailService {

  private final FileStorageProperties properties;
  private final VipsThumbnailService vipsThumbnailService;
  private final HeicConversionService heicConversionService;
  private final FfmpegService ffmpegService;

  /**
   * Generate all thumbnail sizes for an image. Routes to vipsthumbnail by default; falls back to
   * the legacy ImageMagick pipeline when {@code file.upload.thumbnailer=magick}.
   */
  public Path[] generateAllThumbnails(Path originalFile, Path baseOutputPath) {
    if (properties.getThumbnailer() == Thumbnailer.VIPS) {
      return vipsThumbnailService.generateAllThumbnails(originalFile, baseOutputPath);
    }
    return generateAllThumbnailsMagick(originalFile, baseOutputPath);
  }

  /**
   * Legacy ImageMagick thumbnail pipeline. Decodes the source once, progressively downscales (large
   * -> medium -> thumb) and writes each size via {@code +clone -write}. Memory is bounded by
   * ImageMagick {@code -limit} flags. {@code -define jpeg:size=} pre-scales during JPEG decode.
   */
  Path[] generateAllThumbnailsMagick(Path originalFile, Path baseOutputPath) {
    Path[] thumbnailPaths = new Path[3];

    String baseName = baseOutputPath.getFileName().toString();
    Path parentDir = baseOutputPath.getParent();

    Path thumbnailPath = parentDir.resolve("thumb_" + baseName);
    Path mediumPath = parentDir.resolve("medium_" + baseName);
    Path largePath = parentDir.resolve("large_" + baseName);

    ThumbnailSize thumb = ThumbnailSize.THUMBNAIL;
    ThumbnailSize medium = ThumbnailSize.MEDIUM;
    ThumbnailSize large = ThumbnailSize.LARGE;

    String largeGeom = large.getMaxWidth() + "x" + large.getMaxHeight() + ">";
    String mediumGeom = medium.getMaxWidth() + "x" + medium.getMaxHeight() + ">";
    String thumbGeom = thumb.getMaxWidth() + "x" + thumb.getMaxHeight() + ">";
    String jpegSizeHint = (large.getMaxWidth() * 2) + "x" + (large.getMaxHeight() * 2);

    parentDir.toFile().mkdirs();

    List<String> cmd =
        List.of(
            "convert",
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
            "60",
            "-define",
            "jpeg:size=" + jpegSizeHint,
            originalFile.toAbsolutePath().toString(),
            "-auto-orient",
            "-resize",
            largeGeom,
            "(",
            "+clone",
            "-quality",
            String.valueOf((int) (large.getJpegQuality() * 100)),
            "-write",
            largePath.toAbsolutePath().toString(),
            "+delete",
            ")",
            "-resize",
            mediumGeom,
            "(",
            "+clone",
            "-quality",
            String.valueOf((int) (medium.getJpegQuality() * 100)),
            "-write",
            mediumPath.toAbsolutePath().toString(),
            "+delete",
            ")",
            "-resize",
            thumbGeom,
            "-quality",
            String.valueOf((int) (thumb.getJpegQuality() * 100)),
            thumbnailPath.toAbsolutePath().toString());

    try {
      log.info("Generating thumbnails via ImageMagick for: {}", originalFile.getFileName());
      ProcessRunner.Result r = ProcessRunner.run(cmd, 90, TimeUnit.SECONDS);

      if (!r.success()) {
        log.error(
            "ImageMagick thumbnail generation failed (exit {}, timedOut={}) for {}: {}",
            r.exitCode(),
            r.timedOut(),
            originalFile.getFileName(),
            r.output());
      }

      // Pick up whatever ImageMagick managed to write, even on partial failure.
      if (thumbnailPath.toFile().exists() && thumbnailPath.toFile().length() > 0) {
        thumbnailPaths[0] = thumbnailPath;
      }
      if (mediumPath.toFile().exists() && mediumPath.toFile().length() > 0) {
        thumbnailPaths[1] = mediumPath;
      }
      if (largePath.toFile().exists() && largePath.toFile().length() > 0) {
        thumbnailPaths[2] = largePath;
      }

    } catch (IOException e) {
      log.error("IO error during thumbnail generation for {}: {}", originalFile, e.getMessage());
    }
    return thumbnailPaths;
  }

  public boolean transcodeVideo(Path originalFile, Path outputPath) {
    return ffmpegService.transcodeVideo(originalFile, outputPath);
  }

  public boolean convertHeicToJpeg(Path originalFile, Path outputPath) {
    return heicConversionService.convertHeicToJpeg(originalFile, outputPath);
  }

  public boolean generateVideoThumbnail(Path videoFile, Path outputPath) {
    return ffmpegService.generateVideoThumbnail(videoFile, outputPath);
  }

  public Instant extractVideoCreationDate(Path videoFile) {
    return ffmpegService.extractVideoCreationDate(videoFile);
  }

  /** Rotate an image 90 degrees counterclockwise via ImageMagick. */
  public boolean rotateImageLeft(Path imageFile) {
    Path tempFile = imageFile.getParent().resolve(imageFile.getFileName().toString() + ".tmp");
    List<String> cmd =
        List.of(
            "convert",
            imageFile.toAbsolutePath().toString(),
            "-rotate",
            "-90",
            tempFile.toAbsolutePath().toString());
    try {
      log.info("🔄 Rotating left: {}", imageFile.getFileName());
      ProcessRunner.Result r = ProcessRunner.run(cmd, 60, TimeUnit.SECONDS);
      if (r.success() && tempFile.toFile().exists()) {
        java.nio.file.Files.delete(imageFile);
        java.nio.file.Files.move(tempFile, imageFile);
        log.info("✅ Rotated image 90° left: {}", imageFile.getFileName());
        return true;
      }
      log.error(
          "Image rotation failed (exit {}, timedOut={}) for {}: {}",
          r.exitCode(),
          r.timedOut(),
          imageFile.getFileName(),
          r.output());
      java.nio.file.Files.deleteIfExists(tempFile);
      return false;
    } catch (IOException e) {
      log.error("IO error during image rotation for {}: {}", imageFile, e.getMessage(), e);
      try {
        java.nio.file.Files.deleteIfExists(tempFile);
      } catch (IOException ignored) {
        // best-effort cleanup
      }
      return false;
    }
  }

  @Getter
  public enum ThumbnailSize {
    THUMBNAIL(600, 600, 0.6f),
    MEDIUM(1200, 1200, 0.95f),
    LARGE(2400, 2400, 0.95f);

    private final int maxWidth;
    private final int maxHeight;
    private final float jpegQuality;

    ThumbnailSize(int maxWidth, int maxHeight, float jpegQuality) {
      this.maxWidth = maxWidth;
      this.maxHeight = maxHeight;
      this.jpegQuality = jpegQuality;
    }
  }
}
