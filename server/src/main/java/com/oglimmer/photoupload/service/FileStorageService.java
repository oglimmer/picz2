/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.drew.imaging.ImageMetadataReader;
import com.drew.metadata.Metadata;
import com.drew.metadata.exif.ExifSubIFDDirectory;
import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ImageTag;
import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.DuplicateResourceException;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.exception.StorageException;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.mapper.FileInfoMapper;
import com.oglimmer.photoupload.model.FileInfo;
import com.oglimmer.photoupload.model.FileServeInfo;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.ImageTagRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import jakarta.annotation.PostConstruct;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.time.Instant;
import java.util.Arrays;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.Semaphore;
import java.util.stream.Collectors;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.BatchPreparedStatementSetter;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

@Service
@Slf4j
public class FileStorageService {

  public static final String NO_TAG = "no_tag";

  private static final long ONE_KB = 1024L;
  private static final long ONE_MB = ONE_KB * ONE_KB; // 1_048_576
  private static final long ONE_GB = ONE_KB * ONE_MB; // 1_073_741_824
  private static final long ONE_TB = ONE_KB * ONE_GB; // 1_099_511_627_776
  private static final long ONE_PB = ONE_KB * ONE_TB; // 1_125_899_906_842_624
  private static final long ONE_EB = ONE_KB * ONE_PB; // 1_152_921_504_606_846_976
  private static final List<String> ALLOWED_IMAGE_TYPES =
      Arrays.asList(
          "image/jpeg",
          "image/jpg",
          "image/png",
          "image/gif",
          "image/heic",
          "image/heif",
          "image/webp",
          "image/tiff",
          "image/bmp");
  private static final List<String> ALLOWED_VIDEO_TYPES =
      Arrays.asList(
          "video/mp4",
          "video/quicktime",
          "video/x-msvideo",
          "video/x-ms-wmv",
          "video/x-flv",
          "video/x-matroska",
          "video/webm",
          "video/x-m4v");
  private static final List<String> ALLOWED_EXTENSIONS =
      Arrays.asList(
          "jpeg", "jpg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp", "mp4", "mov", "avi",
          "wmv", "flv", "mkv", "webm", "m4v");
  private final Path fileStorageLocation;
  private final FileStorageProperties properties;
  private final FileMetadataRepository metadataRepository;
  private final TagRepository tagRepository;
  private final ImageTagRepository imageTagRepository;
  private final ThumbnailService thumbnailService;
  private final JdbcTemplate jdbcTemplate;
  private final AlbumRepository albumRepository;
  private final FileInfoMapper fileInfoMapper;
  private final UserContext userContext;

  // Semaphore to limit concurrent file processing operations (image conversion, thumbnails, etc.)
  private Semaphore processingPermits;

  public FileStorageService(
      FileStorageProperties properties,
      FileMetadataRepository metadataRepository,
      TagRepository tagRepository,
      ImageTagRepository imageTagRepository,
      ThumbnailService thumbnailService,
      JdbcTemplate jdbcTemplate,
      AlbumRepository albumRepository,
      FileInfoMapper fileInfoMapper,
      UserContext userContext) {
    this.properties = properties;
    this.metadataRepository = metadataRepository;
    this.tagRepository = tagRepository;
    this.imageTagRepository = imageTagRepository;
    this.thumbnailService = thumbnailService;
    this.jdbcTemplate = jdbcTemplate;
    this.fileInfoMapper = fileInfoMapper;
    this.albumRepository = albumRepository;
    this.userContext = userContext;
    this.fileStorageLocation = Paths.get(properties.getUploadDir()).toAbsolutePath().normalize();
  }

  @PostConstruct
  public void init() {
    try {
      Files.createDirectories(this.fileStorageLocation);
      log.info("Upload directory created at: {}", this.fileStorageLocation);

      // Initialize semaphore with configured max concurrent processing
      processingPermits = new Semaphore(properties.getMaxConcurrentProcessing());
      log.info(
          "File processing concurrency limit set to: {}", properties.getMaxConcurrentProcessing());
    } catch (Exception ex) {
      throw new StorageException("Could not create upload directory!", ex);
    }
  }

  /**
   * Convert an absolute path to a relative path for storage in the database. The path is relative
   * to the upload directory.
   */
  private String toRelativePath(Path absolutePath) {
    return this.fileStorageLocation
        .relativize(absolutePath.toAbsolutePath().normalize())
        .toString();
  }

  /**
   * Convert a relative path from the database to an absolute path. The path is resolved relative to
   * the upload directory.
   */
  private Path toAbsolutePath(String relativePath) {
    if (relativePath == null) {
      return null;
    }
    return this.fileStorageLocation.resolve(relativePath).toAbsolutePath().normalize();
  }

  /**
   * Public method to resolve a file path from database to absolute path. Used by controllers to
   * serve files.
   */
  public Path resolveFilePath(String relativePath) {
    return toAbsolutePath(relativePath);
  }

