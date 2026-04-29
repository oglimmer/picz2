/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.drew.imaging.ImageMetadataReader;
import com.drew.metadata.Metadata;
import com.drew.metadata.exif.ExifSubIFDDirectory;
import com.oglimmer.photoupload.config.AsyncConfig;
import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.exception.StorageException;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.storage.StoragePaths;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Comparator;
import java.util.Date;
import java.util.HexFormat;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@Service
@Profile(Profiles.WORKER)
@Slf4j
@RequiredArgsConstructor
public class FileProcessingService {

  private static final String PROCESSING_TMP = ".processing-tmp";

  private final FileStorageProperties properties;
  private final FileMetadataRepository metadataRepository;
  private final ThumbnailService thumbnailService;
  private final PlatformTransactionManager transactionManager;
  // Optional: present iff storage.s3.enabled=true. When present, originals are read from MinIO
  // into a per-job temp dir, derivatives are produced locally and PUT back to S3, and the temp
  // dir is wiped before the method returns.
  private final Optional<ObjectStorageService> objectStorage;

  /**
   * Legacy async entry point used when {@code jobs.dispatcher.enabled=false}. Delegates to the
   * synchronous {@link #processFile(Long)} on the file-processing executor.
   */
  @Async(AsyncConfig.FILE_PROCESSING_EXECUTOR)
  public void processFileAsync(Long fileMetadataId) {
    processFile(fileMetadataId);
  }

