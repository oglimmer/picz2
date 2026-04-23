/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import java.io.File;
import java.io.IOException;
import java.nio.file.Path;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import lombok.Getter;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Service
@Slf4j
public class ThumbnailService {

  /**
   * Generate all thumbnail sizes for an image in a single ImageMagick pipeline.
   *
   * <p>Decodes the source once, progressively downscales (large -> medium -> thumb) and writes each
   * size via {@code +clone -write}. Memory is bounded by ImageMagick {@code -limit} flags on the
   * native process, avoiding JVM heap/native pressure from {@code BufferedImage}. {@code
   * -auto-orient} replaces the prior EXIF-orientation logic. {@code -define jpeg:size=} lets
   * libjpeg pre-scale during decode, saving significant memory on large JPEGs.
   *
   * @param originalFile The original image file
   * @param baseOutputPath The base path for thumbnails (without size suffix)
   * @return Array of paths [thumbnail, medium, large] or nulls for failed generations
   */
  public Path[] generateAllThumbnails(Path originalFile, Path baseOutputPath) {
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
    // Pre-scale during JPEG decode: hint libjpeg to decode at ~2x the largest target.
    String jpegSizeHint = (large.getMaxWidth() * 2) + "x" + (large.getMaxHeight() * 2);

    try {
      parentDir.toFile().mkdirs();

      ProcessBuilder processBuilder =
          new ProcessBuilder(
              "convert",
              "-limit",
              "memory",
              "512MiB",
              "-limit",
              "map",
              "1024MiB",
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

      processBuilder.redirectErrorStream(true);
      log.info("Generating thumbnails via ImageMagick for: {}", originalFile.getFileName());

      Process process = processBuilder.start();

      java.io.BufferedReader reader =
          new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream()));
      String line;
      StringBuilder output = new StringBuilder();
      while ((line = reader.readLine()) != null) {
        output.append(line).append("\n");
      }

      int exitCode = process.waitFor();

      if (exitCode != 0) {
        log.error(
            "ImageMagick thumbnail generation failed with exit code {} for {}: {}",
            exitCode,
            originalFile.getFileName(),
            output);
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

      if (exitCode == 0) {
        log.info(
            "Generated thumbnails for {} (thumb {}, medium {}, large {})",
            originalFile.getFileName(),
            formatBytes(thumbnailPath.toFile().length()),
            formatBytes(mediumPath.toFile().length()),
            formatBytes(largePath.toFile().length()));
      }

      return thumbnailPaths;

    } catch (IOException e) {
      log.error("IO error during thumbnail generation for {}: {}", originalFile, e.getMessage());
      return thumbnailPaths;
    } catch (InterruptedException e) {
      log.error("Thumbnail generation interrupted for {}: {}", originalFile, e.getMessage());
      Thread.currentThread().interrupt();
      return thumbnailPaths;
    }
  }

  /** Check if a file is an image that can be thumbnailed */
  public boolean isImageFile(String mimeType) {
    if (mimeType == null) {
      return false;
    }
    return mimeType.startsWith("image/")
        && !mimeType.equals("image/heic")
        && !mimeType.equals("image/heif"); // HEIC/HEIF need special handling
  }

  /** Check if a file is HEIC/HEIF format that needs conversion */
  public boolean isHeicFile(String mimeType) {
    if (mimeType == null) {
      return false;
    }
    return mimeType.equals("image/heic") || mimeType.equals("image/heif");
  }

  /** Check if a file is a video that should be transcoded */
  public boolean isVideoFile(String mimeType) {
    if (mimeType == null) {
      return false;
    }
    return mimeType.startsWith("video/");
  }

