/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.config.FileStorageProperties.Thumbnailer;
import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.model.CaptureDate;
import com.oglimmer.photoupload.model.GpsCoordinates;
import java.io.IOException;
import java.nio.file.Path;
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
   * A JPEG copy of {@code originalFile} bounded to the LARGE size (2400 px), at {@code
   * destination}. What the enhance preview (D82) is computed on: big enough to judge, a fraction of
   * the original's pixels to process. Routes like {@link #generateAllThumbnails(Path, Path)}; on
   * the legacy magick path the two smaller sizes are produced and thrown away.
   */
  public boolean generateLargeCopy(Path originalFile, Path destination) {
    if (properties.getThumbnailer() == Thumbnailer.VIPS) {
      return vipsThumbnailService.generateLarge(originalFile, destination);
    }
    Path[] all = generateAllThumbnailsMagick(originalFile, destination);
    if (all[2] == null) {
      return false;
    }
    try {
      java.nio.file.Files.move(
          all[2], destination, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
      if (all[0] != null) java.nio.file.Files.deleteIfExists(all[0]);
      if (all[1] != null) java.nio.file.Files.deleteIfExists(all[1]);
      return true;
    } catch (IOException e) {
      log.error("Could not place large copy at {}: {}", destination, e.getMessage());
      return false;
    }
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

  public CaptureDate extractVideoCreationDate(Path videoFile) {
    return ffmpegService.extractVideoCreationDate(videoFile);
  }

  public GpsCoordinates extractVideoLocation(Path videoFile) {
    return ffmpegService.extractVideoLocation(videoFile);
  }

  /**
   * Strength of the shadow lift / highlight pull ("Brilliance"), 0–100. The local-tone mask is
   * mixed toward neutral grey by {@code 100 - this} percent before the soft-light blend, so 100
   * is the full textbook effect and 0 is none. 40 lifts a 20 % shadow to about 26 %.
   */
  static final int BRILLIANCE_PERCENT = 40;

  /**
   * Local-contrast gain ("Definition"): the output is {@code (1 + k) * image - k * blurred}. Apple's
   * slider at its auto position is subtle; 0.25 adds texture without visible halos.
   */
  static final double DEFINITION_GAIN = 0.25;

  /**
   * One-tap auto-enhance in place via ImageMagick (D81) — the server-side cousin of the phone's
   * "magic wand". Six tonal steps, no geometric ones, so pixel dimensions, orientation and EXIF
   * come through unchanged. In the order they run:
   *
   * <ol>
   *   <li>{@code -channel RGB -contrast-stretch 0.2%x0.2% +channel} — each channel's black and
   *       white point is set on its own, which fixes a colour cast (a crude grey-world white
   *       balance) and recovers flat contrast in one move. 0.2 % clipping per end is enough to
   *       ignore stray pixels without eating real shadow or highlight detail.
   *   <li>{@code -gamma} toward mid-grey, from the image's own mean luminance, clamped by {@link
   *       #enhanceGammaFor(double)} so a night shot stays a night shot and a snow scene stays
   *       bright.
   *   <li>{@code -sigmoidal-contrast 2.5x50%} — a gentle S-curve around the midtones.
   *   <li>Brilliance (shadows up, highlights down, locally): a blurred, inverted luminance copy is
   *       soft-light blended over the image. Where the photo is dark the mask is light and lifts;
   *       where it is bright the mask is dark and pulls back. Mixed toward grey by {@link
   *       #BRILLIANCE_PERCENT} so it stays a nudge, not an HDR look.
   *   <li>Definition (local contrast): {@code (1 + k) * image - k * blurred}, a wide-radius
   *       unsharp mask by another name, {@link #DEFINITION_GAIN} as {@code k}. Not edge
   *       sharpening — the derivatives are resampled afterwards and would lose that anyway.
   *   <li>{@code -modulate 100,112,100} — 12 % more saturation, hue and brightness untouched.
   * </ol>
   *
   * <p>Both masks are built on a 10 % {@code -scale} of the image and resized back to the exact
   * pixel size, because a Gaussian blur with a radius of 2 % of the width is what makes these two
   * steps expensive, and a Pi would spend most of a minute on it at full resolution — the same
   * lesson as {@link #measureMeanLuminance(Path)}. On the small copy the blur is free and the mean
   * is preserved; the cost that remains is two resizes and two composites at full size. The size
   * is passed as literal numbers from {@link #measureDimensions(Path)}: the legacy {@code convert}
   * entry point does not expand percent escapes in geometry arguments (asset 6986, 2026-09-06:
   * "invalid argument for option '-resize': %[dims]!"), and {@code convert} is what every other
   * ImageMagick call here uses.
   *
   * <p>Only the first frame ({@code [0]}) is read, so an animated GIF comes out as one still. Three
   * invocations: header-only {@code identify} for the size, a small decode for the mean, then the
   * pass itself. The output keeps the input format (unknown
   * {@code .tmp} suffix → ImageMagick writes with the reader's format), exactly like {@link
   * #rotateImageLeft(Path)}.
   */
  public boolean enhanceImage(Path imageFile) {
    int[] dims = measureDimensions(imageFile);
    Double mean = dims == null ? null : measureMeanLuminance(imageFile);
    if (mean == null) {
      return false;
    }
    String fullSize = dims[0] + "x" + dims[1] + "!";
    String gamma = String.format(java.util.Locale.ROOT, "%.3f", enhanceGammaFor(mean));
    String maskGreyMix = Integer.toString(100 - BRILLIANCE_PERCENT);
    String definitionArgs =
        String.format(java.util.Locale.ROOT, "0,%.3f,%.3f,0", -DEFINITION_GAIN, 1 + DEFINITION_GAIN);
    Path tempFile = imageFile.getParent().resolve(imageFile.getFileName().toString() + ".tmp");
    List<String> cmd =
        List.of(
            "convert",
            "-quiet",
            imageFile.toAbsolutePath().toString() + "[0]",
            // 1. black/white point per channel
            "-channel", "RGB", "-contrast-stretch", "0.2%x0.2%", "+channel",
            // 2. exposure
            "-gamma", gamma,
            // 3. global midtone contrast
            "-sigmoidal-contrast", "2.5x50%",
            // 4. brilliance: inverted, blurred luminance, soft-light blended
            "(", "+clone", "-scale", "10%", "-colorspace", "Gray", "-negate", "-blur", "0x8",
            "-fill", "gray50", "-colorize", maskGreyMix, "-colorspace", "sRGB",
            "-resize", fullSize, ")",
            "-compose", "SoftLight", "-composite",
            // 5. definition: (1+k)*image - k*blurred(image)
            "(", "+clone", "-scale", "10%", "-blur", "0x4", "-resize", fullSize, ")",
            "-define", "compose:args=" + definitionArgs,
            "-compose", "Mathematics", "-composite", "-clamp",
            // 6. saturation
            "-modulate", "100,112,100",
            tempFile.toAbsolutePath().toString());
    try {
      log.info("✨ Enhancing: {} (mean luminance {}, gamma {})", imageFile.getFileName(), mean, gamma);
      long started = System.nanoTime();
      ProcessRunner.Result r = ProcessRunner.run(cmd, 120, TimeUnit.SECONDS);
      if (r.success() && tempFile.toFile().exists()) {
        java.nio.file.Files.delete(imageFile);
        java.nio.file.Files.move(tempFile, imageFile);
        log.info(
            "✅ Enhanced image: {} in {} ms",
            imageFile.getFileName(),
            (System.nanoTime() - started) / 1_000_000);
        return true;
      }
      log.error(
          "Image enhance failed (exit {}, timedOut={}) for {}: {}",
          r.exitCode(),
          r.timedOut(),
          imageFile.getFileName(),
          r.output());
      java.nio.file.Files.deleteIfExists(tempFile);
      return false;
    } catch (IOException e) {
      log.error("IO error during image enhance for {}: {}", imageFile, e.getMessage(), e);
      try {
        java.nio.file.Files.deleteIfExists(tempFile);
      } catch (IOException ignored) {
        // best-effort cleanup
      }
      return false;
    }
  }

  /**
   * Mean luminance of the first frame in 0..1, or null when ImageMagick could not say.
   *
   * <p>Measured on a shrunken copy, not the full photo: the first production run of this on a
   * 12-megapixel original took more than 60 s and was killed (asset 6974, 2026-09-05), while the
   * rotate of the same bytes fits comfortably — the {@code %[fx:mean]} statistics pass over a full
   * HDRI pixel cache is what is slow on the Pi. A box-filter {@code -scale} preserves the mean, and
   * {@code jpeg:size} lets libjpeg decode at 1/8 scale in the first place, so this now costs a
   * fraction of a second regardless of the original's size.
   *
   * <p>{@code ProcessRunner} merges stderr into stdout, so a reader warning (IMv7's "convert is
   * deprecated", a PNG's "incorrect sRGB profile") can precede the number; the last token that
   * parses is the answer.
   */
  private Double measureMeanLuminance(Path imageFile) {
    List<String> cmd =
        List.of(
            "convert",
            "-quiet",
            "-define",
            "jpeg:size=512x512",
            imageFile.toAbsolutePath().toString() + "[0]",
            "-scale",
            "256x256>",
            "-colorspace",
            "Gray",
            "-format",
            "%[fx:mean]",
            "info:");
    try {
      long started = System.nanoTime();
      ProcessRunner.Result r = ProcessRunner.run(cmd, 120, TimeUnit.SECONDS);
      log.info(
          "Measured luminance of {} in {} ms",
          imageFile.getFileName(),
          (System.nanoTime() - started) / 1_000_000);
      Double mean = r.success() ? lastNumber(r.output()) : null;
      if (mean == null) {
        log.error(
            "Could not measure luminance (exit {}, timedOut={}) for {}: {}",
            r.exitCode(),
            r.timedOut(),
            imageFile.getFileName(),
            r.output());
      }
      return mean;
    } catch (IOException e) {
      log.error("IO error measuring luminance for {}: {}", imageFile, e.getMessage(), e);
      return null;
    }
  }

  /**
   * Pixel width and height of the first frame, or null when ImageMagick could not say. {@code
   * -ping} reads the header only, so this costs milliseconds whatever the file size. Same
   * stderr-in-stdout caveat as {@link #lastNumber(String)}: the last two integers are the answer.
   */
  private int[] measureDimensions(Path imageFile) {
    List<String> cmd =
        List.of(
            "identify",
            "-quiet",
            "-ping",
            "-format",
            "%w %h",
            imageFile.toAbsolutePath().toString() + "[0]");
    try {
      ProcessRunner.Result r = ProcessRunner.run(cmd, 30, TimeUnit.SECONDS);
      int[] dims = r.success() ? lastTwoIntegers(r.output()) : null;
      if (dims == null) {
        log.error(
            "Could not measure size (exit {}, timedOut={}) for {}: {}",
            r.exitCode(),
            r.timedOut(),
            imageFile.getFileName(),
            r.output());
      }
      return dims;
    } catch (IOException e) {
      log.error("IO error measuring size for {}: {}", imageFile, e.getMessage(), e);
      return null;
    }
  }

  static int[] lastTwoIntegers(String output) {
    String[] tokens = output.trim().split("\\s+");
    for (int i = tokens.length - 1; i >= 1; i--) {
      try {
        int height = Integer.parseInt(tokens[i]);
        int width = Integer.parseInt(tokens[i - 1]);
        if (width > 0 && height > 0) {
          return new int[] {width, height};
        }
      } catch (NumberFormatException ignored) {
        // keep looking
      }
    }
    return null;
  }

  static Double lastNumber(String output) {
    String[] tokens = output.trim().split("\\s+");
    for (int i = tokens.length - 1; i >= 0; i--) {
      try {
        return Double.parseDouble(tokens[i]);
      } catch (NumberFormatException ignored) {
        // keep looking
      }
    }
    return null;
  }

  /**
   * The {@code -gamma} value that moves an image's mean luminance toward mid-grey — softened to
   * half the correction and clamped to {@code [0.85, 1.3]}, so the result reads as "a bit better
   * exposed" and never as a different photo. A mean of exactly 0 or 1 (or NaN) yields 1.0: there
   * is nothing to correct toward.
   */
  static double enhanceGammaFor(double meanLuminance) {
    if (!(meanLuminance > 0.0) || !(meanLuminance < 1.0)) {
      return 1.0;
    }
    // ImageMagick's -gamma g computes out = in^(1/g); the g that lands the mean on 0.5 is
    // ln(mean) / ln(0.5): > 1 brightens a dark image, < 1 darkens a bright one.
    double full = Math.log(meanLuminance) / Math.log(0.5);
    double softened = 1.0 + (full - 1.0) * 0.5;
    return Math.max(0.85, Math.min(1.3, softened));
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