  @Transactional
  public FileInfo storeFile(MultipartFile file, Long albumId, String contentId) throws IOException {
    User currentUser = userContext.getCurrentUser();

    // If albumId is not provided, use the user's default album
    final Long effectiveAlbumId;
    if (albumId == null) {
      effectiveAlbumId = currentUser.getDefaultAlbumId();
      if (effectiveAlbumId == null) {
        // User has paused sync by clearing target album
        // This can happen if:
        // 1. User set "Pause Sync" on web/another device
        // 2. iOS app hasn't detected the pause yet via background sync
        // Throw clear error so uploads fail gracefully
        log.warn(
            "Upload rejected - sync is paused (no target album configured) for user: {} (file: {})",
            currentUser.getEmail(),
            file.getOriginalFilename());
        throw new ValidationException(
            "Sync is paused. Please select a target album in your settings to resume uploads.");
      }
    } else {
      effectiveAlbumId = albumId;
    }
    // Validate file
    validateFile(file);

    // Check for duplicate by contentId first (if provided)
    // ContentId is a stable identifier from the source (e.g., iOS PHAsset.localIdentifier)
    // This is more reliable than checksum for detecting duplicates, especially for HEIC files
    if (contentId != null && !contentId.isBlank()) {
      List<FileMetadata> existingByContentId =
          metadataRepository.findByContentIdAndUserId(contentId, currentUser.getId());
      if (!existingByContentId.isEmpty()) {
        FileMetadata existing = existingByContentId.get(0);
        if (existingByContentId.size() > 1) {
          log.warn(
              "⚠️ Found {} duplicate files with contentId {}, using first one",
              existingByContentId.size(),
              contentId);
        }
        log.info(
            "⚠️ Duplicate file detected by contentId {}: {} (matches existing file: {} in album {}). Upload skipped.",
            contentId,
            file.getOriginalFilename(),
            existing.getOriginalName(),
            existing.getAlbum() != null ? existing.getAlbum().getName() : "unknown");
        return convertToFileInfo(existing);
      }
    }

    // Calculate checksum early to detect duplicates before storing
    byte[] fileBytes = file.getBytes();
    String checksum = calculateChecksum(fileBytes);

    // Check for duplicate in the same album
    Optional<FileMetadata> existingFile =
        metadataRepository.findByChecksumAndAlbumIdAndUserId(
            checksum, effectiveAlbumId, currentUser.getId());
    if (existingFile.isPresent()) {
      FileMetadata existing = existingFile.get();
      log.info(
          "⚠️ Duplicate file detected in album {}: {} (matches existing file: {}). Upload skipped.",
          effectiveAlbumId,
          file.getOriginalFilename(),
          existing.getOriginalName());
      return convertToFileInfo(existing);
    }

    // Check for duplicate in any other album
    List<FileMetadata> existingInOtherAlbum = metadataRepository.findByChecksum(checksum);
    if (!existingInOtherAlbum.isEmpty()) {
      FileMetadata existing = existingInOtherAlbum.get(0);
      if (existingInOtherAlbum.size() > 1) {
        log.warn(
            "⚠️ Found {} duplicate files with checksum {}, using first one",
            existingInOtherAlbum.size(),
            checksum);
      }
      log.info(
          "⚠️ Duplicate file detected: {} (matches existing file: {} in album {}). Upload skipped.",
          file.getOriginalFilename(),
          existing.getOriginalName(),
          existing.getAlbum() != null ? existing.getAlbum().getName() : "unknown");
      return convertToFileInfo(existing);
    }

    // Generate unique filename
    String originalFilename = file.getOriginalFilename();
    String extension = getFileExtension(originalFilename);
    String nameWithoutExtension = getFilenameWithoutExtension(originalFilename);
    String uniqueSuffix =
        System.currentTimeMillis() + "-" + UUID.randomUUID().toString().substring(0, 9);
    String newFilename = nameWithoutExtension + "-" + uniqueSuffix + "." + extension;

    // Store file
    Path targetLocation = this.fileStorageLocation.resolve(newFilename);
    Files.write(targetLocation, fileBytes);

    // Convert HEIC/HEIF to JPEG if needed
    String contentType = file.getContentType();
    Path convertedLocation = null;
    boolean isHeic =
        thumbnailService.isHeicFile(contentType)
            || extension.equalsIgnoreCase("heic")
            || extension.equalsIgnoreCase("heif");

    log.info(
        "File {} - ContentType: {}, Extension: {}, IsHEIC: {}",
        originalFilename,
        contentType,
        extension,
        isHeic);

    if (isHeic) {
      String convertedFilename = nameWithoutExtension + "-" + uniqueSuffix + ".jpg";
      convertedLocation = this.fileStorageLocation.resolve(convertedFilename);

      if (thumbnailService.convertHeicToJpeg(targetLocation, convertedLocation)) {
        log.info("Converted HEIC/HEIF to JPEG: {} -> {}", originalFilename, convertedFilename);

        // Delete original HEIC/HEIF file
        Files.deleteIfExists(targetLocation);

        // Update target location and filename to point to converted JPEG
        targetLocation = convertedLocation;
        newFilename = convertedFilename;
        extension = "jpg";
        contentType = "image/jpeg";
      } else {
        // HEIC conversion failed - reject the upload
        // Delete both the original HEIC file and any failed conversion attempt
        Files.deleteIfExists(targetLocation);
        Files.deleteIfExists(convertedLocation);

        String errorMsg =
            String.format(
                "Failed to convert HEIC/HEIF file '%s' to JPEG. "
                    + "This file may use an unsupported HEIC format or have corrupted metadata. "
                    + "Please try converting the file to JPEG on your device before uploading.",
                originalFilename);
        log.error(errorMsg);
        throw new StorageException(errorMsg);
      }
    }

    log.info("✅ File uploaded: {} ({})", originalFilename, formatBytes(file.getSize()));

    // Generate thumbnails for images (not videos)
    String thumbnailPath = null;
    String mediumPath = null;
    String largePath = null;
    String transcodedVideoPath = null;

    // Acquire permit before CPU-intensive processing
    boolean permitAcquired = false;
    try {
      log.debug(
          "Waiting for processing permit (available: {})", processingPermits.availablePermits());
      processingPermits.acquire();
      permitAcquired = true;
      log.debug("Processing permit acquired (available: {})", processingPermits.availablePermits());

      if (thumbnailService.isImageFile(contentType)) {
        Path[] thumbnails = thumbnailService.generateAllThumbnails(targetLocation, targetLocation);
        if (thumbnails[0] != null) {
          thumbnailPath = toRelativePath(thumbnails[0]);
        }
        if (thumbnails[1] != null) {
          mediumPath = toRelativePath(thumbnails[1]);
        }
        if (thumbnails[2] != null) {
          largePath = toRelativePath(thumbnails[2]);
        }

        if (thumbnailPath != null) {
          log.info("📐 Generated thumbnails for: {}", originalFilename);
        }
      }

      // Transcode videos for Safari/iOS compatibility
      if (thumbnailService.isVideoFile(contentType)) {
        String baseNameWithoutExt = newFilename.substring(0, newFilename.lastIndexOf('.'));

        // Generate transcoded video (web-compatible MP4)
        String transcodedFilename = "web_" + baseNameWithoutExt + ".mp4";
        Path transcodedLocation = this.fileStorageLocation.resolve(transcodedFilename);

        if (thumbnailService.transcodeVideo(targetLocation, transcodedLocation)) {
          transcodedVideoPath = toRelativePath(transcodedLocation);
          log.info("🎬 Transcoded video for Safari/iOS: {}", originalFilename);
        } else {
          log.warn("⚠️ Video transcoding failed for: {}, will serve original", originalFilename);
        }

        // Generate video thumbnail (image from first frame)
        String thumbnailFilename = "thumb_" + baseNameWithoutExt + ".jpg";
        Path thumbnailLocation = this.fileStorageLocation.resolve(thumbnailFilename);

        if (thumbnailService.generateVideoThumbnail(targetLocation, thumbnailLocation)) {
          thumbnailPath = toRelativePath(thumbnailLocation);
          log.info("📸 Generated video thumbnail: {}", originalFilename);
        } else {
          log.warn("⚠️ Video thumbnail generation failed for: {}", originalFilename);
        }
      }
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      log.error("Processing interrupted for: {}", originalFilename, e);
      throw new StorageException("File processing was interrupted", e);
    } finally {
      if (permitAcquired) {
        processingPermits.release();
        log.debug(
            "Processing permit released (available: {})", processingPermits.availablePermits());
      }
    }

    // Save metadata to database
    FileMetadata metadata = new FileMetadata();
    metadata.setOriginalName(originalFilename);
    metadata.setStoredFilename(newFilename);
    metadata.setFileSize(file.getSize());
    metadata.setMimeType(
        contentType); // Use updated contentType (may have changed from HEIC to JPEG)
    metadata.setFilePath(toRelativePath(targetLocation));
    metadata.setUploadedAt(Instant.now());
    metadata.setChecksum(checksum);
    metadata.setContentId(
        contentId); // Store contentId from source (e.g., iOS PHAsset.localIdentifier)
    metadata.setThumbnailPath(thumbnailPath);
    metadata.setMediumPath(mediumPath);
    metadata.setLargePath(largePath);
    metadata.setTranscodedVideoPath(transcodedVideoPath);

    // Extract EXIF DateTimeOriginal if this is an image file
    if (thumbnailService.isImageFile(contentType)) {
      Instant exifDateTime = extractExifDateTimeOriginal(targetLocation);
      metadata.setExifDateTimeOriginal(exifDateTime);
    }

    // Set album (required) - verify ownership
    Album album =
        albumRepository
            .findByUserAndId(currentUser, effectiveAlbumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", effectiveAlbumId));
    metadata.setAlbum(album);

    // Set display order to be at the end of the album
    Integer maxOrder =
        metadataRepository.findMaxDisplayOrderByAlbumIdAndUserId(
            effectiveAlbumId, currentUser.getId());
    metadata.setDisplayOrder(maxOrder != null ? maxOrder + 1 : 0);

    metadata = metadataRepository.save(metadata);

    // Add "no_tag" to all newly uploaded files
    ensureNoTagExists(currentUser);
    addNoTagToFile(metadata, currentUser);

    // Return file info
    return convertToFileInfo(metadata);
  }

  public List<FileInfo> listFiles() {
    return metadataRepository.findAllByOrderByDisplayOrderAsc().stream()
        .map(this::convertToFileInfo)
        .collect(Collectors.toList());
  }

  public List<FileInfo> listFilesByTag(String tagName) {
    User currentUser = userContext.getCurrentUser();
    Tag tag =
        tagRepository
            .findByUserAndName(currentUser, tagName)
            .orElseThrow(() -> new ResourceNotFoundException("Tag", "name", tagName));

    return imageTagRepository.findAll().stream()
        .filter(imageTag -> imageTag.getTag().getId().equals(tag.getId()))
        .map(imageTag -> convertToFileInfo(imageTag.getFileMetadata()))
        .collect(Collectors.toList());
  }

  public List<FileInfo> listFilesByAlbum(Long albumId) {
    User currentUser = userContext.getCurrentUser();
    // Return files in specified album (albumId required)
    // Using optimized query with JOIN FETCH to avoid N+1 query problem
    return metadataRepository
        .findByAlbumIdAndUserIdWithTagsOrderByDisplayOrderAsc(albumId, currentUser.getId())
        .stream()
        .map(this::convertToFileInfoOptimized)
        .collect(Collectors.toList());
  }

  public List<FileInfo> listFilesByAlbumByShareToken(String shareToken) {
    // Return files in specified album (albumId required)
    // Using optimized query with JOIN FETCH to avoid N+1 query problem
    return metadataRepository
        .findByAlbumShareTokenWithTagsOrderByDisplayOrderAsc(shareToken)
        .stream()
        .map(this::convertToFileInfoOptimized)
        .collect(Collectors.toList());
  }

  public FileInfo getFileInfoByPublicToken(String publicToken) {
    FileMetadata metadata =
        metadataRepository
            .findByPublicToken(publicToken)
            .orElseThrow(
                () ->
                    new ResourceNotFoundException(
                        "File not found with public token: " + publicToken));
    return convertToFileInfoOptimized(metadata);
  }

  public Path getFile(String filename) {
    return this.fileStorageLocation.resolve(filename).normalize();
  }

  private void validateFile(MultipartFile file) {
    if (file.isEmpty()) {
      throw new ValidationException("Cannot upload empty file");
    }

    String contentType = file.getContentType();
    String originalFilename = file.getOriginalFilename();
    String extension = getFileExtension(originalFilename).toLowerCase();

    boolean isValidType =
        ALLOWED_IMAGE_TYPES.contains(contentType) || ALLOWED_VIDEO_TYPES.contains(contentType);

    boolean isValidExtension = ALLOWED_EXTENSIONS.contains(extension);

    if (!isValidType && !isValidExtension) {
      throw new ValidationException("Only image and video files are allowed!");
    }

    if (file.getSize() > properties.getMaxFileSize()) {
      throw new ValidationException(
          "File size exceeds maximum limit of " + formatBytes(properties.getMaxFileSize()));
    }
  }

  private String getFileExtension(String filename) {
    if (filename == null || !filename.contains(".")) {
      return "";
    }
    return filename.substring(filename.lastIndexOf(".") + 1);
  }

  private String getFilenameWithoutExtension(String filename) {
    if (filename == null || !filename.contains(".")) {
      return filename;
    }
    return filename.substring(0, filename.lastIndexOf("."));
  }

  public String byteCountToDisplaySize(long size) {
    final boolean negative = size < 0;
    long n = negative ? -size : size;

    final String out;
    if (n < ONE_KB) {
      out = n + " bytes";
    } else if (n < ONE_MB) {
      out = (n / ONE_KB) + " KB";
    } else if (n < ONE_GB) {
      out = (n / ONE_MB) + " MB";
    } else if (n < ONE_TB) {
      out = (n / ONE_GB) + " GB";
    } else if (n < ONE_PB) {
      out = (n / ONE_TB) + " TB";
    } else if (n < ONE_EB) {
      out = (n / ONE_PB) + " PB";
    } else {
      // For extremely large values >= EB (still fits in signed long)
      out = (n / ONE_EB) + " EB";
    }

    return negative ? "-" + out : out;
  }

  private String formatBytes(long bytes) {
    return byteCountToDisplaySize(bytes);
  }

  private String calculateChecksum(byte[] fileBytes) {
    try {
      MessageDigest digest = MessageDigest.getInstance("SHA-256");
      byte[] hash = digest.digest(fileBytes);
      StringBuilder hexString = new StringBuilder();
      for (byte b : hash) {
        String hex = Integer.toHexString(0xff & b);
        if (hex.length() == 1) {
          hexString.append('0');
        }
        hexString.append(hex);
      }
      return hexString.toString();
    } catch (Exception e) {
      log.error("Error calculating checksum", e);
      return null;
    }
  }

  /**
   * Extract EXIF DateTimeOriginal from an image file. Returns null if EXIF data is not available or
   * if DateTimeOriginal is not set.
   */
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
      log.debug("No EXIF DateTimeOriginal found for: {}", imagePath.getFileName());
      return null;
    } catch (Exception e) {
      log.debug("Could not read EXIF data from {}: {}", imagePath.getFileName(), e.getMessage());
      return null;
    }
  }

  @Transactional
  public void deleteFile(Long fileId) {
    FileMetadata metadata =
        metadataRepository
            .findById(fileId)
            .orElseThrow(() -> new ResourceNotFoundException("File", "id", fileId));

    try {
      // Delete physical file
      Path filePath = toAbsolutePath(metadata.getFilePath());
      Files.deleteIfExists(filePath);
      log.info("Deleted file: {}", metadata.getStoredFilename());

      // Delete thumbnails
      thumbnailService.deleteThumbnails(
          toAbsolutePath(metadata.getThumbnailPath()),
          toAbsolutePath(metadata.getMediumPath()),
          toAbsolutePath(metadata.getLargePath()));

      // Delete transcoded video if exists
      thumbnailService.deleteTranscodedVideo(toAbsolutePath(metadata.getTranscodedVideoPath()));

      // Delete metadata (cascade will delete image_tags)
      metadataRepository.delete(metadata);
    } catch (IOException e) {
      log.error("Error deleting file", e);
      throw new StorageException("Could not delete file: " + e.getMessage(), e);
    }
  }

  @Transactional
  public List<String> addTagToFile(Long fileId, String tagName) {
    User currentUser = userContext.getCurrentUser();
    FileMetadata metadata =
        metadataRepository
            .findByIdAndUserId(fileId, currentUser.getId())
            .orElseThrow(() -> new ResourceNotFoundException("File", "id", fileId));

    Tag tag =
        tagRepository
            .findByUserAndName(currentUser, tagName)
            .orElseThrow(() -> new ResourceNotFoundException("Tag", "name", tagName));

    // Check if tag already exists for this file
    if (imageTagRepository.findByFileMetadataIdAndTagId(fileId, tag.getId()).isPresent()) {
      throw new DuplicateResourceException("File already has this tag");
    }

    // Count current tags (excluding no_tag)
    List<ImageTag> existingTags = imageTagRepository.findByFileMetadataId(fileId);
    long otherTagsCount =
        existingTags.stream().filter(it -> !NO_TAG.equals(it.getTag().getName())).count();

    ImageTag imageTag = new ImageTag();
    imageTag.setFileMetadata(metadata);
    imageTag.setTag(tag);
    imageTagRepository.save(imageTag);

    log.info("Added tag '{}' to file: {}", tagName, metadata.getStoredFilename());

    // If this is the first real tag being added, remove no_tag
    if (otherTagsCount == 0 && !NO_TAG.equals(tagName)) {
      removeNoTagFromFile(fileId, currentUser);
    }

    // Return updated tags list
    return imageTagRepository.findByFileMetadataId(fileId).stream()
        .map(it -> it.getTag().getName())
        .collect(Collectors.toList());
  }

  @Transactional
  public List<String> removeTagFromFile(Long fileId, String tagName) {
    User currentUser = userContext.getCurrentUser();
    FileMetadata metadata =
        metadataRepository
            .findByIdAndUserId(fileId, currentUser.getId())
            .orElseThrow(() -> new ResourceNotFoundException("File", "id", fileId));

    Tag tag =
        tagRepository
            .findByUserAndName(currentUser, tagName)
            .orElseThrow(() -> new ResourceNotFoundException("Tag", "name", tagName));

    ImageTag imageTag =
        imageTagRepository
            .findByFileMetadataIdAndTagId(fileId, tag.getId())
            .orElseThrow(() -> new ResourceNotFoundException("File does not have this tag"));

    imageTagRepository.delete(imageTag);
    log.info("Removed tag '{}' from file: {}", tagName, metadata.getStoredFilename());

    // Check if this was the last real tag (excluding no_tag)
    List<ImageTag> remainingTags = imageTagRepository.findByFileMetadataId(fileId);
    long otherTagsCount =
        remainingTags.stream().filter(it -> !NO_TAG.equals(it.getTag().getName())).count();

    // If no other tags remain, restore no_tag
    if (otherTagsCount == 0) {
      ensureNoTagExists(currentUser);
      addNoTagToFile(metadata, currentUser);
    }

    // Return updated tags list
    return imageTagRepository.findByFileMetadataId(fileId).stream()
        .map(it -> it.getTag().getName())
        .collect(Collectors.toList());
  }

  @Transactional
  public void reorderFiles(List<Long> fileIds) {
    // Validate all file IDs exist with a single query
    List<Long> existingIds = metadataRepository.findExistingIds(fileIds);
    if (existingIds.size() != fileIds.size()) {
      throw new ResourceNotFoundException("One or more file IDs not found");
    }

    // Batch update all display orders in a single database round trip
    String sql = "UPDATE file_metadata SET display_order = ? WHERE id = ?";
    jdbcTemplate.batchUpdate(
        sql,
        new BatchPreparedStatementSetter() {
          @Override
          public void setValues(PreparedStatement ps, int i) throws SQLException {
            ps.setInt(1, i); // display_order (new position)
            ps.setLong(2, fileIds.get(i)); // file id
          }

          @Override
          public int getBatchSize() {
            return fileIds.size();
          }
        });

    log.info("Reordered {} files", fileIds.size());
  }

  /**
   * Generate thumbnails for all existing images that don't have them. This is useful for batch
   * processing existing files that were uploaded before thumbnail feature was added.
   *
   * @param overwrite If true, regenerate all thumbnails even if they already exist
   */
  @Transactional
  public Map<String, Object> generateMissingThumbnails(boolean overwrite) {
    int processed = 0;
    int succeeded = 0;
    int failed = 0;
    int skipped = 0;

    List<FileMetadata> allFiles = metadataRepository.findAll();

    for (FileMetadata metadata : allFiles) {
      processed++;

      // Skip if thumbnails already exist and we're not overwriting
      if (!overwrite
          && metadata.getThumbnailPath() != null
          && metadata.getMediumPath() != null
          && metadata.getLargePath() != null) {
        skipped++;
        continue;
      }

      // Skip if not an image
      if (!thumbnailService.isImageFile(metadata.getMimeType())) {
        skipped++;
        continue;
      }

      try {
        // Get the original file path
        Path originalFile = toAbsolutePath(metadata.getFilePath());

        if (!originalFile.toFile().exists()) {
          log.warn("File not found, skipping: {}", metadata.getStoredFilename());
          failed++;
          continue;
        }

        // If overwriting, delete existing thumbnails first
        if (overwrite) {
          thumbnailService.deleteThumbnails(
              toAbsolutePath(metadata.getThumbnailPath()),
              toAbsolutePath(metadata.getMediumPath()),
              toAbsolutePath(metadata.getLargePath()));
        }

        // Generate thumbnails
        Path[] thumbnails = thumbnailService.generateAllThumbnails(originalFile, originalFile);

        boolean anyGenerated = false;
        if (thumbnails[0] != null) {
          metadata.setThumbnailPath(toRelativePath(thumbnails[0]));
          anyGenerated = true;
        }
        if (thumbnails[1] != null) {
          metadata.setMediumPath(toRelativePath(thumbnails[1]));
          anyGenerated = true;
        }
        if (thumbnails[2] != null) {
          metadata.setLargePath(toRelativePath(thumbnails[2]));
          anyGenerated = true;
        }

        if (anyGenerated) {
          metadataRepository.save(metadata);
          succeeded++;
          log.info(
              "Generated thumbnails for: {} ({}/{})",
              metadata.getOriginalName(),
              succeeded,
              allFiles.size());
        } else {
          failed++;
          log.warn("Failed to generate thumbnails for: {}", metadata.getOriginalName());
        }

      } catch (Exception e) {
        failed++;
        log.error(
            "Error generating thumbnails for {}: {}", metadata.getOriginalName(), e.getMessage());
      }
    }

    Map<String, Object> result = new HashMap<>();
    result.put("processed", processed);
    result.put("succeeded", succeeded);
    result.put("failed", failed);
    result.put("skipped", skipped);

    log.info(
        "Thumbnail generation complete: {} processed, {} succeeded, {} failed, {} skipped",
        processed,
        succeeded,
        failed,
        skipped);

    return result;
  }

  /**
   * Scan for transcoded videos on disk and update database paths This is useful for batch
   * processing existing videos that were transcoded manually
   *
   * @return Statistics about the update process
   */
  @Transactional
  public Map<String, Object> updateTranscodedVideoPaths() {
    int processed = 0;
    int found = 0;
    int updated = 0;
    int skipped = 0;

    List<FileMetadata> allFiles = metadataRepository.findAll();

    for (FileMetadata metadata : allFiles) {
      // Skip if not a video
      if (metadata.getMimeType() == null || !metadata.getMimeType().startsWith("video/")) {
        continue;
      }

      processed++;

      // Skip if transcoded path already set
      if (metadata.getTranscodedVideoPath() != null) {
        skipped++;
        log.debug("Skipping {} - transcoded path already set", metadata.getStoredFilename());
        continue;
      }

      try {
        // Generate expected transcoded filename
        String storedFilename = metadata.getStoredFilename();
        String baseNameWithoutExt = storedFilename.substring(0, storedFilename.lastIndexOf('.'));
        String transcodedFilename = "web_" + baseNameWithoutExt + ".mp4";
        Path transcodedLocation = this.fileStorageLocation.resolve(transcodedFilename);

        // Check if transcoded file exists on disk
        if (transcodedLocation.toFile().exists()) {
          // Update database with transcoded path
          metadata.setTranscodedVideoPath(toRelativePath(transcodedLocation));
          metadataRepository.save(metadata);
          found++;
          updated++;
          log.info(
              "Found and linked transcoded video: {} -> {}",
              metadata.getOriginalName(),
              transcodedFilename);
        } else {
          log.debug(
              "No transcoded video found for: {} (expected: {})",
              metadata.getStoredFilename(),
              transcodedFilename);
        }

      } catch (Exception e) {
        log.error(
            "Error updating transcoded path for {}: {}",
            metadata.getOriginalName(),
            e.getMessage());
      }
    }

    Map<String, Object> result = new HashMap<>();
    result.put("processedVideos", processed);
    result.put("foundTranscoded", found);
    result.put("updatedDatabase", updated);
    result.put("skippedExisting", skipped);

    log.info(
        "Transcoded video scan complete: {} videos processed, {} transcoded found, {} database records updated, {} skipped",
        processed,
        found,
        updated,
        skipped);

    return result;
  }

  /**
   * Scan for video thumbnails on disk and update database paths This is useful for batch processing
   * existing videos that had thumbnails generated manually
   *
   * @return Statistics about the update process
   */
  @Transactional
  public Map<String, Object> updateVideoThumbnailPaths() {
    int processed = 0;
    int found = 0;
    int updated = 0;
    int skipped = 0;

    List<FileMetadata> allFiles = metadataRepository.findAll();

    for (FileMetadata metadata : allFiles) {
      // Skip if not a video
      if (metadata.getMimeType() == null || !metadata.getMimeType().startsWith("video/")) {
        continue;
      }

      processed++;

      // Skip if thumbnail path already set
      if (metadata.getThumbnailPath() != null) {
        skipped++;
        log.debug("Skipping {} - thumbnail path already set", metadata.getStoredFilename());
        continue;
      }

      try {
        // Generate expected thumbnail filename
        String storedFilename = metadata.getStoredFilename();
        String baseNameWithoutExt = storedFilename.substring(0, storedFilename.lastIndexOf('.'));
        String thumbnailFilename = "thumb_" + baseNameWithoutExt + ".jpg";
        Path thumbnailLocation = this.fileStorageLocation.resolve(thumbnailFilename);

        // Check if thumbnail file exists on disk
        if (thumbnailLocation.toFile().exists()) {
          // Update database with thumbnail path
          metadata.setThumbnailPath(toRelativePath(thumbnailLocation));
          metadataRepository.save(metadata);
          found++;
          updated++;
          log.info(
              "Found and linked video thumbnail: {} -> {}",
              metadata.getOriginalName(),
              thumbnailFilename);
        } else {
          log.debug(
              "No video thumbnail found for: {} (expected: {})",
              metadata.getStoredFilename(),
              thumbnailFilename);
        }

      } catch (Exception e) {
        log.error(
            "Error updating video thumbnail path for {}: {}",
            metadata.getOriginalName(),
            e.getMessage());
      }
    }

    Map<String, Object> result = new HashMap<>();
    result.put("processedVideos", processed);
    result.put("foundThumbnails", found);
    result.put("updatedDatabase", updated);
    result.put("skippedExisting", skipped);

    log.info(
        "Video thumbnail scan complete: {} videos processed, {} thumbnails found, {} database records updated, {} skipped",
        processed,
        found,
        updated,
        skipped);

    return result;
  }

  /**
   * Get file serve information by public token (for serving files)
   *
   * @param publicToken The public token
   * @param size The size variant to serve (original, thumb, medium, large)
   * @return File serve information DTO
   */
  public FileServeInfo getFileServeInfoByPublicToken(String publicToken, String size) {
    FileMetadata metadata =
        metadataRepository
            .findByPublicToken(publicToken)
            .orElseThrow(() -> new ResourceNotFoundException("File not found"));

    // Determine which file to serve based on size parameter and file type
    String filePath = metadata.getFilePath(); // Default to original
    String mimeType = metadata.getMimeType(); // Default to original MIME type

    boolean isVideo = metadata.getMimeType() != null && metadata.getMimeType().startsWith("video/");
    boolean isOriginalRequested = "original".equalsIgnoreCase(size);
    boolean isServingThumbnail = false;
    boolean isServingTranscodedVideo = false;

    // Handle size parameter for both images and videos
    if (size != null) {
      switch (size.toLowerCase()) {
        case "thumb":
        case "thumbnail":
          // Both images and videos can have thumbnail paths (for videos it's a still image)
          if (metadata.getThumbnailPath() != null) {
            filePath = metadata.getThumbnailPath();
            isServingThumbnail = true;
          }
          break;
        case "medium":
          if (metadata.getMediumPath() != null) {
            filePath = metadata.getMediumPath();
          }
          break;
        case "large":
          if (metadata.getLargePath() != null) {
            filePath = metadata.getLargePath();
          }
          break;
        case "original":
          // For videos, serve transcoded version if available (unless explicitly requesting
          // original)
          if (isVideo && metadata.getTranscodedVideoPath() != null) {
            filePath = metadata.getTranscodedVideoPath();
            isServingTranscodedVideo = true;
          }
          // For images, use original file path (already set as default)
          break;
        default:
          // No size specified or unrecognized size
          // For videos, serve transcoded version if available
          if (isVideo && !isOriginalRequested && metadata.getTranscodedVideoPath() != null) {
            filePath = metadata.getTranscodedVideoPath();
            isServingTranscodedVideo = true;
          }
          break;
      }
    } else if (isVideo && metadata.getTranscodedVideoPath() != null) {
      // No size specified for video, serve transcoded version
      filePath = metadata.getTranscodedVideoPath();
      isServingTranscodedVideo = true;
    }

    // Adjust MIME type based on what we're actually serving
    if (isServingThumbnail && isVideo) {
      // Video thumbnails are JPEG images
      mimeType = "image/jpeg";
    } else if (isServingTranscodedVideo) {
      // Transcoded videos are always MP4
      mimeType = "video/mp4";
    }

    Path absolutePath = toAbsolutePath(filePath);

    return new FileServeInfo(
        mimeType,
        metadata.getChecksum(),
        metadata.getUploadedAt(),
        absolutePath,
        metadata.getStoredFilename());
  }

  private FileInfo convertToFileInfo(FileMetadata metadata) {
    FileInfo info = fileInfoMapper.fileMetadataToFileInfo(metadata);

    // Fetch tags if not already loaded (for queries without JOIN FETCH)
    if (info.getTags() == null || info.getTags().isEmpty()) {
      List<String> tags =
          imageTagRepository.findByFileMetadataId(metadata.getId()).stream()
              .map(imageTag -> imageTag.getTag().getName())
              .collect(Collectors.toList());
      info.setTags(tags);
    }

    return info;
  }

  /**
   * Optimized version of convertToFileInfo that uses pre-fetched tags from JOIN FETCH. This avoids
   * N+1 query problems when tags are already loaded. The mapper's afterMapping automatically
   * handles pre-fetched tags if available.
   */
  private FileInfo convertToFileInfoOptimized(FileMetadata metadata) {
    return fileInfoMapper.fileMetadataToFileInfo(metadata);
  }

  /**
   * Ensure the special "no_tag" tag exists for the current user. Creates it if it doesn't exist.
   */
  private void ensureNoTagExists(User user) {
    if (!tagRepository.existsByUserAndName(user, NO_TAG)) {
      Tag noTag = new Tag();
      noTag.setUser(user);
      noTag.setName(NO_TAG);
      tagRepository.save(noTag);
      log.info("Created special '{}' tag for user: {}", NO_TAG, user.getEmail());
    }
  }

  /** Add the "no_tag" tag to a file (without any checks or side effects). */
  private void addNoTagToFile(FileMetadata metadata, User user) {
    Tag noTag =
        tagRepository
            .findByUserAndName(user, NO_TAG)
            .orElseThrow(() -> new ResourceNotFoundException("Tag", "name", NO_TAG));

    // Check if no_tag already exists for this file
    if (imageTagRepository
        .findByFileMetadataIdAndTagId(metadata.getId(), noTag.getId())
        .isEmpty()) {
      ImageTag imageTag = new ImageTag();
      imageTag.setFileMetadata(metadata);
      imageTag.setTag(noTag);
      imageTagRepository.save(imageTag);
      log.info("Added '{}' to file: {}", NO_TAG, metadata.getStoredFilename());
    }
  }

  /** Remove the "no_tag" tag from a file (if it exists). */
  private void removeNoTagFromFile(Long fileId, User user) {
    Optional<Tag> noTagOpt = tagRepository.findByUserAndName(user, NO_TAG);
    if (noTagOpt.isPresent()) {
      Tag noTag = noTagOpt.get();
      Optional<ImageTag> imageTagOpt =
          imageTagRepository.findByFileMetadataIdAndTagId(fileId, noTag.getId());
      if (imageTagOpt.isPresent()) {
        imageTagRepository.delete(imageTagOpt.get());
        log.info("Removed '{}' from file ID: {}", NO_TAG, fileId);
      }
    }
  }

  /**
   * Rotate an image 90 degrees counterclockwise (to the left). This physically rotates the image
   * file and regenerates all thumbnails.
   *
   * @param fileId The ID of the file to rotate
   */
  @Transactional
  public void rotateImageLeft(Long fileId) {
    log.info("========================================");
    log.info("📸 Rotation request received for file ID: {}", fileId);

    User currentUser = userContext.getCurrentUser();
    log.info("   User: {}", currentUser.getEmail());

    FileMetadata metadata =
        metadataRepository
            .findByIdAndUserId(fileId, currentUser.getId())
            .orElseThrow(() -> new ResourceNotFoundException("File", "id", fileId));

    log.info("   File: {} ({})", metadata.getOriginalName(), metadata.getMimeType());
    log.info(
        "   Current rotation: {}°", metadata.getRotation() != null ? metadata.getRotation() : 0);

    // Verify this is an image file
    if (!thumbnailService.isImageFile(metadata.getMimeType())) {
      log.error("❌ Cannot rotate: not an image file");
      throw new ValidationException("Only image files can be rotated");
    }

    // Get the file path
    Path originalFile = toAbsolutePath(metadata.getFilePath());
    log.info("   Original file path: {}", originalFile);
    log.info("   File exists: {}", originalFile.toFile().exists());

    if (!originalFile.toFile().exists()) {
      log.error("❌ Image file not found on disk: {}", originalFile);
      throw new ResourceNotFoundException("Image file not found on disk");
    }

    try {
      // Rotate the original image file
      log.info("   Starting image rotation...");
      boolean rotateSuccess = thumbnailService.rotateImageLeft(originalFile);
      if (!rotateSuccess) {
        log.error("❌ ThumbnailService.rotateImageLeft returned false");
        throw new StorageException("Failed to rotate image file");
      }
      log.info("   ✅ Image file rotated successfully");

      // Delete existing thumbnails
      log.info("   Deleting old thumbnails...");
      thumbnailService.deleteThumbnails(
          toAbsolutePath(metadata.getThumbnailPath()),
          toAbsolutePath(metadata.getMediumPath()),
          toAbsolutePath(metadata.getLargePath()));

      // Regenerate all thumbnails with the rotated image
      log.info("   Regenerating thumbnails...");
      Path[] thumbnails = thumbnailService.generateAllThumbnails(originalFile, originalFile);

      // Update thumbnail paths
      if (thumbnails[0] != null) {
        metadata.setThumbnailPath(toRelativePath(thumbnails[0]));
        log.info("   ✅ Generated thumbnail");
      }
      if (thumbnails[1] != null) {
        metadata.setMediumPath(toRelativePath(thumbnails[1]));
        log.info("   ✅ Generated medium");
      }
      if (thumbnails[2] != null) {
        metadata.setLargePath(toRelativePath(thumbnails[2]));
        log.info("   ✅ Generated large");
      }

      // Update rotation metadata (increment by 90 degrees, wrapping at 360)
      int currentRotation = metadata.getRotation() != null ? metadata.getRotation() : 0;
      int newRotation = (currentRotation + 90) % 360;
      metadata.setRotation(newRotation);
      log.info("   Updated rotation: {}° -> {}°", currentRotation, newRotation);

      // Swap width and height since we rotated 90 degrees
      if (metadata.getWidth() != null && metadata.getHeight() != null) {
        Integer temp = metadata.getWidth();
        metadata.setWidth(metadata.getHeight());
        metadata.setHeight(temp);
        log.info("   Swapped dimensions: {}x{}", metadata.getWidth(), metadata.getHeight());
      }

      // Regenerate public token to bust browser cache
      String oldToken = metadata.getPublicToken();
      byte[] bytes = new byte[24]; // 48 hex chars
      new java.security.SecureRandom().nextBytes(bytes);
      String newToken = java.util.HexFormat.of().formatHex(bytes);
      metadata.setPublicToken(newToken);
      log.info(
          "   Updated public token to bust cache: {} -> {}",
          oldToken != null ? oldToken.substring(0, 8) + "..." : "null",
          newToken.substring(0, 8) + "...");

      // Save updated metadata
      log.info("   Saving metadata to database...");
      metadataRepository.save(metadata);

      log.info(
          "✅ Successfully rotated image {} by 90° left (total rotation: {}°)",
          metadata.getOriginalName(),
          newRotation);
      log.info("========================================");

    } catch (Exception e) {
      log.error("❌ Error rotating image {}: {}", metadata.getOriginalName(), e.getMessage(), e);
      log.error("========================================");
      throw new StorageException("Failed to rotate image: " + e.getMessage(), e);
    }
  }
}
