/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.drew.imaging.ImageMetadataReader;
import com.drew.metadata.Metadata;
import com.drew.metadata.exif.ExifSubIFDDirectory;
import com.oglimmer.photoupload.config.AsyncConfig;
import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import java.util.Date;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@Service
@Slf4j
@RequiredArgsConstructor
public class FileProcessingService {

  private final FileStorageProperties properties;
  private final FileMetadataRepository metadataRepository;
  private final ThumbnailService thumbnailService;
  private final PlatformTransactionManager transactionManager;

  @Async(AsyncConfig.FILE_PROCESSING_EXECUTOR)
  public void processFile(Long fileMetadataId) {
    TransactionTemplate tx = new TransactionTemplate(transactionManager);
    FileMetadata metadata = tx.execute(status -> metadataRepository.findById(fileMetadataId).orElse(null));
    if (metadata == null) {
      log.warn("processFile: metadata id {} not found (deleted?)", fileMetadataId);
      return;
    }

    Path fileStorageLocation = Paths.get(properties.getUploadDir()).toAbsolutePath().normalize();
    Path currentFile = fileStorageLocation.resolve(metadata.getFilePath()).normalize();
    String originalName = metadata.getOriginalName();
    String storedFilename = metadata.getStoredFilename();
    String mimeType = metadata.getMimeType();
    String extension = getFileExtension(storedFilename);

    boolean isHeic =
        thumbnailService.isHeicFile(mimeType)
            || extension.equalsIgnoreCase("heic")
            || extension.equalsIgnoreCase("heif");

    try {
      // 1) HEIC → JPEG
      if (isHeic) {
        String baseName = getFilenameWithoutExtension(storedFilename);
        String convertedFilename = baseName + ".jpg";
        Path convertedLocation = fileStorageLocation.resolve(convertedFilename);

        if (thumbnailService.convertHeicToJpeg(currentFile, convertedLocation)) {
          log.info("Converted HEIC/HEIF to JPEG: {} -> {}", originalName, convertedFilename);
          Files.deleteIfExists(currentFile);
          currentFile = convertedLocation;
          storedFilename = convertedFilename;
          mimeType = "image/jpeg";
          metadata.setStoredFilename(convertedFilename);
          metadata.setMimeType(mimeType);
          metadata.setFilePath(toRelativePath(fileStorageLocation, convertedLocation));
        } else {
          log.error(
              "Failed to convert HEIC/HEIF file {} to JPEG; leaving original in place", originalName);
          // Keep the original HEIC — serve-layer will fall back to it.
        }
      }

      // 2) Thumbnails (images)
      if (thumbnailService.isImageFile(mimeType)) {
        Path[] thumbnails = thumbnailService.generateAllThumbnails(currentFile, currentFile);
        if (thumbnails[0] != null) {
          metadata.setThumbnailPath(toRelativePath(fileStorageLocation, thumbnails[0]));
        }
        if (thumbnails[1] != null) {
          metadata.setMediumPath(toRelativePath(fileStorageLocation, thumbnails[1]));
        }
        if (thumbnails[2] != null) {
          metadata.setLargePath(toRelativePath(fileStorageLocation, thumbnails[2]));
        }
        if (thumbnails[0] != null) {
          log.info("📐 Generated thumbnails for: {}", originalName);
        }
      }

      // 3) Video transcode + video thumbnail
      if (thumbnailService.isVideoFile(mimeType)) {
        String baseNameWithoutExt = storedFilename.substring(0, storedFilename.lastIndexOf('.'));
        String transcodedFilename = "web_" + baseNameWithoutExt + ".mp4";
        Path transcodedLocation = fileStorageLocation.resolve(transcodedFilename);
        if (thumbnailService.transcodeVideo(currentFile, transcodedLocation)) {
          metadata.setTranscodedVideoPath(toRelativePath(fileStorageLocation, transcodedLocation));
          log.info("🎬 Transcoded video for Safari/iOS: {}", originalName);
        } else {
          log.warn("⚠️ Video transcoding failed for: {}", originalName);
        }

        String thumbnailFilename = "thumb_" + baseNameWithoutExt + ".jpg";
        Path thumbnailLocation = fileStorageLocation.resolve(thumbnailFilename);
        if (thumbnailService.generateVideoThumbnail(currentFile, thumbnailLocation)) {
          metadata.setThumbnailPath(toRelativePath(fileStorageLocation, thumbnailLocation));
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
      final FileMetadata toSave = metadata;
      tx.executeWithoutResult(status -> metadataRepository.save(toSave));
      log.info("✅ Finished processing: {}", originalName);
    } catch (IOException e) {
      log.error("I/O error processing file {}", originalName, e);
    } catch (Exception e) {
      log.error("Unexpected error processing file {}", originalName, e);
    }
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
