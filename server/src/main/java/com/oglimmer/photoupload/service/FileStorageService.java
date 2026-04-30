/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import org.springframework.context.annotation.Profile;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.config.JobsProperties;
import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ImageTag;
import com.oglimmer.photoupload.entity.JobType;
import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.DuplicateResourceException;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.exception.StorageException;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.mapper.FileInfoMapper;
import com.oglimmer.photoupload.model.FileInfo;
import com.oglimmer.photoupload.model.FileServeInfo;
import com.oglimmer.photoupload.repository.AlbumEnabledTagRepository;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.ImageTagRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import com.oglimmer.photoupload.storage.StoragePaths;
import com.oglimmer.photoupload.util.MimeTypePredicates;
import jakarta.annotation.PostConstruct;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.time.Instant;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.task.TaskRejectedException;
import org.springframework.jdbc.core.BatchPreparedStatementSetter;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.multipart.MultipartFile;

@Profile(Profiles.API)
@Service
@Slf4j
public class FileStorageService {

  public static final String NO_TAG = "no_tag";
  public static final String ALL_TAG = "all";

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
  private final AlbumEnabledTagRepository albumEnabledTagRepository;
  // Worker-only after the deployment split (Phase 4a). The api pod boots with this empty; the
  // remaining heavy admin methods (rotate, generateMissingThumbnails, etc.) throw when invoked
  // until they are rewritten as worker-side jobs (Phase 4.5, D17).
  private final Optional<ThumbnailService> thumbnailService;
  private final LocalFileCleanupService localFileCleanupService;
  private final JdbcTemplate jdbcTemplate;
  private final AlbumRepository albumRepository;
  private final FileInfoMapper fileInfoMapper;
  private final UserContext userContext;
  private final TransactionTemplate transactionTemplate;
  // Worker-only after Phase 4a. The legacy @Async fallback (used when
  // {@code jobs.dispatcher.enabled=false}) is the only call site; on api-only deploys with the
  // dispatcher enabled, the empty Optional is never read. Misconfigurations fail fast.
  private final Optional<FileProcessingService> fileProcessingService;
  private final JobEnqueueService jobEnqueueService;
  private final JobsProperties jobsProperties;
  // Optional: present iff storage.s3.enabled=true. When present, the upload path PUTs the body
  // directly to MinIO and stores an S3 key in file_path; the local PVC is used only for Spring's
  // transient .multipart-tmp staging (auto-cleaned per request) and per-job processing scratch.
  private final Optional<ObjectStorageService> objectStorage;

  public FileStorageService(
      FileStorageProperties properties,
      FileMetadataRepository metadataRepository,
      TagRepository tagRepository,
      ImageTagRepository imageTagRepository,
      AlbumEnabledTagRepository albumEnabledTagRepository,
      Optional<ThumbnailService> thumbnailService,
      LocalFileCleanupService localFileCleanupService,
      JdbcTemplate jdbcTemplate,
      AlbumRepository albumRepository,
      FileInfoMapper fileInfoMapper,
      UserContext userContext,
      PlatformTransactionManager transactionManager,
      Optional<FileProcessingService> fileProcessingService,
      JobEnqueueService jobEnqueueService,
      JobsProperties jobsProperties,
      Optional<ObjectStorageService> objectStorage) {
    this.properties = properties;
    this.metadataRepository = metadataRepository;
    this.tagRepository = tagRepository;
    this.imageTagRepository = imageTagRepository;
    this.albumEnabledTagRepository = albumEnabledTagRepository;
    this.thumbnailService = thumbnailService;
    this.localFileCleanupService = localFileCleanupService;
    this.jdbcTemplate = jdbcTemplate;
    this.fileInfoMapper = fileInfoMapper;
    this.albumRepository = albumRepository;
    this.userContext = userContext;
    this.fileStorageLocation = Paths.get(properties.getUploadDir()).toAbsolutePath().normalize();
    this.transactionTemplate = new TransactionTemplate(transactionManager);
    this.fileProcessingService = fileProcessingService;
    this.jobEnqueueService = jobEnqueueService;
    this.jobsProperties = jobsProperties;
    this.objectStorage = objectStorage;
  }

