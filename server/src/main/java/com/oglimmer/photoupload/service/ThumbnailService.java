/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.drew.imaging.ImageMetadataReader;
import com.drew.imaging.ImageProcessingException;
import com.drew.metadata.Metadata;
import com.drew.metadata.MetadataException;
import com.drew.metadata.exif.ExifIFD0Directory;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.Transparency;
import java.awt.geom.AffineTransform;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.nio.file.Path;
import java.util.Iterator;
import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.stream.ImageOutputStream;
import lombok.Getter;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Service
@Slf4j
public class ThumbnailService {

  /**
   * Generate a thumbnail for an image file
   *
   * @param originalFile The original image file
   * @param outputPath The path where the thumbnail should be saved
   * @param size The thumbnail size to generate
   * @return true if successful, false otherwise
   */
  public boolean generateThumbnail(Path originalFile, Path outputPath, ThumbnailSize size) {
    try {
      BufferedImage originalImage = ImageIO.read(originalFile.toFile());
      if (originalImage == null) {
        log.warn("Could not read image file: {}", originalFile);
        return false;
      }

      // Read EXIF orientation and apply transformation
      int orientation = getExifOrientation(originalFile);
      if (orientation != 1) {
        log.debug("Applying EXIF orientation {} to {}", orientation, originalFile.getFileName());
        originalImage = applyOrientation(originalImage, orientation);
      }

      // Calculate scaled dimensions while maintaining aspect ratio
      int originalWidth = originalImage.getWidth();
      int originalHeight = originalImage.getHeight();

      double widthRatio = (double) size.getMaxWidth() / originalWidth;
      double heightRatio = (double) size.getMaxHeight() / originalHeight;
      double ratio = Math.min(widthRatio, heightRatio);

      // Don't upscale images
      if (ratio > 1.0) {
        ratio = 1.0;
      }

      int targetWidth = (int) (originalWidth * ratio);
      int targetHeight = (int) (originalHeight * ratio);

      // Create scaled image with high quality, preserving image type
      // Use ARGB for images with transparency, RGB otherwise
      int imageType =
          originalImage.getTransparency() == Transparency.OPAQUE
              ? BufferedImage.TYPE_INT_RGB
              : BufferedImage.TYPE_INT_ARGB;
      BufferedImage scaledImage = new BufferedImage(targetWidth, targetHeight, imageType);
      Graphics2D graphics = scaledImage.createGraphics();

      // Use high-quality rendering hints
      graphics.setRenderingHint(
          RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
      graphics.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
      graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
      graphics.setRenderingHint(
          RenderingHints.KEY_ALPHA_INTERPOLATION, RenderingHints.VALUE_ALPHA_INTERPOLATION_QUALITY);

      graphics.drawImage(originalImage, 0, 0, targetWidth, targetHeight, null);
      graphics.dispose();

      // Save the thumbnail
      File outputFile = outputPath.toFile();
      outputFile.getParentFile().mkdirs();

      // Determine format from original file
      String format = getImageFormat(originalFile);
      writeImageWithQuality(scaledImage, outputFile, format, size.getJpegQuality());

      log.debug(
          "Generated {} thumbnail: {} ({}x{}) at {}% quality",
          size, outputPath, targetWidth, targetHeight, (int) (size.getJpegQuality() * 100));
      return true;

    } catch (IOException e) {
      log.error("Error generating thumbnail for {}: {}", originalFile, e.getMessage());
      return false;
    }
  }

  /**
   * Generate all thumbnail sizes for an image
   *
   * @param originalFile The original image file
   * @param baseOutputPath The base path for thumbnails (without size suffix)
   * @return Array of paths [thumbnail, medium, large] or nulls for failed generations
   */
  public Path[] generateAllThumbnails(Path originalFile, Path baseOutputPath) {
    Path[] thumbnailPaths = new Path[3];

    String baseName = baseOutputPath.getFileName().toString();
    Path parentDir = baseOutputPath.getParent();

    // Generate thumbnail (200x200)
    Path thumbnailPath = parentDir.resolve("thumb_" + baseName);
    if (generateThumbnail(originalFile, thumbnailPath, ThumbnailSize.THUMBNAIL)) {
      thumbnailPaths[0] = thumbnailPath;
    }

    // Generate medium (800x800)
    Path mediumPath = parentDir.resolve("medium_" + baseName);
    if (generateThumbnail(originalFile, mediumPath, ThumbnailSize.MEDIUM)) {
      thumbnailPaths[1] = mediumPath;
    }

    // Generate large (1920x1920)
    Path largePath = parentDir.resolve("large_" + baseName);
    if (generateThumbnail(originalFile, largePath, ThumbnailSize.LARGE)) {
      thumbnailPaths[2] = largePath;
    }

    return thumbnailPaths;
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

      // Use ImageMagick's convert command
      // The AppImage version has latest libheif integration for modern HEIC files
      ProcessBuilder processBuilder =
          new ProcessBuilder(
              "convert",
              originalFile.toAbsolutePath().toString(),
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
   * Read EXIF orientation from image file
   *
   * @param file The image file
   * @return The orientation value (1-8), or 1 (normal) if not found or on error
   */
  private int getExifOrientation(Path file) {
    try {
      Metadata metadata = ImageMetadataReader.readMetadata(file.toFile());
      ExifIFD0Directory directory = metadata.getFirstDirectoryOfType(ExifIFD0Directory.class);
      if (directory != null && directory.containsTag(ExifIFD0Directory.TAG_ORIENTATION)) {
        return directory.getInt(ExifIFD0Directory.TAG_ORIENTATION);
      }
    } catch (ImageProcessingException | IOException | MetadataException e) {
      log.debug("Could not read EXIF orientation from {}: {}", file, e.getMessage());
    }
    return 1; // Default: no rotation needed
  }

  /**
   * Apply EXIF orientation transformation to image
   *
   * @param image The original image
   * @param orientation The EXIF orientation value (1-8)
   * @return The correctly oriented image
   */
  private BufferedImage applyOrientation(BufferedImage image, int orientation) {
    int width = image.getWidth();
    int height = image.getHeight();

    // For orientations 5-8, we need to swap width and height
    boolean swapDimensions = orientation >= 5 && orientation <= 8;
    int newWidth = swapDimensions ? height : width;
    int newHeight = swapDimensions ? width : height;

    BufferedImage rotatedImage = new BufferedImage(newWidth, newHeight, image.getType());
    Graphics2D g = rotatedImage.createGraphics();

    AffineTransform transform = new AffineTransform();

    switch (orientation) {
      case 1: // Normal - no transformation needed
        return image;

      case 2: // Flip horizontal
        transform.scale(-1, 1);
        transform.translate(-width, 0);
        break;

      case 3: // Rotate 180
        transform.translate(width, height);
        transform.rotate(Math.PI);
        break;

      case 4: // Flip vertical
        transform.scale(1, -1);
        transform.translate(0, -height);
        break;

      case 5: // Rotate 90 CW and flip horizontal
        transform.rotate(Math.PI / 2);
        transform.scale(-1, 1);
        break;

      case 6: // Rotate 90 CW
        transform.translate(height, 0);
        transform.rotate(Math.PI / 2);
        break;

      case 7: // Rotate 90 CCW and flip horizontal
        transform.scale(-1, 1);
        transform.translate(-height, 0);
        transform.translate(0, width);
        transform.rotate(3 * Math.PI / 2);
        break;

      case 8: // Rotate 90 CCW
        transform.translate(0, width);
        transform.rotate(3 * Math.PI / 2);
        break;

      default:
        return image;
    }

    g.drawImage(image, transform, null);
    g.dispose();

    return rotatedImage;
  }

  /** Get image format from file extension */
  private String getImageFormat(Path file) {
    String filename = file.getFileName().toString().toLowerCase();
    if (filename.endsWith(".png")) {
      return "png";
    } else if (filename.endsWith(".gif")) {
      return "gif";
    } else if (filename.endsWith(".webp")) {
      return "webp";
    }
    return "jpg"; // Default to JPEG
  }

  /**
   * Write image to file with configurable quality settings
   *
   * @param image The image to write
   * @param outputFile The output file
   * @param format The image format (jpg, png, etc.)
   * @param jpegQuality The JPEG quality (0.0 to 1.0)
   */
  private void writeImageWithQuality(
      BufferedImage image, File outputFile, String format, float jpegQuality) throws IOException {
    if (format.equals("jpg") || format.equals("jpeg")) {
      // For JPEG, use specified quality compression
      Iterator<ImageWriter> writers = ImageIO.getImageWritersByFormatName("jpeg");
      if (!writers.hasNext()) {
        throw new IOException("No JPEG writer found");
      }

      ImageWriter writer = writers.next();
      ImageWriteParam writeParam = writer.getDefaultWriteParam();

      if (writeParam.canWriteCompressed()) {
        writeParam.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
        writeParam.setCompressionQuality(jpegQuality);
      }

      try (ImageOutputStream ios = ImageIO.createImageOutputStream(outputFile)) {
        writer.setOutput(ios);
        writer.write(null, new IIOImage(image, null, null), writeParam);
        writer.dispose();
      }
    } else {
      // For other formats (PNG, GIF, WebP), use default ImageIO
      ImageIO.write(image, format, outputFile);
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