  public void processFile(Long fileMetadataId) {
    TransactionTemplate tx = new TransactionTemplate(transactionManager);
    FileMetadata metadata =
        tx.execute(
            status -> {
              FileMetadata found = metadataRepository.findById(fileMetadataId).orElse(null);
              if (found == null) {
                return null;
              }
              found.setProcessingStatus(ProcessingStatus.PROCESSING);
              found.setProcessingAttempts(
                  found.getProcessingAttempts() == null ? 1 : found.getProcessingAttempts() + 1);
              found.setProcessingError(null);
              return metadataRepository.save(found);
            });
    if (metadata == null) {
      log.warn("processFile: metadata id {} not found (deleted?)", fileMetadataId);
      return;
    }

    Path fileStorageLocation = Paths.get(properties.getUploadDir()).toAbsolutePath().normalize();
    String originalName = metadata.getOriginalName();
    String storedFilename = metadata.getStoredFilename();
    String mimeType = metadata.getMimeType();
    String extension = getFileExtension(storedFilename);
    boolean s3Backed =
        objectStorage.isPresent() && StoragePaths.isS3Key(metadata.getFilePath());

    Path workdir = null;
    Path currentFile;
    try {
      if (s3Backed) {
        // Per-job scratch dir on the PVC. Wiped in the finally block so we never accumulate.
        workdir =
            Files.createDirectories(
                fileStorageLocation.resolve(PROCESSING_TMP).resolve(String.valueOf(fileMetadataId)));
        currentFile = workdir.resolve(storedFilename);
        objectStorage.get().getToFile(metadata.getFilePath(), currentFile);
      } else {
        currentFile = fileStorageLocation.resolve(metadata.getFilePath()).normalize();
      }

      boolean isHeic =
          thumbnailService.isHeicFile(mimeType)
              || extension.equalsIgnoreCase("heic")
              || extension.equalsIgnoreCase("heif");

      // 1) HEIC → JPEG
      if (isHeic) {
        String baseName = getFilenameWithoutExtension(storedFilename);
        String convertedFilename = baseName + ".jpg";
        Path convertedLocation =
            (workdir != null ? workdir : fileStorageLocation).resolve(convertedFilename);

        if (thumbnailService.convertHeicToJpeg(currentFile, convertedLocation)) {
          log.info("Converted HEIC/HEIF to JPEG: {} -> {}", originalName, convertedFilename);

          if (s3Backed) {
            // Upload the JPEG as the new original, drop the old HEIC key.
            String newKey = StoragePaths.ORIGINALS_PREFIX + convertedFilename;
            objectStorage.get().putFile(newKey, convertedLocation, "image/jpeg");
            try {
              objectStorage.get().delete(metadata.getFilePath());
            } catch (Exception e) {
              // Non-fatal: leaves an orphan key but the row is correct. Log and continue.
              log.warn(
                  "Could not delete legacy HEIC key {} after conversion: {}",
                  metadata.getFilePath(),
                  e.toString());
            }
            metadata.setFilePath(newKey);
          } else {
            Files.deleteIfExists(currentFile);
            metadata.setFilePath(toRelativePath(fileStorageLocation, convertedLocation));
          }

          // Switch the in-memory state to the JPEG for derivative generation.
          currentFile = convertedLocation;
          storedFilename = convertedFilename;
          mimeType = "image/jpeg";
          metadata.setStoredFilename(convertedFilename);
          metadata.setMimeType(mimeType);
          // file_size used to drift here (recorded HEIC size, on-disk JPEG size). Update it now
          // so downstream consumers (gallery UI) see the right number.
          try {
            metadata.setFileSize(Files.size(convertedLocation));
          } catch (IOException sizeError) {
            log.warn("Could not stat converted JPEG {}: {}", convertedLocation, sizeError.toString());
          }
        } else {
          log.error(
              "Failed to convert HEIC/HEIF file {} to JPEG; leaving original in place",
              originalName);
        }
      }

      // 2) Thumbnails (images)
      if (thumbnailService.isImageFile(mimeType)) {
        Path[] thumbnails = thumbnailService.generateAllThumbnails(currentFile, currentFile);
        if (thumbnails[0] == null && thumbnails[1] == null && thumbnails[2] == null) {
          // All sizes failed — bail out so we don't mark the asset DONE with no derivatives.
          // The catch block below routes this through markFailed.
          throw new StorageException(
              "Thumbnail generation produced no output for " + originalName);
        }
        if (thumbnails[0] != null) {
          metadata.setThumbnailPath(
              storeDerivative(
                  fileStorageLocation,
                  thumbnails[0],
                  s3Backed ? StoragePaths.derivativeThumbnailKey(fileMetadataId) : null,
                  "image/jpeg"));
        }
        if (thumbnails[1] != null) {
          metadata.setMediumPath(
              storeDerivative(
                  fileStorageLocation,
                  thumbnails[1],
                  s3Backed ? StoragePaths.derivativeMediumKey(fileMetadataId) : null,
                  "image/jpeg"));
        }
        if (thumbnails[2] != null) {
          metadata.setLargePath(
              storeDerivative(
                  fileStorageLocation,
                  thumbnails[2],
                  s3Backed ? StoragePaths.derivativeLargeKey(fileMetadataId) : null,
                  "image/jpeg"));
        }
        if (thumbnails[0] != null) {
          log.info("📐 Generated thumbnails for: {}", originalName);
        }
      }

      // 3) Video transcode + video thumbnail
      if (thumbnailService.isVideoFile(mimeType)) {
        String baseNameWithoutExt = storedFilename.substring(0, storedFilename.lastIndexOf('.'));
        String transcodedFilename = "web_" + baseNameWithoutExt + ".mp4";
        Path transcodedLocation =
            (workdir != null ? workdir : fileStorageLocation).resolve(transcodedFilename);
        if (thumbnailService.transcodeVideo(currentFile, transcodedLocation)) {
          metadata.setTranscodedVideoPath(
              storeDerivative(
                  fileStorageLocation,
                  transcodedLocation,
                  s3Backed ? StoragePaths.derivativeTranscodedKey(fileMetadataId) : null,
                  "video/mp4"));
          log.info("🎬 Transcoded video for Safari/iOS: {}", originalName);
        } else {
          log.warn("⚠️ Video transcoding failed for: {}", originalName);
        }

        String thumbnailFilename = "thumb_" + baseNameWithoutExt + ".jpg";
        Path thumbnailLocation =
            (workdir != null ? workdir : fileStorageLocation).resolve(thumbnailFilename);
        if (thumbnailService.generateVideoThumbnail(currentFile, thumbnailLocation)) {
          metadata.setThumbnailPath(
              storeDerivative(
                  fileStorageLocation,
                  thumbnailLocation,
                  s3Backed ? StoragePaths.derivativeThumbnailKey(fileMetadataId) : null,
                  "image/jpeg"));
          log.info("📸 Generated video thumbnail: {}", originalName);
        } else {
          log.warn("⚠️ Video thumbnail generation failed for: {}", originalName);
        }
      }

      // 4) EXIF / video creation date
      Instant exifInstant = null;
      if (thumbnailService.isImageFile(mimeType)) {
        exifInstant = extractExifDateTimeOriginal(currentFile);
      } else if (thumbnailService.isVideoFile(mimeType)) {
        exifInstant = thumbnailService.extractVideoCreationDate(currentFile);
      }
      if (exifInstant != null) {
        metadata.setExifDateTimeOriginal(exifInstant);
      }

      // Persist all updates in one short transaction
      metadata.setProcessingStatus(ProcessingStatus.DONE);
      metadata.setProcessingCompletedAt(Instant.now());
      metadata.setProcessingError(null);
      final FileMetadata toSave = metadata;
      tx.executeWithoutResult(status -> metadataRepository.save(toSave));
      log.info("✅ Finished processing: {}", originalName);
    } catch (IOException e) {
      log.error("I/O error processing file {}", originalName, e);
      markFailed(tx, fileMetadataId, e);
    } catch (Exception e) {
      log.error("Unexpected error processing file {}", originalName, e);
      markFailed(tx, fileMetadataId, e);
    } finally {
      if (workdir != null) {
        deleteRecursive(workdir);
      }
    }
  }