  /**
   * Transcode video to Safari/iOS-compatible MP4 format Uses H.264 Main profile and AAC audio for
   * maximum compatibility
   *
   * @param originalFile The original video file
   * @param outputPath The path where the transcoded video should be saved
   * @return true if successful, false otherwise
   */
  public boolean transcodeVideo(Path originalFile, Path outputPath) {
    try {
      // Ensure output directory exists
      File outputFile = outputPath.toFile();
      outputFile.getParentFile().mkdirs();

      // Build ffmpeg command for Safari/iOS compatibility
      // -profile:v main -level 4.0: H.264 Main profile (Safari/iOS compatible)
      // -c:a aac -b:a 128k: AAC audio codec
      // -movflags +faststart: Optimize MP4 for web streaming
      // -preset medium: Balance encoding speed vs file size
      ProcessBuilder processBuilder =
          new ProcessBuilder(
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
              "-y", // Overwrite output file if it exists
              outputPath.toAbsolutePath().toString());

      processBuilder.redirectErrorStream(true);
      log.debug(
          "Starting video transcoding: {} -> {}",
          originalFile.getFileName(),
          outputPath.getFileName());

      Process process = processBuilder.start();

      // Read output for logging (optional, helps with debugging)
      java.io.BufferedReader reader =
          new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream()));
      String line;
      StringBuilder output = new StringBuilder();
      while ((line = reader.readLine()) != null) {
        output.append(line).append("\n");
      }

      int exitCode = process.waitFor();