  @PostConstruct
  public void init() {
    try {
      Files.createDirectories(this.fileStorageLocation);
      Files.createDirectories(this.fileStorageLocation.resolve(".multipart-tmp"));
      log.info("Upload directory created at: {}", this.fileStorageLocation);
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

  /**
   * Resolve the thumbnailer for admin/rotate paths. Empty on api-only deployments after the worker
   * split (Phase 4a, D17) — those endpoints are documented broken until the Phase 4.5 worker-job
   * rewrite. Throws so the controller maps to a clear 5xx instead of NPE'ing later.
   */
  private ThumbnailService requireThumbnailer() {
    return thumbnailService.orElseThrow(
        () ->
            new IllegalStateException(
                "Image processing is not available on this pod (worker profile required). "
                    + "Admin/rotate endpoints are deferred to a worker-side job; see plan D17."));
  }

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
    if (properties.isDuplicateDetectionEnabled() && contentId != null && !contentId.isBlank()) {
      FileInfo duplicateByContentId =
          transactionTemplate.execute(
              status -> {
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
                return null;
              });
      if (duplicateByContentId != null) {
        return duplicateByContentId;
      }
    }

    // Generate a unique final name. With direct-to-S3 we never write a durable file under our
    // own control: Spring's multipart parser stages the body in .multipart-tmp (transient), we
    // hash it in one pass, then PUT the same staged body to MinIO in a second read. No
    // ATOMIC_MOVE on the PVC, no .tmp left behind on errors.
    String originalFilename = file.getOriginalFilename();
    String extension = getFileExtension(originalFilename);
    String nameWithoutExtension = getFilenameWithoutExtension(originalFilename);
    String uniqueSuffix =
        System.currentTimeMillis() + "-" + UUID.randomUUID().toString().substring(0, 9);
    String newFilename = nameWithoutExtension + "-" + uniqueSuffix + "." + extension;
    boolean useObjectStorage = objectStorage.isPresent();

    // Write the multipart body to a stable temp file exactly once.
    // Calling file.getInputStream() twice is unreliable: some Part implementations back the
    // stream with a non-resettable file descriptor, so a second open can deliver fewer bytes
    // than file.getSize() declares — the AWS SDK then throws IllegalStateException.
    Path tempFile =
        this.fileStorageLocation
            .resolve(".multipart-tmp")
            .resolve("." + newFilename + ".tmp");
    try (InputStream in = file.getInputStream()) {
      Files.copy(in, tempFile, StandardCopyOption.REPLACE_EXISTING);
    }
    final String checksum = computeSha256(tempFile);

    // Check for duplicate by checksum (same album and other albums) in a single transaction.
    FileInfo duplicateByChecksum =
        !properties.isDuplicateDetectionEnabled()
            ? null
            : transactionTemplate.execute(
                status -> {
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

                  List<FileMetadata> existingInOtherAlbum =
                      metadataRepository.findByChecksum(checksum);
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
                  return null;
                });
    if (duplicateByChecksum != null) {
      Files.deleteIfExists(tempFile);
      return duplicateByChecksum;
    }

    String contentType = file.getContentType();

    // Persist the bytes. With S3 enabled the storage of record is MinIO; otherwise fall back to
    // the legacy local-disk write so tests / non-S3 deployments still function.
    final String storedPath;
    if (useObjectStorage) {
      String storageKey = StoragePaths.ORIGINALS_PREFIX + newFilename;
      try {
        objectStorage.get().putFile(storageKey, tempFile, contentType);
      } finally {
        Files.deleteIfExists(tempFile);
      }
      storedPath = storageKey;
      log.info("✅ File uploaded to S3: {} ({})", originalFilename, formatBytes(file.getSize()));
    } else {
      Path targetLocation = this.fileStorageLocation.resolve(newFilename);
      Files.move(tempFile, targetLocation, StandardCopyOption.ATOMIC_MOVE);
      storedPath = toRelativePath(targetLocation);
      log.info("✅ File uploaded to disk: {} ({})", originalFilename, formatBytes(file.getSize()));
    }

    // Insert metadata row immediately with null thumbnails/transcoded paths — processing
    // will fill those in asynchronously and save again.
    final String finalNewFilename = newFilename;
    final String finalContentType = contentType;
    final String finalStoredPath = storedPath;
    FileInfo result =
        transactionTemplate.execute(
            status -> {
              FileMetadata metadata = new FileMetadata();
              metadata.setOriginalName(originalFilename);
              metadata.setStoredFilename(finalNewFilename);
              metadata.setFileSize(file.getSize());
              metadata.setMimeType(finalContentType);
              metadata.setFilePath(finalStoredPath);
              metadata.setUploadedAt(Instant.now());
              metadata.setChecksum(checksum);
              metadata.setContentId(contentId);
              // When the dispatcher owns processing, the row is QUEUED at insert time and the
              // jobs table is the source of truth. The legacy @Async path keeps INGESTED so
              // FileProcessingService transitions it to PROCESSING the same way it always has.
              boolean dispatcherEnabled = jobsProperties.getDispatcher().isEnabled();
              metadata.setProcessingStatus(
                  dispatcherEnabled ? ProcessingStatus.QUEUED : ProcessingStatus.INGESTED);

              Album album =
                  albumRepository
                      .findByUserAndId(currentUser, effectiveAlbumId)
                      .orElseThrow(
                          () -> new ResourceNotFoundException("Album", "id", effectiveAlbumId));
              metadata.setAlbum(album);

              Integer maxOrder =
                  metadataRepository.findMaxDisplayOrderByAlbumIdAndUserId(
                      effectiveAlbumId, currentUser.getId());
              metadata.setDisplayOrder(maxOrder != null ? maxOrder + 1 : 0);

              FileMetadata saved = metadataRepository.save(metadata);
              ensureNoTagExists(currentUser);
              addNoTagToFile(saved, currentUser);
              if (dispatcherEnabled) {
                // Same TX as the metadata insert → either both visible or neither.
                jobEnqueueService.enqueue(saved.getId());
              }
              return convertToFileInfoWithId(saved);
            });

    if (!jobsProperties.getDispatcher().isEnabled()) {
      // Legacy path: hand the new asset id to the @Async executor directly. If the executor
      // queue is full and AbortPolicy rejects us, the row already exists and can be
      // reprocessed later; we log and return success so the client doesn't double-upload.
      FileProcessingService legacy =
          fileProcessingService.orElseThrow(
              () ->
                  new IllegalStateException(
                      "jobs.dispatcher.enabled=false but FileProcessingService is not loaded "
                          + "(worker profile required). Enable the dispatcher on api-only deploys."));
      try {
        legacy.processFileAsync(result.getId());
      } catch (TaskRejectedException e) {
        log.warn(
            "Processing task rejected after insert for {} (id={}); row retained for later reprocess",
            originalFilename,
            result.getId());
      }
    }

    return result;
  }

  private FileInfo convertToFileInfoWithId(FileMetadata saved) {
    return convertToFileInfo(saved);
  }

  @Transactional(readOnly = true)
  public List<FileInfo> listFiles() {
    return metadataRepository.findAllByOrderByDisplayOrderAsc().stream()
        .map(this::convertToFileInfo)
        .collect(Collectors.toList());
  }

  @Transactional(readOnly = true)
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

  @Transactional(readOnly = true)
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

  @Transactional(readOnly = true)
  public List<FileInfo> listFilesByAlbumByShareToken(String shareToken) {
    // Return files in specified album (albumId required)
    // Using optimized query with JOIN FETCH to avoid N+1 query problem
    return metadataRepository
        .findByAlbumShareTokenWithTagsOrderByDisplayOrderAsc(shareToken)
        .stream()
        .map(this::convertToFileInfoOptimized)
        .collect(Collectors.toList());
  }

  @Transactional(readOnly = true)
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

  private String computeSha256(Path file) throws IOException {
    MessageDigest digest;
    try {
      digest = MessageDigest.getInstance("SHA-256");
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException("SHA-256 unavailable", e);
    }
    byte[] buf = new byte[64 * 1024];
    try (InputStream in = Files.newInputStream(file);
        DigestInputStream dis = new DigestInputStream(in, digest)) {
      while (dis.read(buf) != -1) {}
    }
    byte[] hash = digest.digest();
    StringBuilder hex = new StringBuilder(hash.length * 2);
    for (byte b : hash) {
      hex.append(String.format("%02x", b));
    }
    return hex.toString();
  }

  @Transactional
  /**
   * Compares every key in the S3 bucket against the paths recorded in the DB and deletes any key
   * that has no corresponding row. Pass {@code dryRun=true} to log what would be deleted without
   * touching MinIO — always run a dry-run first to sanity-check the numbers.
   */
  public Map<String, Object> purgeOrphanedS3Objects(boolean dryRun) {
    if (objectStorage.isEmpty()) {
      throw new IllegalStateException("S3 storage is not enabled");
    }
    ObjectStorageService s3 = objectStorage.get();

    Set<String> knownPaths = new HashSet<>(metadataRepository.findAllStoredPaths());
    List<String> bucketKeys = s3.listKeys();

    int orphaned = 0;
    int deleted = 0;
    int failed = 0;
    for (String key : bucketKeys) {
      if (!knownPaths.contains(key)) {
        orphaned++;
        if (dryRun) {
          log.info("Dry run — orphaned S3 object: {}", key);
        } else {
          try {
            s3.delete(key);
            deleted++;
            log.info("Deleted orphaned S3 object: {}", key);
          } catch (Exception e) {
            failed++;
            log.warn("Failed to delete orphaned S3 object {}: {}", key, e.getMessage());
          }
        }
      }
    }

    log.info(
        "S3 orphan purge complete (dryRun={}): {} bucket keys, {} known DB paths, {} orphaned, {} deleted, {} failed",
        dryRun,
        bucketKeys.size(),
        knownPaths.size(),
        orphaned,
        deleted,
        failed);

    Map<String, Object> result = new HashMap<>();
    result.put("dryRun", dryRun);
    result.put("totalBucketKeys", bucketKeys.size());
    result.put("knownDbPaths", knownPaths.size());
    result.put("orphaned", orphaned);
    result.put("deleted", deleted);
    result.put("failed", failed);
    return result;
  }

  private void deleteS3Objects(FileMetadata metadata) {
    if (objectStorage.isEmpty()) {
      log.warn(
          "S3 key {} found in DB but ObjectStorageService is not available — skipping object deletion",
          metadata.getFilePath());
      return;
    }
    ObjectStorageService s3 = objectStorage.get();
    deleteS3Key(s3, metadata.getFilePath(), "original");
    deleteS3Key(s3, metadata.getThumbnailPath(), "thumbnail");
    deleteS3Key(s3, metadata.getMediumPath(), "medium");
    deleteS3Key(s3, metadata.getLargePath(), "large");
    deleteS3Key(s3, metadata.getTranscodedVideoPath(), "transcoded");
  }

  private void deleteS3Key(ObjectStorageService s3, String key, String label) {
    if (key == null) {
      return;
    }
    try {
      s3.delete(key);
      log.debug("Deleted S3 {} object: {}", label, key);
    } catch (Exception e) {
      log.warn("Failed to delete S3 {} object {}: {}", label, key, e.getMessage());
    }
  }

  public void deleteFile(Long fileId) {
    FileMetadata metadata =
        metadataRepository
            .findById(fileId)
            .orElseThrow(() -> new ResourceNotFoundException("File", "id", fileId));

    // Check if physical files are shared with other FileMetadata records
    boolean isShared = metadataRepository.countByFilePath(metadata.getFilePath()) > 1;

    if (isShared) {
      log.info(
          "Skipping physical file deletion for {} — shared with other records",
          metadata.getStoredFilename());
    } else if (StoragePaths.isS3Key(metadata.getFilePath())) {
      deleteS3Objects(metadata);
    } else {
      try {
        // Delete physical file
        Path filePath = toAbsolutePath(metadata.getFilePath());
        Files.deleteIfExists(filePath);
        log.info("Deleted file: {}", metadata.getStoredFilename());

        // Delete thumbnails
        localFileCleanupService.deleteThumbnails(
            toAbsolutePath(metadata.getThumbnailPath()),
            toAbsolutePath(metadata.getMediumPath()),
            toAbsolutePath(metadata.getLargePath()));

        // Delete transcoded video if exists
        localFileCleanupService.deleteTranscodedVideo(
            toAbsolutePath(metadata.getTranscodedVideoPath()));
      } catch (IOException e) {
        log.error("Error deleting file", e);
        throw new StorageException("Could not delete file: " + e.getMessage(), e);
      }
    }

    // Delete metadata (cascade will delete image_tags)
    metadataRepository.delete(metadata);
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

    // Enforce album's enabled-tags list (system tags NO_TAG and ALL_TAG are always allowed)
    if (!NO_TAG.equals(tagName)
        && !ALL_TAG.equals(tagName)
        && !albumEnabledTagRepository.existsByAlbumIdAndTagId(
            metadata.getAlbum().getId(), tag.getId())) {
      throw new ValidationException("Tag '" + tagName + "' is not enabled for this album");
    }

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
  public Map<String, Object> generateMissingThumbnails(boolean overwrite) {
    ThumbnailService thumb = requireThumbnailer();
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
      if (!MimeTypePredicates.isImageFile(metadata.getMimeType())) {
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

        // If overwriting, delete existing thumbnails first (disk I/O, no transaction needed)
        if (overwrite) {
          localFileCleanupService.deleteThumbnails(
              toAbsolutePath(metadata.getThumbnailPath()),
              toAbsolutePath(metadata.getMediumPath()),
              toAbsolutePath(metadata.getLargePath()));
        }

        // Generate thumbnails (CPU/disk intensive, no transaction needed)
        Path[] thumbnails = thumb.generateAllThumbnails(originalFile, originalFile);

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
          // Short transaction for DB save only
          transactionTemplate.executeWithoutResult(status -> metadataRepository.save(metadata));
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

        // Check if transcoded file exists on disk (no transaction needed)
        if (transcodedLocation.toFile().exists()) {
          // Short transaction for DB update only
          metadata.setTranscodedVideoPath(toRelativePath(transcodedLocation));
          transactionTemplate.executeWithoutResult(status -> metadataRepository.save(metadata));
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

        // Check if thumbnail file exists on disk (no transaction needed)
        if (thumbnailLocation.toFile().exists()) {
          // Short transaction for DB update only
          metadata.setThumbnailPath(toRelativePath(thumbnailLocation));
          transactionTemplate.executeWithoutResult(status -> metadataRepository.save(metadata));
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
  @Transactional(readOnly = true)
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
    // Tracks whether the size the caller asked for is genuinely present. When false, the
    // controller decides between 202 (processing not done) and serving the original (done
    // but no derivative — e.g. video has only a thumb, or image processing failed).
    boolean derivativeReady = true;

    // Handle size parameter for both images and videos
    if (size != null) {
      switch (size.toLowerCase()) {
        case "thumb":
        case "thumbnail":
          // Both images and videos can have thumbnail paths (for videos it's a still image)
          if (metadata.getThumbnailPath() != null) {
            filePath = metadata.getThumbnailPath();
            isServingThumbnail = true;
          } else {
            derivativeReady = false;
          }
          break;
        case "medium":
          if (metadata.getMediumPath() != null) {
            filePath = metadata.getMediumPath();
          } else {
            derivativeReady = false;
          }
          break;
        case "large":
          if (metadata.getLargePath() != null) {
            filePath = metadata.getLargePath();
          } else {
            derivativeReady = false;
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

    // Migrated rows hold an S3 object key (originals/... or derivatives/...). Leave the local
    // Path null in that case so the controller fails loudly if it forgets to check storageKey,
    // and route serve via ObjectStorageService instead.
    boolean s3Backed = StoragePaths.isS3Key(filePath);
    Path absolutePath = s3Backed ? null : toAbsolutePath(filePath);

    return new FileServeInfo(
        mimeType,
        metadata.getChecksum(),
        metadata.getUploadedAt(),
        absolutePath,
        metadata.getStoredFilename(),
        metadata.getProcessingStatus(),
        derivativeReady,
        s3Backed ? filePath : null);
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
   * Enqueue a rotate-90-CCW job for the given asset (Phase 4.5, D17). The actual ImageMagick work
   * runs on the worker pod via {@link FileProcessingService#rotateAndReprocess(Long)} — the api
   * pod no longer has the thumbnailer beans. Returns immediately so the controller can answer
   * 202 Accepted; the UI polls {@code GET /api/assets/{id}/status} until DONE.
   *
   * <p>Same-TX guarantee: the {@code FileMetadata} status flip and the {@code processing_jobs} row
   * insert commit together, so the dispatcher never sees a queued job for an asset whose row
   * still says DONE (which would race the gallery's read-after-rotate).
   */
  public void rotateImageLeft(Long fileId) {
    User currentUser = userContext.getCurrentUser();

    FileMetadata metadata =
        metadataRepository
            .findByIdAndUserId(fileId, currentUser.getId())
            .orElseThrow(() -> new ResourceNotFoundException("File", "id", fileId));

    if (!MimeTypePredicates.isImageFile(metadata.getMimeType())) {
      throw new ValidationException("Only image files can be rotated");
    }
    // Rotation needs the worker to download the original from S3, rotate it, and PUT it back.
    // Pre-S3 rows (Gap 2a migration was completed) never reach this branch in practice, but
    // reject loudly rather than silently succeeding without rotating bytes.
    if (!StoragePaths.isS3Key(metadata.getFilePath())) {
      throw new ValidationException(
          "This asset is on legacy local storage. Migrate to object storage before rotating.");
    }

    log.info(
        "📸 Enqueuing rotate-left for asset {} ({}, current rotation {}°) by user {}",
        fileId,
        metadata.getOriginalName(),
        metadata.getRotation() != null ? metadata.getRotation() : 0,
        currentUser.getEmail());

    transactionTemplate.executeWithoutResult(
        status -> {
          FileMetadata locked =
              metadataRepository
                  .findById(fileId)
                  .orElseThrow(() -> new ResourceNotFoundException("File", "id", fileId));
          locked.setProcessingStatus(ProcessingStatus.QUEUED);
          locked.setProcessingAttempts(0);
          locked.setProcessingError(null);
          locked.setProcessingCompletedAt(null);
          metadataRepository.save(locked);
          jobEnqueueService.enqueue(fileId, JobType.ROTATE_LEFT);
        });
  }
}