  /**
   * Worker-side rotate (Phase 4.5, D17). Mirrors {@link #processFile(Long)}: lease the asset into
   * PROCESSING, do all heavy work locally on the worker pod, then commit the result in one short
   * TX. Bytes flow: download original from S3 → ImageMagick rotate-90-CCW → PUT same key →
   * regenerate all derivatives → PUT derivative keys (overwrite). Metadata flips: {@code rotation}
   * += 90 mod 360, swap {@code width}/{@code height}, regen {@code publicToken} (so the gallery
   * URL changes and the browser cache misses), update {@code fileSize}.
   *
   * <p>Pre-conditions enforced by the api pod before enqueue: image MIME type and S3-backed
   * {@code filePath}. We re-check defensively here so a stale or hand-crafted job row fails with a
   * clear error instead of corrupting state.
   */
  public void rotateAndReprocess(Long fileMetadataId) {
    TransactionTemplate tx = new TransactionTemplate(transactionManager);
    FileMetadata metadata =
        tx.execute(
            status -> {
              FileMetadata found = metadataRepository.findById(fileMetadataId).orElse(null);
              if (found == null) {
                return null;
              }
              found.setProcessingStatus(ProcessingStatus.PROCESSING);
              found.setProcessingAttempts(
                  found.getProcessingAttempts() == null ? 1 : found.getProcessingAttempts() + 1);
              found.setProcessingError(null);
              return metadataRepository.save(found);
            });
    if (metadata == null) {
      log.warn("rotateAndReprocess: metadata id {} not found (deleted?)", fileMetadataId);
      return;
    }

    String originalName = metadata.getOriginalName();
    String mimeType = metadata.getMimeType();
    Path fileStorageLocation = Paths.get(properties.getUploadDir()).toAbsolutePath().normalize();

    if (!thumbnailService.isImageFile(mimeType)) {
      // Should never happen — api side validates. Treat as a permanent failure.
      markFailed(
          tx,
          fileMetadataId,
          new StorageException("Cannot rotate non-image asset (mime=" + mimeType + ")"));
      return;
    }
    if (objectStorage.isEmpty() || !StoragePaths.isS3Key(metadata.getFilePath())) {
      markFailed(
          tx,
          fileMetadataId,
          new StorageException("Rotate requires the asset to be on object storage"));
      return;
    }

    Path workdir = null;
    try {
      workdir =
          Files.createDirectories(
              fileStorageLocation.resolve(PROCESSING_TMP).resolve(String.valueOf(fileMetadataId)));
      Path localOriginal = workdir.resolve(metadata.getStoredFilename());
      objectStorage.get().getToFile(metadata.getFilePath(), localOriginal);

      log.info("🔄 Rotating asset {} ({}) 90° left", fileMetadataId, originalName);
      boolean rotated = thumbnailService.rotateImageLeft(localOriginal);
      if (!rotated) {
        throw new StorageException("ImageMagick rotate failed for " + originalName);
      }

      // Push the rotated bytes back over the existing key. Same content type — we already
      // know it's an image at this point.
      objectStorage.get().putFile(metadata.getFilePath(), localOriginal, mimeType);
      try {
        metadata.setFileSize(Files.size(localOriginal));
      } catch (IOException sizeError) {
        log.warn(
            "Could not stat rotated original {}: {}", localOriginal, sizeError.toString());
      }

      // Regenerate thumbnails from the rotated original. Derivative keys are deterministic per
      // assetId, so the PUT overwrites the old derivative bytes — no separate delete needed.
      Path[] thumbnails = thumbnailService.generateAllThumbnails(localOriginal, localOriginal);
      if (thumbnails[0] != null) {
        metadata.setThumbnailPath(
            storeDerivative(
                fileStorageLocation,
                thumbnails[0],
                StoragePaths.derivativeThumbnailKey(fileMetadataId),
                "image/jpeg"));
      }
      if (thumbnails[1] != null) {
        metadata.setMediumPath(
            storeDerivative(
                fileStorageLocation,
                thumbnails[1],
                StoragePaths.derivativeMediumKey(fileMetadataId),
                "image/jpeg"));
      }
      if (thumbnails[2] != null) {
        metadata.setLargePath(
            storeDerivative(
                fileStorageLocation,
                thumbnails[2],
                StoragePaths.derivativeLargeKey(fileMetadataId),
                "image/jpeg"));
      }

      int currentRotation = metadata.getRotation() != null ? metadata.getRotation() : 0;
      metadata.setRotation((currentRotation + 90) % 360);
      if (metadata.getWidth() != null && metadata.getHeight() != null) {
        Integer oldWidth = metadata.getWidth();
        metadata.setWidth(metadata.getHeight());
        metadata.setHeight(oldWidth);
      }

      // Cache-bust: the gallery URL keys off publicToken, so every viewer's browser fetches the
      // new derivative bytes after the next gallery reload instead of serving a stale image.
      byte[] tokenBytes = new byte[24];
      new SecureRandom().nextBytes(tokenBytes);
      metadata.setPublicToken(HexFormat.of().formatHex(tokenBytes));

      metadata.setProcessingStatus(ProcessingStatus.DONE);
      metadata.setProcessingCompletedAt(Instant.now());
      metadata.setProcessingError(null);
      final FileMetadata toSave = metadata;
      tx.executeWithoutResult(status -> metadataRepository.save(toSave));
      log.info("✅ Rotated asset {} ({}) → {}°", fileMetadataId, originalName, toSave.getRotation());
    } catch (IOException e) {
      log.error("I/O error rotating file {}", originalName, e);
      markFailed(tx, fileMetadataId, e);
    } catch (Exception e) {
      log.error("Unexpected error rotating file {}", originalName, e);
      markFailed(tx, fileMetadataId, e);
    } finally {
      if (workdir != null) {
        deleteRecursive(workdir);
      }
    }
  }

