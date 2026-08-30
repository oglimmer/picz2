/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.exception.StorageException;
import com.oglimmer.photoupload.model.CaptureDate;
import com.oglimmer.photoupload.model.GpsCoordinates;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.storage.BackendStorage;
import com.oglimmer.photoupload.storage.StoragePaths;
import com.oglimmer.photoupload.util.MimeTypePredicates;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
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
  private final CaptureDateExtractor captureDateExtractor;
  private final GpsExtractor gpsExtractor;
  private final PlatformTransactionManager transactionManager;
  // Optional: present iff storage.s3.enabled=true. When present, originals are read from MinIO
  // into a per-job temp dir, derivatives are produced locally and PUT back to S3, and the temp
  // dir is wiped before the method returns.
  private final Optional<ObjectStorageService> objectStorage;

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
    boolean s3Backed = objectStorage.isPresent() && StoragePaths.isS3Key(metadata.getFilePath());

    Path workdir = null;
    Path currentFile;
    try {
      if (s3Backed) {
        // Per-job scratch dir on the PVC. Wiped in the finally block so we never accumulate.
        workdir =
            Files.createDirectories(
                fileStorageLocation
                    .resolve(PROCESSING_TMP)
                    .resolve(String.valueOf(fileMetadataId)));
        currentFile = workdir.resolve(storedFilename);
        storageFor(metadata).getToFile(metadata.getFilePath(), currentFile);
      } else {
        currentFile = fileStorageLocation.resolve(metadata.getFilePath()).normalize();
      }

      boolean isHeic =
          MimeTypePredicates.isHeicFile(mimeType)
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
            storageFor(metadata).putFile(newKey, convertedLocation, "image/jpeg");
            try {
              storageFor(metadata).delete(metadata.getFilePath());
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
            log.warn(
                "Could not stat converted JPEG {}: {}", convertedLocation, sizeError.toString());
          }
        } else {
          log.error(
              "Failed to convert HEIC/HEIF file {} to JPEG; leaving original in place",
              originalName);
        }
      }

      // Everything below rebuilds this asset's derivative set, so the byte count starts over.
      resetDerivativeBytes(metadata);

      // 2) Thumbnails (images)
      if (MimeTypePredicates.isImageFile(mimeType)) {
        Path[] thumbnails = thumbnailService.generateAllThumbnails(currentFile, currentFile);
        if (thumbnails[0] == null && thumbnails[1] == null && thumbnails[2] == null) {
          // All sizes failed — bail out so we don't mark the asset DONE with no derivatives.
          // The catch block below routes this through markFailed.
          throw new StorageException("Thumbnail generation produced no output for " + originalName);
        }
        if (thumbnails[0] != null) {
          metadata.setThumbnailPath(
              storeDerivative(
                  metadata,
                  fileStorageLocation,
                  thumbnails[0],
                  s3Backed ? StoragePaths.derivativeThumbnailKey(fileMetadataId) : null,
                  "image/jpeg"));
        }
        if (thumbnails[1] != null) {
          metadata.setMediumPath(
              storeDerivative(
                  metadata,
                  fileStorageLocation,
                  thumbnails[1],
                  s3Backed ? StoragePaths.derivativeMediumKey(fileMetadataId) : null,
                  "image/jpeg"));
        }
        if (thumbnails[2] != null) {
          metadata.setLargePath(
              storeDerivative(
                  metadata,
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
      if (MimeTypePredicates.isVideoFile(mimeType)) {
        String baseNameWithoutExt = storedFilename.substring(0, storedFilename.lastIndexOf('.'));
        String transcodedFilename = "web_" + baseNameWithoutExt + ".mp4";
        Path transcodedLocation =
            (workdir != null ? workdir : fileStorageLocation).resolve(transcodedFilename);
        if (thumbnailService.transcodeVideo(currentFile, transcodedLocation)) {
          metadata.setTranscodedVideoPath(
              storeDerivative(
                  metadata,
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
                  metadata,
                  fileStorageLocation,
                  thumbnailLocation,
                  s3Backed ? StoragePaths.derivativeThumbnailKey(fileMetadataId) : null,
                  "image/jpeg"));
          log.info("📸 Generated video thumbnail: {}", originalName);
        } else {
          log.warn("⚠️ Video thumbnail generation failed for: {}", originalName);
        }
      }

      // 4) Capture date (image EXIF / video creation time), resolved to a true instant
      CaptureDate captureDate = captureDateExtractor.extract(currentFile, mimeType);
      metadata.setExifDateSource(captureDate.source());
      if (captureDate.isPresent()) {
        metadata.setExifDateTimeOriginal(captureDate.instant());
        metadata.setCaptureUtcOffsetSeconds(captureDate.offsetSeconds());
      }

      // 5) Capture location (EXIF GPS IFD / QuickTime location atom), for the map filter.
      // Read here and not later: this is the last point at which the original is guaranteed to be
      // on local disk, and retention eventually deletes it for good.
      GpsCoordinates gps = gpsExtractor.extract(currentFile, mimeType);
      metadata.setGpsSource(gps.source());
      metadata.setGpsLatitude(gps.latitude());
      metadata.setGpsLongitude(gps.longitude());

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
   * += 90 mod 360, swap {@code width}/{@code height}, regen {@code publicToken} (so the gallery URL
   * changes and the browser cache misses), update {@code fileSize}.
   *
   * <p>Pre-conditions enforced by the api pod before enqueue: image MIME type and S3-backed {@code
   * filePath}. We re-check defensively here so a stale or hand-crafted job row fails with a clear
   * error instead of corrupting state.
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

    if (!MimeTypePredicates.isImageFile(mimeType)) {
      // Should never happen — api side validates. Treat as a permanent failure.
      markFailed(
          tx,
          fileMetadataId,
          new StorageException("Cannot rotate non-image asset (mime=" + mimeType + ")"));
      return;
    }
    if (objectStorage.isEmpty()) {
      markFailed(
          tx,
          fileMetadataId,
          new StorageException("Rotate requires the asset to be on object storage"));
      return;
    }
    // Source key for the rotation: prefer the original, then fall back through the derivative
    // ladder for assets whose original has been purged by retention. Output is bounded by
    // LARGE=2400px anyway, so feeding `large` produces pixel-equivalent derivatives to feeding
    // the original — see the rationale in FileStorageService.rotateImageLeft.
    String sourceKey = pickRotationSource(metadata);
    if (sourceKey == null) {
      markFailed(
          tx,
          fileMetadataId,
          new StorageException("Rotate has no S3-backed source for asset " + fileMetadataId));
      return;
    }
    boolean originalRetained = sourceKey.equals(metadata.getFilePath());

    Path workdir = null;
    try {
      workdir =
          Files.createDirectories(
              fileStorageLocation.resolve(PROCESSING_TMP).resolve(String.valueOf(fileMetadataId)));
      Path localOriginal = workdir.resolve(metadata.getStoredFilename());
      storageFor(metadata).getToFile(sourceKey, localOriginal);

      log.info(
          "🔄 Rotating asset {} ({}) 90° left (source={})",
          fileMetadataId,
          originalName,
          originalRetained ? "original" : sourceKey);
      boolean rotated = thumbnailService.rotateImageLeft(localOriginal);
      if (!rotated) {
        throw new StorageException("ImageMagick rotate failed for " + originalName);
      }

      // Push the rotated bytes back to originals/ only when an original existed. If retention
      // already purged it, we deliberately don't recreate the key — that would resurrect bytes
      // the operator decided to drop, and would still only contain ≤2400px of pixels.
      if (originalRetained) {
        storageFor(metadata).putFile(metadata.getFilePath(), localOriginal, mimeType);
        try {
          metadata.setFileSize(Files.size(localOriginal));
        } catch (IOException sizeError) {
          log.warn("Could not stat rotated original {}: {}", localOriginal, sizeError.toString());
        }
      }

      // Regenerate thumbnails from the rotated original. Derivative keys are deterministic per
      // assetId, so the PUT overwrites the old derivative bytes — no separate delete needed, and
      // the byte count restarts for the same reason.
      resetDerivativeBytes(metadata);
      Path[] thumbnails = thumbnailService.generateAllThumbnails(localOriginal, localOriginal);
      if (thumbnails[0] != null) {
        metadata.setThumbnailPath(
            storeDerivative(
                metadata,
                fileStorageLocation,
                thumbnails[0],
                StoragePaths.derivativeThumbnailKey(fileMetadataId),
                "image/jpeg"));
      }
      if (thumbnails[1] != null) {
        metadata.setMediumPath(
            storeDerivative(
                metadata,
                fileStorageLocation,
                thumbnails[1],
                StoragePaths.derivativeMediumKey(fileMetadataId),
                "image/jpeg"));
      }
      if (thumbnails[2] != null) {
        metadata.setLargePath(
            storeDerivative(
                metadata,
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
   * Phase 4.5 follow-up — regenerate the three image derivatives (thumbnail / medium / large) for
   * an asset that's missing one or more, or whose derivatives the operator wants rebuilt (e.g.
   * after a vips upgrade). Same mechanics as {@link #rotateAndReprocess(Long)} minus the rotate
   * step: lease into PROCESSING, pick the best S3-backed source via {@link
   * #pickRotationSource(FileMetadata)} (works on retention-purged assets too), regenerate locally,
   * PUT each derivative to its deterministic key, refresh {@code publicToken} so viewer caches
   * miss, transition back to DONE.
   *
   * <p>Does <em>not</em> touch {@code rotation}, {@code width}/{@code height}, {@code fileSize}, or
   * the original-key bytes. The original is never written back even when present — we read, we
   * generate, that's it.
   */
  public void regenerateThumbnails(Long fileMetadataId) {
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
      log.warn("regenerateThumbnails: metadata id {} not found (deleted?)", fileMetadataId);
      return;
    }

    String originalName = metadata.getOriginalName();
    String mimeType = metadata.getMimeType();
    Path fileStorageLocation = Paths.get(properties.getUploadDir()).toAbsolutePath().normalize();

    if (!MimeTypePredicates.isImageFile(mimeType)) {
      markFailed(
          tx,
          fileMetadataId,
          new StorageException(
              "Cannot regenerate thumbnails for non-image asset (mime=" + mimeType + ")"));
      return;
    }
    if (objectStorage.isEmpty()) {
      markFailed(
          tx,
          fileMetadataId,
          new StorageException("Regen-thumbnails requires the asset to be on object storage"));
      return;
    }
    String sourceKey = pickRotationSource(metadata);
    if (sourceKey == null) {
      markFailed(
          tx,
          fileMetadataId,
          new StorageException(
              "Regen-thumbnails has no S3-backed source for asset " + fileMetadataId));
      return;
    }
    boolean fromOriginal = sourceKey.equals(metadata.getFilePath());

    Path workdir = null;
    try {
      workdir =
          Files.createDirectories(
              fileStorageLocation.resolve(PROCESSING_TMP).resolve(String.valueOf(fileMetadataId)));
      Path localSource = workdir.resolve(metadata.getStoredFilename());
      storageFor(metadata).getToFile(sourceKey, localSource);

      log.info(
          "🖼️  Regenerating derivatives for asset {} ({}, source={})",
          fileMetadataId,
          originalName,
          fromOriginal ? "original" : sourceKey);
      resetDerivativeBytes(metadata);
      Path[] thumbnails = thumbnailService.generateAllThumbnails(localSource, localSource);
      if (thumbnails[0] == null && thumbnails[1] == null && thumbnails[2] == null) {
        throw new StorageException("Thumbnail regeneration produced no output for " + originalName);
      }
      if (thumbnails[0] != null) {
        metadata.setThumbnailPath(
            storeDerivative(
                metadata,
                fileStorageLocation,
                thumbnails[0],
                StoragePaths.derivativeThumbnailKey(fileMetadataId),
                "image/jpeg"));
      }
      if (thumbnails[1] != null) {
        metadata.setMediumPath(
            storeDerivative(
                metadata,
                fileStorageLocation,
                thumbnails[1],
                StoragePaths.derivativeMediumKey(fileMetadataId),
                "image/jpeg"));
      }
      if (thumbnails[2] != null) {
        metadata.setLargePath(
            storeDerivative(
                metadata,
                fileStorageLocation,
                thumbnails[2],
                StoragePaths.derivativeLargeKey(fileMetadataId),
                "image/jpeg"));
      }

      // Cache-bust like rotate does — viewer browsers fetch the new derivative bytes after the
      // next gallery reload instead of holding the stale ones.
      byte[] tokenBytes = new byte[24];
      new SecureRandom().nextBytes(tokenBytes);
      metadata.setPublicToken(HexFormat.of().formatHex(tokenBytes));

      metadata.setProcessingStatus(ProcessingStatus.DONE);
      metadata.setProcessingCompletedAt(Instant.now());
      metadata.setProcessingError(null);
      final FileMetadata toSave = metadata;
      tx.executeWithoutResult(status -> metadataRepository.save(toSave));
      log.info("✅ Regenerated derivatives for asset {} ({})", fileMetadataId, originalName);
    } catch (IOException e) {
      log.error("I/O error regenerating thumbnails for {}", originalName, e);
      markFailed(tx, fileMetadataId, e);
    } catch (Exception e) {
      log.error("Unexpected error regenerating thumbnails for {}", originalName, e);
      markFailed(tx, fileMetadataId, e);
    } finally {
      if (workdir != null) {
        deleteRecursive(workdir);
      }
    }
  }

  /**
   * Re-reads the capture date of an already-processed asset and nothing else.
   *
   * <p>Exists because every row written before the timezone-aware extractor holds a photo's local
   * wall clock relabelled UTC, which sorts photos and videos on two different clocks. Deliberately
   * does not touch derivatives — re-running {@code PROCESS} would redo transcodes that already
   * succeeded, and on a Pi that is hours of work for a metadata fix.
   *
   * <p>Reads the original only. Retention-purged rows ({@code file_path} null) can't be re-read at
   * all — no derivative carries the source EXIF — so the api-side query excludes them and this
   * method fails loudly if one slips through.
   */
  public void reextractCaptureDate(Long fileMetadataId) {
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
      log.warn("reextractCaptureDate: metadata id {} not found (deleted?)", fileMetadataId);
      return;
    }

    String originalName = metadata.getOriginalName();
    String mimeType = metadata.getMimeType();
    Path fileStorageLocation = Paths.get(properties.getUploadDir()).toAbsolutePath().normalize();
    if (metadata.getFilePath() == null) {
      markFailed(
          tx,
          fileMetadataId,
          new StorageException(
              "Cannot re-extract capture date for asset "
                  + fileMetadataId
                  + ": original is gone (retention-purged)"));
      return;
    }
    boolean s3Backed = objectStorage.isPresent() && StoragePaths.isS3Key(metadata.getFilePath());

    Path workdir = null;
    try {
      Path currentFile;
      if (s3Backed) {
        workdir =
            Files.createDirectories(
                fileStorageLocation
                    .resolve(PROCESSING_TMP)
                    .resolve(String.valueOf(fileMetadataId)));
        currentFile = workdir.resolve(metadata.getStoredFilename());
        storageFor(metadata).getToFile(metadata.getFilePath(), currentFile);
      } else {
        currentFile = fileStorageLocation.resolve(metadata.getFilePath()).normalize();
      }

      CaptureDate captureDate = captureDateExtractor.extract(currentFile, mimeType);
      Instant previous = metadata.getExifDateTimeOriginal();
      metadata.setExifDateSource(captureDate.source());
      if (captureDate.isPresent()) {
        metadata.setExifDateTimeOriginal(captureDate.instant());
        metadata.setCaptureUtcOffsetSeconds(captureDate.offsetSeconds());
      } else if (previous != null && metadata.getCaptureUtcOffsetSeconds() == null) {
        // Kept-but-unreadable rows were written by the old extractor, which relabelled the wall
        // clock as UTC. Offset 0 therefore recovers that wall clock exactly, and stamping it keeps
        // the row out of the next sweep instead of re-reading it forever.
        metadata.setCaptureUtcOffsetSeconds(0);
      }
      // A NONE result keeps whatever the old extractor stored: it is at worst offset by a UTC
      // offset, which still beats dropping the only capture date we have. The recorded source
      // makes such rows findable.
      metadata.setProcessingStatus(ProcessingStatus.DONE);
      metadata.setProcessingCompletedAt(Instant.now());
      metadata.setProcessingError(null);
      final FileMetadata toSave = metadata;
      tx.executeWithoutResult(status -> metadataRepository.save(toSave));
      log.info(
          "🕒 Capture date for asset {} ({}): {} → {} (source={})",
          fileMetadataId,
          originalName,
          previous,
          metadata.getExifDateTimeOriginal(),
          captureDate.source());
    } catch (IOException e) {
      log.error("I/O error re-extracting capture date for {}", originalName, e);
      markFailed(tx, fileMetadataId, e);
    } catch (Exception e) {
      log.error("Unexpected error re-extracting capture date for {}", originalName, e);
      markFailed(tx, fileMetadataId, e);
    } finally {
      if (workdir != null) {
        deleteRecursive(workdir);
      }
    }
  }

  /**
   * Reads the capture location of an already-processed asset and nothing else.
   *
   * <p>Backfill for every row that predates the map feature. Same shape and the same reasoning as
   * {@link #reextractCaptureDate}: metadata only, no derivative is touched, because re-running
   * {@code PROCESS} would redo transcodes that already succeeded.
   *
   * <p>Reads the original only. Coordinates live in the EXIF GPS IFD or the QuickTime location atom
   * and no derivative carries either, so retention-purged rows ({@code file_path} null) can never
   * be backfilled — the api-side query excludes them and this method fails loudly if one slips
   * through.
   */
  public void reextractGps(Long fileMetadataId) {
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
      log.warn("reextractGps: metadata id {} not found (deleted?)", fileMetadataId);
      return;
    }

    String originalName = metadata.getOriginalName();
    String mimeType = metadata.getMimeType();
    Path fileStorageLocation = Paths.get(properties.getUploadDir()).toAbsolutePath().normalize();
    if (metadata.getFilePath() == null) {
      markFailed(
          tx,
          fileMetadataId,
          new StorageException(
              "Cannot extract GPS for asset "
                  + fileMetadataId
                  + ": original is gone (retention-purged)"));
      return;
    }
    boolean s3Backed = objectStorage.isPresent() && StoragePaths.isS3Key(metadata.getFilePath());

    Path workdir = null;
    try {
      Path currentFile;
      if (s3Backed) {
        workdir =
            Files.createDirectories(
                fileStorageLocation
                    .resolve(PROCESSING_TMP)
                    .resolve(String.valueOf(fileMetadataId)));
        currentFile = workdir.resolve(metadata.getStoredFilename());
        storageFor(metadata).getToFile(metadata.getFilePath(), currentFile);
      } else {
        currentFile = fileStorageLocation.resolve(metadata.getFilePath()).normalize();
      }

      GpsCoordinates gps = gpsExtractor.extract(currentFile, mimeType);
      // A NONE result is written, not skipped: it is what takes the row out of the sweep's
      // eligible set, so repeat runs converge instead of re-reading every location-less asset.
      metadata.setGpsSource(gps.source());
      metadata.setGpsLatitude(gps.latitude());
      metadata.setGpsLongitude(gps.longitude());
      metadata.setProcessingStatus(ProcessingStatus.DONE);
      metadata.setProcessingCompletedAt(Instant.now());
      metadata.setProcessingError(null);
      final FileMetadata toSave = metadata;
      tx.executeWithoutResult(status -> metadataRepository.save(toSave));
      log.info(
          "🌍 GPS for asset {} ({}): {}/{} (source={})",
          fileMetadataId,
          originalName,
          gps.latitude(),
          gps.longitude(),
          gps.source());
    } catch (IOException e) {
      log.error("I/O error extracting GPS for {}", originalName, e);
      markFailed(tx, fileMetadataId, e);
    } catch (Exception e) {
      log.error("Unexpected error extracting GPS for {}", originalName, e);
      markFailed(tx, fileMetadataId, e);
    } finally {
      if (workdir != null) {
        deleteRecursive(workdir);
      }
    }
  }

  /**
   * Persist a freshly-generated derivative. When {@code s3Key} is non-null we PUT the local file to
   * S3 and return the key as the DB pointer; the local file is deleted (it lives in the temp
   * workdir which is wiped anyway, but we delete eagerly to keep peak disk small). Otherwise we
   * fall back to storing the derivative on the PVC and returning its relative path.
   */
  /**
   * The album's storage backend for this asset. Resolved per call rather than once per job: the
   * lookup is memoised in {@link ObjectStorageService}, and holding a handle across a long
   * transcode would pin credentials that the owner may have corrected in the meantime.
   */
  private BackendStorage storageFor(FileMetadata metadata) {
    return objectStorage
        .orElseThrow(() -> new StorageException("Object storage is not enabled"))
        .forFile(metadata);
  }

  private String storeDerivative(
      FileMetadata metadata, Path fileStorageLocation, Path local, String s3Key, String contentType)
      throws IOException {
    if (s3Key != null) {
      // Measured before the PUT, while the file is still on disk — afterwards it is deleted, and
      // asking S3 for the size would be a second round trip per derivative.
      long size = Files.size(local);
      storageFor(metadata).putFile(s3Key, local, contentType);
      metadata.setDerivativeBytes(nullToZero(metadata.getDerivativeBytes()) + size);
      try {
        Files.deleteIfExists(local);
      } catch (IOException cleanup) {
        log.warn("Could not delete derivative temp file {}: {}", local, cleanup.toString());
      }
      return s3Key;
    }
    return toRelativePath(fileStorageLocation, local);
  }

  /**
   * Start counting this asset's derivative bytes from scratch.
   *
   * <p>Called by every job that rebuilds the whole set (first pass, rotate, regenerate). Without it
   * the running total from {@link #storeDerivative} would accumulate across reprocessings, and an
   * asset rotated four times would meter as if it held four copies of its own thumbnails.
   */
  private void resetDerivativeBytes(FileMetadata metadata) {
    metadata.setDerivativeBytes(0L);
  }

  private static long nullToZero(Long value) {
    return value != null ? value : 0L;
  }

  /**
   * Pick the best S3-backed source for a rotation. Original first; if retention has nulled {@code
   * file_path} we step down through the derivative ladder. Returns null if no S3-backed source
   * exists at all (api-side guard should have rejected before enqueue, but defensive).
   */
  private String pickRotationSource(FileMetadata metadata) {
    if (StoragePaths.isS3Key(metadata.getFilePath())) {
      return metadata.getFilePath();
    }
    if (StoragePaths.isS3Key(metadata.getLargePath())) {
      return metadata.getLargePath();
    }
    if (StoragePaths.isS3Key(metadata.getMediumPath())) {
      return metadata.getMediumPath();
    }
    if (StoragePaths.isS3Key(metadata.getThumbnailPath())) {
      return metadata.getThumbnailPath();
    }
    return null;
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