      if (exitCode == 0 && outputFile.exists()) {
        log.info(
            "Successfully transcoded video: {} -> {} ({})",
            originalFile.getFileName(),
            outputPath.getFileName(),
            formatBytes(outputFile.length()));
        return true;
      } else {
        log.error(
            "Video transcoding failed with exit code {}: {}", exitCode, originalFile.getFileName());
        log.debug("ffmpeg output: {}", output);
        return false;
      }

    } catch (IOException e) {
      log.error("IO error during video transcoding for {}: {}", originalFile, e.getMessage());
      return false;
    } catch (InterruptedException e) {
      log.error("Video transcoding interrupted for {}: {}", originalFile, e.getMessage());
      Thread.currentThread().interrupt();
      return false;
    }
  }

  /**
   * Convert HEIC/HEIF image to JPEG format using ImageMagick Uses the latest ImageMagick AppImage
   * which has better HEIC support than package manager versions Handles modern iPhone HEIC files
   * with multiple image references, depth maps, and HDR data
   *
   * @param originalFile The original HEIC/HEIF file
   * @param outputPath The path where the converted JPEG should be saved
   * @return true if successful, false otherwise
   */
  public boolean convertHeicToJpeg(Path originalFile, Path outputPath) {
    try {
      // Ensure output directory exists
      File outputFile = outputPath.toFile();
      outputFile.getParentFile().mkdirs();

      // Use ImageMagick's convert command.
      // Memory limits prevent ImageMagick from consuming excessive memory.
      // -auto-orient bakes any HEIF irot/EXIF orientation into the pixels and clears the tag, so
      // downstream consumers (thumbnailer, browser) see a normalized JPEG regardless of how
      // libheif/ImageMagick handled orientation during HEIC decode.
      ProcessBuilder processBuilder =
          new ProcessBuilder(
              "convert",
              "-limit",
              "memory",
              "512MiB",
              "-limit",
              "map",
              "1024MiB",
              originalFile.toAbsolutePath().toString(),
              "-auto-orient",
              "-quality",
              "95",
              outputPath.toAbsolutePath().toString());

      processBuilder.redirectErrorStream(true);
      log.info(
          "Converting HEIC/HEIF using ImageMagick: {} -> {}",
          originalFile.getFileName(),
          outputPath.getFileName());

      Process process = processBuilder.start();

      // Read output for logging
      java.io.BufferedReader reader =
          new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream()));
      String line;
      StringBuilder output = new StringBuilder();
      while ((line = reader.readLine()) != null) {
        output.append(line).append("\n");
      }

      int exitCode = process.waitFor();

      if (exitCode == 0 && outputFile.exists() && outputFile.length() > 0) {
        log.info(
            "✅ Converted HEIC/HEIF to JPEG: {} -> {} ({})",
            originalFile.getFileName(),
            outputPath.getFileName(),
            formatBytes(outputFile.length()));
        return true;
      } else {
        log.error(
            "ImageMagick HEIC conversion failed with exit code {}: {}",
            exitCode,
            originalFile.getFileName());
        if (output.length() > 0) {
          log.error("ImageMagick output: {}", output);
        }
        return false;
      }

    } catch (IOException e) {
      log.error(
          "IO error during ImageMagick HEIC conversion for {}: {}", originalFile, e.getMessage());
      return false;
    } catch (InterruptedException e) {
      log.error("ImageMagick HEIC conversion interrupted for {}: {}", originalFile, e.getMessage());
      Thread.currentThread().interrupt();
      return false;
    }
  }

  /** Format bytes for logging */
  private String formatBytes(long bytes) {
    if (bytes < 1024) {
      return bytes + " B";
    }
    int exp = (int) (Math.log(bytes) / Math.log(1024));
    String pre = "KMGTPE".charAt(exp - 1) + "";
    return String.format("%.1f %sB", bytes / Math.pow(1024, exp), pre);
  }

  /** Delete transcoded video file */
  public void deleteTranscodedVideo(Path transcodedVideoPath) {
    if (transcodedVideoPath != null) {
      try {
        File file = transcodedVideoPath.toFile();
        if (file.exists()) {
          file.delete();
          log.debug("Deleted transcoded video: {}", transcodedVideoPath);
        }
      } catch (Exception e) {
        log.warn("Failed to delete transcoded video {}: {}", transcodedVideoPath, e.getMessage());
      }
    }
  }

  /**
   * Generate a thumbnail image from a video file Extracts the first frame at 1 second into the
   * video
   *
   * @param videoFile The original video file
   * @param outputPath The path where the thumbnail image should be saved (should end with .jpg)
   * @return true if successful, false otherwise
   */
  public boolean generateVideoThumbnail(Path videoFile, Path outputPath) {
    try {
      // Ensure output directory exists
      File outputFile = outputPath.toFile();
      outputFile.getParentFile().mkdirs();

      // Build ffmpeg command to extract frame at 1 second
      // -ss 1: Seek to 1 second position
      // -i: Input file
      // -vframes 1: Extract only 1 frame
      // -vf scale=600:-1: Scale to 600px width, maintain aspect ratio
      // -q:v 2: High quality JPEG (scale 2-31, lower is better)
      ProcessBuilder processBuilder =
          new ProcessBuilder(
              "ffmpeg",
              "-ss",
              "1", // Seek to 1 second
              "-i",
              videoFile.toAbsolutePath().toString(),
              "-vframes",
              "1", // Extract 1 frame
              "-vf",
              "scale=600:-1", // Scale to thumbnail size
              "-q:v",
              "2", // High quality JPEG
              "-y", // Overwrite output file if exists
              outputPath.toAbsolutePath().toString());

      processBuilder.redirectErrorStream(true);
      log.debug(
          "Generating video thumbnail: {} -> {}",
          videoFile.getFileName(),
          outputPath.getFileName());

      Process process = processBuilder.start();

      // Read output for logging
      java.io.BufferedReader reader =
          new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream()));
      String line;
      StringBuilder output = new StringBuilder();
      while ((line = reader.readLine()) != null) {
        output.append(line).append("\n");
      }

      int exitCode = process.waitFor();

      if (exitCode == 0 && outputFile.exists()) {
        log.info(
            "Generated video thumbnail: {} ({} bytes)",
            videoFile.getFileName(),
            outputFile.length());
        return true;
      } else {
        log.error(
            "Video thumbnail generation failed with exit code {}: {}",
            exitCode,
            videoFile.getFileName());
        log.debug("ffmpeg output: {}", output);
        return false;
      }

    } catch (IOException e) {
      log.error("IO error during video thumbnail generation for {}: {}", videoFile, e.getMessage());
      return false;
    } catch (InterruptedException e) {
      log.error("Video thumbnail generation interrupted for {}: {}", videoFile, e.getMessage());
      Thread.currentThread().interrupt();
      return false;
    }
  }

  /**
   * Extract the container-level creation timestamp from a video via ffprobe. Reads the {@code
   * format_tags=creation_time} field (populated from MP4/MOV atoms). Returns null if the tag is
   * missing, unparseable, or ffprobe fails.
   */
  public Instant extractVideoCreationDate(Path videoFile) {
    try {
      ProcessBuilder processBuilder =
          new ProcessBuilder(
              "ffprobe",
              "-v",
              "quiet",
              "-show_entries",
              "format_tags=creation_time",
              "-of",
              "default=noprint_wrappers=1:nokey=1",
              videoFile.toAbsolutePath().toString());

      processBuilder.redirectErrorStream(true);
      Process process = processBuilder.start();

      StringBuilder output = new StringBuilder();
      try (java.io.BufferedReader reader =
          new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream()))) {
        String line;
        while ((line = reader.readLine()) != null) {
          output.append(line).append("\n");
        }
      }

      int exitCode = process.waitFor();
      String value = output.toString().trim();

      if (exitCode != 0 || value.isEmpty()) {
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
    } catch (InterruptedException e) {
      log.debug("Video metadata extraction interrupted for {}", videoFile.getFileName());
      Thread.currentThread().interrupt();
      return null;
    }
  }

  /**
   * Rotate an image file 90 degrees counterclockwise (to the left) using ImageMagick
   *
   * @param imageFile The image file to rotate
   * @return true if successful, false otherwise
   */
  public boolean rotateImageLeft(Path imageFile) {
    try {
      log.info("🔄 Starting rotation for: {}", imageFile.getFileName());
      log.info("   File path: {}", imageFile.toAbsolutePath());
      log.info("   File exists: {}", imageFile.toFile().exists());

      // Create a temporary file for the rotated image
      Path tempFile = imageFile.getParent().resolve(imageFile.getFileName().toString() + ".tmp");

      // Use ImageMagick to rotate the image 90 degrees counterclockwise
      // -rotate -90: Rotate 90 degrees counterclockwise
      ProcessBuilder processBuilder =
          new ProcessBuilder(
              "convert",
              imageFile.toAbsolutePath().toString(),
              "-rotate",
              "-90",
              tempFile.toAbsolutePath().toString());

      processBuilder.redirectErrorStream(true);
      log.info(
          "   Executing: convert {} -rotate -90 {}",
          imageFile.getFileName(),
          tempFile.getFileName());

      Process process = processBuilder.start();

      // Read output for logging
      java.io.BufferedReader reader =
          new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream()));
      String line;
      StringBuilder output = new StringBuilder();
      while ((line = reader.readLine()) != null) {
        output.append(line).append("\n");
      }

      int exitCode = process.waitFor();
      log.info("   ImageMagick (convert) exit code: {}", exitCode);
      log.info("   Temp file exists: {}", tempFile.toFile().exists());

      if (output.length() > 0) {
        log.info("   ImageMagick (convert) output: {}", output);
      }

      if (exitCode == 0 && tempFile.toFile().exists()) {
        // Replace original file with rotated version
        log.info("   Replacing original file with rotated version");
        java.nio.file.Files.delete(imageFile);
        java.nio.file.Files.move(tempFile, imageFile);

        log.info(
            "✅ Successfully rotated image 90° left using ImageMagick (convert): {}",
            imageFile.getFileName());
        return true;
      } else {
        log.error(
            "❌ Image rotation failed with exit code {}: {}", exitCode, imageFile.getFileName());
        if (output.length() > 0) {
          log.error("   ImageMagick (convert) output: {}", output);
        }
        // Clean up temp file if it exists
        java.nio.file.Files.deleteIfExists(tempFile);
        return false;
      }

    } catch (IOException e) {
      log.error("❌ IO error during image rotation for {}: {}", imageFile, e.getMessage(), e);
      return false;
    } catch (InterruptedException e) {
      log.error("❌ Image rotation interrupted for {}: {}", imageFile, e.getMessage(), e);
      Thread.currentThread().interrupt();
      return false;
    }
  }

  /** Delete all thumbnails for a file */
  public void deleteThumbnails(Path thumbnailPath, Path mediumPath, Path largePath) {
    deleteThumbnailFile(thumbnailPath);
    deleteThumbnailFile(mediumPath);
    deleteThumbnailFile(largePath);
  }

  private void deleteThumbnailFile(Path path) {
    if (path != null) {
      try {
        File file = path.toFile();
        if (file.exists()) {
          file.delete();
          log.debug("Deleted thumbnail: {}", path);
        }
      } catch (Exception e) {
        log.warn("Failed to delete thumbnail {}: {}", path, e.getMessage());
      }
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