  /**
   * Persist a freshly-generated derivative. When {@code s3Key} is non-null we PUT the local file
   * to S3 and return the key as the DB pointer; the local file is deleted (it lives in the temp
   * workdir which is wiped anyway, but we delete eagerly to keep peak disk small). Otherwise we
   * fall back to storing the derivative on the PVC and returning its relative path.
   */
  private String storeDerivative(
      Path fileStorageLocation, Path local, String s3Key, String contentType) throws IOException {
    if (s3Key != null) {
      objectStorage.get().putFile(s3Key, local, contentType);
      try {
        Files.deleteIfExists(local);
      } catch (IOException cleanup) {
        log.warn("Could not delete derivative temp file {}: {}", local, cleanup.toString());
      }
      return s3Key;
    }
    return toRelativePath(fileStorageLocation, local);
  }

  private void deleteRecursive(Path dir) {
    if (!Files.exists(dir)) {
      return;
    }
    try (var paths = Files.walk(dir)) {
      paths
          .sorted(Comparator.reverseOrder())
          .forEach(
              p -> {
                try {
                  Files.deleteIfExists(p);
                } catch (IOException ignored) {
                  // Best-effort; the next job will overwrite anyway.
                }
              });
    } catch (IOException e) {
      log.warn("Could not wipe processing workdir {}: {}", dir, e.toString());
    }
  }

  private void markFailed(TransactionTemplate tx, Long fileMetadataId, Throwable cause) {
    try {
      tx.executeWithoutResult(
          status -> {
            FileMetadata current = metadataRepository.findById(fileMetadataId).orElse(null);
            if (current == null) {
              return;
            }
            current.setProcessingStatus(ProcessingStatus.FAILED);
            current.setProcessingCompletedAt(Instant.now());
            current.setProcessingError(truncateError(cause));
            metadataRepository.save(current);
          });
    } catch (Exception persistenceError) {
      log.error(
          "Failed to record FAILED status for fileMetadataId {}: {}",
          fileMetadataId,
          persistenceError.getMessage(),
          persistenceError);
    }
  }

  private String truncateError(Throwable cause) {
    String msg = cause.getClass().getSimpleName() + ": " + cause.getMessage();
    return msg.length() > 4000 ? msg.substring(0, 4000) : msg;
  }

  private Instant extractExifDateTimeOriginal(Path imagePath) {
    try {
      Metadata metadata = ImageMetadataReader.readMetadata(imagePath.toFile());
      ExifSubIFDDirectory directory = metadata.getFirstDirectoryOfType(ExifSubIFDDirectory.class);
      if (directory != null && directory.containsTag(ExifSubIFDDirectory.TAG_DATETIME_ORIGINAL)) {
        Date date = directory.getDate(ExifSubIFDDirectory.TAG_DATETIME_ORIGINAL);
        if (date != null) {
          Instant exifInstant = date.toInstant();
          log.info("📷 Extracted EXIF DateTimeOriginal: {}", exifInstant);
          return exifInstant;
        }
      }
      return null;
    } catch (Exception e) {
      log.debug("Could not read EXIF from {}: {}", imagePath.getFileName(), e.getMessage());
      return null;
    }
  }

  private String toRelativePath(Path storageRoot, Path absolutePath) {
    return storageRoot.relativize(absolutePath.toAbsolutePath().normalize()).toString();
  }

  private String getFileExtension(String filename) {
    if (filename == null || !filename.contains(".")) return "";
    return filename.substring(filename.lastIndexOf(".") + 1);
  }

  private String getFilenameWithoutExtension(String filename) {
    if (filename == null || !filename.contains(".")) return filename;
    return filename.substring(0, filename.lastIndexOf("."));
  }
}
