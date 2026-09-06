/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.config.JobsProperties;
import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ImageTag;
import com.oglimmer.photoupload.entity.JobType;
import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.entity.SlideshowRecording;
import com.oglimmer.photoupload.entity.StorageBackend;
import com.oglimmer.photoupload.entity.SystemTags;
import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.DuplicateResourceException;
import com.oglimmer.photoupload.exception.JobQueueSaturatedException;
import com.oglimmer.photoupload.exception.ResourceGoneException;
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
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.repository.StorageBackendRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import com.oglimmer.photoupload.storage.BackendStorage;
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
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.function.Predicate;
import java.util.stream.Collectors;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.BatchPreparedStatementSetter;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;

@Profile(Profiles.API)
@Service
@Slf4j
public class FileStorageService {

  /**
   * Cap on a caption (D69). Chosen for the layout, not the column: TEXT holds far more, but the
   * caption is rendered under a gallery thumbnail.
   */
  private static final int MAX_CAPTION_LENGTH = 2000;

  /** Why a lone {@code hidden} cannot be taken off a file by hand (D79). */
  static final String HIDDEN_IS_THE_ONLY_TAG =
      "'hidden' is the only tag on this photo, so it would come straight back. "
          + "Give the photo a tag to publish it.";

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
  private final JdbcTemplate jdbcTemplate;
  private final AlbumRepository albumRepository;
  private final SlideshowRecordingRepository slideshowRecordingRepository;
  private final StorageBackendRepository storageBackendRepository;
  private final FileInfoMapper fileInfoMapper;
  private final UserContext userContext;
  private final TransactionTemplate transactionTemplate;
  private final JobEnqueueService jobEnqueueService;
  private final SystemTagProvisioner systemTagProvisioner;
  private final StorageQuotaService storageQuotaService;
  // Backpressure for the re-processing paths (rotate / enhance / regen). The ingest paths have
  // had their own guard since Phase 4 — UploadBackpressureFilter for POST /api/upload and the
  // TUS pre-create hook — but nothing stood between a bulk action and the queue.
  private final JobQueueDepthService queueDepthService;
  private final JobsProperties jobsProperties;
  // The upload path PUTs the body to the album's backend and stores the object key in file_path;
  // local disk is only Spring's transient .multipart-tmp staging (D77).
  private final ObjectStorageService objectStorage;

  public FileStorageService(
      FileStorageProperties properties,
      FileMetadataRepository metadataRepository,
      TagRepository tagRepository,
      ImageTagRepository imageTagRepository,
      AlbumEnabledTagRepository albumEnabledTagRepository,
      JdbcTemplate jdbcTemplate,
      AlbumRepository albumRepository,
      SlideshowRecordingRepository slideshowRecordingRepository,
      StorageBackendRepository storageBackendRepository,
      FileInfoMapper fileInfoMapper,
      UserContext userContext,
      PlatformTransactionManager transactionManager,
      JobEnqueueService jobEnqueueService,
      SystemTagProvisioner systemTagProvisioner,
      StorageQuotaService storageQuotaService,
      ObjectStorageService objectStorage,
      JobQueueDepthService queueDepthService,
      JobsProperties jobsProperties) {
    this.properties = properties;
    this.metadataRepository = metadataRepository;
    this.tagRepository = tagRepository;
    this.imageTagRepository = imageTagRepository;
    this.albumEnabledTagRepository = albumEnabledTagRepository;
    this.jdbcTemplate = jdbcTemplate;
    this.fileInfoMapper = fileInfoMapper;
    this.albumRepository = albumRepository;
    this.slideshowRecordingRepository = slideshowRecordingRepository;
    this.storageBackendRepository = storageBackendRepository;
    this.userContext = userContext;
    this.fileStorageLocation = Paths.get(properties.getUploadDir()).toAbsolutePath().normalize();
    this.transactionTemplate = new TransactionTemplate(transactionManager);
    this.jobEnqueueService = jobEnqueueService;
    this.systemTagProvisioner = systemTagProvisioner;
    this.storageQuotaService = storageQuotaService;
    this.objectStorage = objectStorage;
    this.queueDepthService = queueDepthService;
    this.jobsProperties = jobsProperties;
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

    // Ownership BEFORE any byte moves. The album decides which storage backend receives the PUT,
    // and an album id that is not the caller's used to be discovered only by the insert transaction
    // — after the bytes had already landed in somebody else's bucket as an orphan.
    requireOwnedAlbum(currentUser, effectiveAlbumId);

    // Before anything is staged or PUT: an upload that cannot be kept should not be carried.
    // A no-op when the album lives on the user's own storage — that disk is theirs to fill.
    storageQuotaService.requireRoomFor(currentUser, effectiveAlbumId, file.getSize());

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
    // Resolve the album's storage backend BEFORE any byte is written. An album can live on its
    // owner's own S3, so choosing the backend after the PUT would mean the bytes went to the
    // instance's MinIO while the row claims otherwise — unreadable, and invisible until serve time.
    final BackendStorage albumStorage = objectStorage.forAlbumId(effectiveAlbumId);

    // Write the multipart body to a stable temp file exactly once.
    // Calling file.getInputStream() twice is unreliable: some Part implementations back the
    // stream with a non-resettable file descriptor, so a second open can deliver fewer bytes
    // than file.getSize() declares — the AWS SDK then throws IllegalStateException.
    Path tempFile =
        this.fileStorageLocation.resolve(".multipart-tmp").resolve("." + newFilename + ".tmp");
    try (InputStream in = file.getInputStream()) {
      Files.copy(in, tempFile, StandardCopyOption.REPLACE_EXISTING);
    }
    // From here until the bytes are durable, every exit path must remove the staged file.
    final String checksum;
    final FileInfo duplicateByChecksum;
    try {
      checksum = computeSha256(tempFile);
      duplicateByChecksum = findDuplicateByChecksum(checksum, file, effectiveAlbumId, currentUser);
    } catch (IOException | RuntimeException e) {
      Files.deleteIfExists(tempFile);
      throw e;
    }
    if (duplicateByChecksum != null) {
      Files.deleteIfExists(tempFile);
      return duplicateByChecksum;
    }

    String contentType = file.getContentType();
    // Persist the bytes: the storage of record is the album's backend.
    final String storedPath = StoragePaths.ORIGINALS_PREFIX + newFilename;
    try {
      albumStorage.putFile(storedPath, tempFile, contentType);
    } finally {
      Files.deleteIfExists(tempFile);
    }
    log.info("✅ File uploaded to S3: {} ({})", originalFilename, formatBytes(file.getSize()));

    // Insert metadata row immediately with null thumbnails/transcoded paths — processing
    // will fill those in asynchronously and save again.
    final String finalNewFilename = newFilename;
    final String finalContentType = contentType;
    final String finalStoredPath = storedPath;
    // Commit the new-asset tag BEFORE opening the insert transaction. Not a style choice: MariaDB
    // runs REPEATABLE READ, so a transaction that starts first cannot see a tags row another
    // request commits later — and the image_tags insert's foreign-key check on that unseen parent
    // fails with 1020 "Record has changed since last read", taking the file_metadata row down with
    // it. Provisioning first means this transaction's snapshot always contains the tag it
    // references.
    final String newAssetTag = currentUser.getNewAssetTag();
    final Long newAssetTagId = ensureNewAssetTagExists(currentUser);

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
              metadata.setProcessingStatus(ProcessingStatus.QUEUED);

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
              addTagRowIfMissing(saved, newAssetTagId, newAssetTag);
              // Same TX as the metadata insert → either both visible or neither.
              jobEnqueueService.enqueue(saved.getId());
              return convertToFileInfo(saved);
            });

    return result;
  }

  /**
   * Checksum-based duplicate detection for the multipart path: first the same album, then any
   * album. Returns the existing asset to hand back instead of storing a second copy, or {@code
   * null} when the upload is new (or detection is switched off).
   */
  private FileInfo findDuplicateByChecksum(
      String checksum, MultipartFile file, Long effectiveAlbumId, User currentUser) {
    if (!properties.isDuplicateDetectionEnabled()) {
      return null;
    }
    return transactionTemplate.execute(
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
          return null;
        });
  }

  /**
   * Phase 5 — TUS resumable upload landing path. Bytes are already in MinIO at {@code tusS3Key}
   * (where tusd put them as a multipart upload). We rename them server-side to the canonical {@code
   * originals/{stored_filename}} convention via S3 COPY+DELETE — see D24/D25 — then insert the
   * {@code file_metadata} row and enqueue a PROCESS job in the same TX, exactly like {@link
   * #storeFile}.
   *
   * <p>The hook controller is the only caller. The user has already been authenticated upstream
   * from {@code Upload-Metadata.auth}; we accept it as a plain {@link User} argument rather than
   * pulling it from {@link com.oglimmer.photoupload.security.UserContext} (no Spring Security
   * context exists for tusd→api hook calls).
   *
   * <p>Idempotency: a duplicate {@code contentId} <i>or</i> {@code checksum} for the same user
   * causes pre-create to reject 409 before tusd ever begins the upload, so this method ordinarily
   * runs at most once per upload. If post-finish fires twice (network retry), the caller
   * short-circuits on the existing row before invoking us — see {@code
   * TusHookService.handlePostFinish}.
   *
   * <p>{@code checksum} is the client's SHA-256 of the bytes it sent, and it is persisted here for
   * the same reason {@link #storeFile} persists its own: it is the only key that identifies one
   * photo across two devices. Nothing recomputes it server-side — the bytes never pass through this
   * pod on the same-backend path (S3 COPY), so hashing here would mean pulling the whole object
   * back just to confirm what the client already told us. A client that sends none leaves the
   * column null and keeps exactly the pre-fix behaviour.
   *
   * <p>The COPY is server-side in MinIO (no JVM bytes); the cleanup of {@code tusS3Key} and its
   * companion {@code .info} object is best-effort — a stale tus-uploads/{uuid} object is mopped up
   * by tusd's own {@code -expire-after} sweep.
   */
  public FileInfo registerTusUpload(
      User currentUser,
      Long albumId,
      String tusS3Key,
      String originalName,
      long fileSize,
      String contentType,
      String contentId,
      String checksum) {
    final Long effectiveAlbumId;
    if (albumId == null) {
      effectiveAlbumId = currentUser.getDefaultAlbumId();
      if (effectiveAlbumId == null) {
        throw new ValidationException(
            "Sync is paused. Please select a target album in your settings to resume uploads.");
      }
    } else {
      effectiveAlbumId = albumId;
    }

    validateTusUpload(originalName, contentType, fileSize);

    // Same rule as storeFile: prove the album is the caller's before the bytes are moved into its
    // backend. The staged tus-uploads/ object is left for the retention sweep on rejection.
    requireOwnedAlbum(currentUser, effectiveAlbumId);

    // Re-checked here even though pre-create already asked: the pre-create hook sees the size the
    // client *declared*, and the album it names can be changed between the two calls. Rejecting
    // now leaves the object in tus-uploads/, which retention sweeps — the user is never charged
    // for bytes that never became an asset.
    storageQuotaService.requireRoomFor(currentUser, effectiveAlbumId, fileSize);

    String extension = getFileExtension(originalName);
    String nameWithoutExtension = getFilenameWithoutExtension(originalName);
    String uniqueSuffix =
        System.currentTimeMillis() + "-" + UUID.randomUUID().toString().substring(0, 9);
    String newFilename = nameWithoutExtension + "-" + uniqueSuffix + "." + extension;
    String originalKey = StoragePaths.ORIGINALS_PREFIX + newFilename;

    // tusd always stages into the instance's own bucket — it is one process with one set of
    // credentials and it does not know which album the upload is for. So the finish hook is where
    // the bytes reach the album's actual backend. Same backend: a server-side COPY, no JVM bytes.
    // Different backend: transfer() streams them through this pod, which is the unavoidable price
    // of an album on the user's own S3.
    BackendStorage staging = objectStorage.forSystemDefault();
    BackendStorage target = objectStorage.forAlbumId(effectiveAlbumId);
    objectStorage.transfer(staging, tusS3Key, target, originalKey, contentType);

    final String finalContentType = contentType;
    final String finalNewFilename = newFilename;
    final String finalOriginalKey = originalKey;
    // Commit the new-asset tag BEFORE opening the insert transaction. Not a style choice: MariaDB
    // runs REPEATABLE READ, so a transaction that starts first cannot see a tags row another
    // request commits later — and the image_tags insert's foreign-key check on that unseen parent
    // fails with 1020 "Record has changed since last read", taking the file_metadata row down with
    // it. Provisioning first means this transaction's snapshot always contains the tag it
    // references.
    final String newAssetTag = currentUser.getNewAssetTag();
    final Long newAssetTagId = ensureNewAssetTagExists(currentUser);

    FileInfo result =
        transactionTemplate.execute(
            status -> {
              FileMetadata metadata = new FileMetadata();
              metadata.setOriginalName(originalName);
              metadata.setStoredFilename(finalNewFilename);
              metadata.setFileSize(fileSize);
              metadata.setMimeType(finalContentType);
              metadata.setFilePath(finalOriginalKey);
              metadata.setUploadedAt(Instant.now());
              metadata.setContentId(contentId);
              metadata.setChecksum(checksum);
              metadata.setProcessingStatus(ProcessingStatus.QUEUED);

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
              addTagRowIfMissing(saved, newAssetTagId, newAssetTag);
              jobEnqueueService.enqueue(saved.getId(), JobType.PROCESS);
              return convertToFileInfo(saved);
            });

    try {
      staging.deleteKeys(java.util.List.of(tusS3Key, tusS3Key + ".info"));
    } catch (Exception e) {
      log.warn("TUS cleanup failed for {} ({}); orphan job will mop up", tusS3Key, e.toString());
    }

    log.info(
        "✅ TUS upload registered: {} ({}) → asset {}",
        originalName,
        formatBytes(fileSize),
        result.getId());
    return result;
  }

  /**
   * Mirrors {@link #validateFile(MultipartFile)} for the TUS path where we don't have a
   * MultipartFile — only the metadata fields tusd surfaced from {@code Upload-Metadata}.
   */
  private void validateTusUpload(String originalName, String contentType, long fileSize) {
    if (originalName == null || originalName.isBlank()) {
      throw new ValidationException("Filename is required");
    }
    if (fileSize <= 0) {
      throw new ValidationException("Cannot register empty TUS upload");
    }
    if (fileSize > properties.getMaxFileSize()) {
      throw new ValidationException(
          "File size exceeds maximum limit of " + formatBytes(properties.getMaxFileSize()));
    }
    String extension = getFileExtension(originalName).toLowerCase();
    boolean isValidType =
        contentType != null
            && (ALLOWED_IMAGE_TYPES.contains(contentType)
                || ALLOWED_VIDEO_TYPES.contains(contentType));
    boolean isValidExtension = ALLOWED_EXTENSIONS.contains(extension);
    if (!isValidType && !isValidExtension) {
      throw new ValidationException("Only image and video files are allowed!");
    }
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

  /**
   * The public listing behind a share link. Both privacy gates live here, not in the callers: the
   * album must be published (an unpublished or unknown token is the same 404), and assets in the
   * {@code hidden} holding pen (D70) are dropped.
   */
  @Transactional(readOnly = true)
  public List<FileInfo> listFilesByAlbumByShareToken(String shareToken) {
    albumRepository
        .findByShareTokenAndPublishedTrue(shareToken)
        .orElseThrow(() -> new ResourceNotFoundException("Album not found with share token"));
    // Using optimized query with JOIN FETCH to avoid N+1 query problem
    return metadataRepository
        .findByAlbumShareTokenWithTagsOrderByDisplayOrderAsc(shareToken)
        .stream()
        .filter(m -> !isHidden(m))
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
    if (isHidden(metadata)) {
      // Only the public share pages read a file by its token this way, so a hidden asset is simply
      // not there. Note this does NOT gate `/api/i/{token}`: the owner's own gallery and the iOS
      // app fetch their pixels through that same route, so blocking it would blank their grid.
      // Withholding the token is the gate — the listing above never hands one out.
      throw new ResourceNotFoundException("File not found with public token: " + publicToken);
    }
    return convertToFileInfoOptimized(metadata);
  }

  /**
   * True if this asset is in the holding pen (D70) and must stay out of everything a public visitor
   * can reach. Reads the eagerly-fetched tag collection, so it costs nothing on the JOIN FETCH
   * queries and one lazy load elsewhere.
   */
  private static boolean isHidden(FileMetadata metadata) {
    return metadata.getImageTags().stream()
        .anyMatch(it -> SystemTags.HIDDEN.equals(it.getTag().getName()));
  }

  /**
   * Set (or clear) the owner's caption on one asset (D69).
   *
   * <p>Blank in means null stored, so "no caption" has exactly one representation in the column and
   * every reader can test for null alone. Length is capped well under the TEXT limit: the caption
   * is rendered under a thumbnail, and an unbounded one would break the gallery layout long before
   * it troubled the database.
   *
   * @return the asset as the gallery should now show it
   */
  @Transactional
  public FileInfo updateCaption(Long fileId, String caption) {
    User currentUser = userContext.getCurrentUser();
    FileMetadata metadata =
        metadataRepository
            .findByIdAndUserId(fileId, currentUser.getId())
            .orElseThrow(() -> new ResourceNotFoundException("File", "id", fileId));

    String normalized = caption == null || caption.isBlank() ? null : caption.strip();
    if (normalized != null && normalized.length() > MAX_CAPTION_LENGTH) {
      throw new ValidationException(
          "Caption must be at most " + MAX_CAPTION_LENGTH + " characters");
    }

    metadata.setCaption(normalized);
    metadataRepository.save(metadata);

    return convertToFileInfo(metadata);
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

  private static String formatBytes(long size) {
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

  /**
   * Compares every key in the S3 bucket against the paths recorded in the DB and deletes any key
   * that has no corresponding row. Pass {@code dryRun=true} to log what would be deleted without
   * touching MinIO — always run a dry-run first to sanity-check the numbers.
   *
   * <p><b>The known-key set must cover every table that owns bucket keys, not just {@code
   * file_metadata}.</b> It did not, and it cost real data: slideshow narration audio lives in
   * {@code slideshow_recordings.audio_path}, which this swept read as unowned, so one run of this
   * endpoint deleted every commentary recorded before it — the rows survived, pointing at keys that
   * no longer existed, which is why old commentaries later 404'd. The AAC siblings are derived
   * rather than stored, so they are named here the same way the serving path names them.
   *
   * <p>{@code tus-uploads/} is skipped outright: those objects are owned by tusd and have no DB row
   * at all until the post-finish hook moves them, so "no row" there means "in flight", not
   * "garbage". {@link com.oglimmer.photoupload.service.RetentionService} reaps that prefix on a
   * grace period instead, which is the only safe way to judge it.
   *
   * <p>Deliberately NOT {@code @Transactional}: the method lists whole buckets over the network,
   * and a transaction here pinned a pool connection for the entire sweep. The reads are point
   * queries that need no shared snapshot.
   */
  public Map<String, Object> purgeOrphanedS3Objects(boolean dryRun) {
    ObjectStorageService s3 = objectStorage;

    int totalBucketKeys = 0;
    int knownDbPaths = 0;
    int orphaned = 0;
    int deleted = 0;
    int failed = 0;
    int skippedInFlight = 0;

    // One pass per backend. A key is only garbage relative to the bucket it was found in: two
    // backends can legitimately hold the same key for different albums, so comparing one bucket's
    // listing against every album's paths would spare real orphans and, worse, delete live objects.
    for (StorageBackend backend : storageBackendRepository.findAll()) {
      Set<String> knownPaths =
          new HashSet<>(metadataRepository.findStoredPathsByStorageBackend(backend.getId()));
      knownPaths.addAll(
          slideshowRecordingRepository.findAudioPathsByStorageBackend(backend.getId()));
      for (String audioFilename :
          slideshowRecordingRepository.findAudioFilenamesByStorageBackend(backend.getId())) {
        knownPaths.add(StoragePaths.audioAacKey(audioFilename));
      }

      BackendStorage storage;
      List<String> bucketKeys;
      try {
        storage = s3.forBackend(backend);
        bucketKeys = storage.listKeys();
      } catch (Exception e) {
        // A user's endpoint being down must not abort the sweep of every other backend.
        failed++;
        log.warn(
            "Skipping orphan sweep of storage backend {} ({}): {}",
            backend.getId(),
            backend.getName(),
            e.getMessage());
        continue;
      }

      totalBucketKeys += bucketKeys.size();
      knownDbPaths += knownPaths.size();

      for (String key : bucketKeys) {
        if (key.startsWith(StoragePaths.TUS_UPLOADS_PREFIX)
            || StoragePaths.isEnhancePreviewKey(key)) {
          // Both are in flight by nature: a TUS upload the hook has not finalised, or an enhance
          // preview (D82) the owner has not decided on. Neither is referenced from a row.
          skippedInFlight++;
          continue;
        }
        if (!knownPaths.contains(key)) {
          orphaned++;
          if (dryRun) {
            log.info("Dry run — orphaned S3 object on backend {}: {}", backend.getId(), key);
          } else {
            try {
              storage.delete(key);
              deleted++;
              log.info("Deleted orphaned S3 object on backend {}: {}", backend.getId(), key);
            } catch (Exception e) {
              failed++;
              log.warn("Failed to delete orphaned S3 object {}: {}", key, e.getMessage());
            }
          }
        }
      }
    }

    log.info(
        "S3 orphan purge complete (dryRun={}): {} bucket keys, {} known DB paths, {} skipped in-flight, {} orphaned, {} deleted, {} failed",
        dryRun,
        totalBucketKeys,
        knownDbPaths,
        skippedInFlight,
        orphaned,
        deleted,
        failed);

    Map<String, Object> result = new HashMap<>();
    result.put("dryRun", dryRun);
    result.put("totalBucketKeys", totalBucketKeys);
    result.put("knownDbPaths", knownDbPaths);
    result.put("skippedInFlight", skippedInFlight);
    result.put("orphaned", orphaned);
    result.put("deleted", deleted);
    result.put("failed", failed);
    return result;
  }

  private void deleteS3Objects(FileMetadata metadata) {
    BackendStorage s3 = objectStorage.forFile(metadata);
    deleteS3Key(s3, metadata.getFilePath(), "original");
    deleteS3Key(s3, metadata.getThumbnailPath(), "thumbnail");
    deleteS3Key(s3, metadata.getMediumPath(), "medium");
    deleteS3Key(s3, metadata.getLargePath(), "large");
    deleteS3Key(s3, metadata.getTranscodedVideoPath(), "transcoded");
    // Not a column: an un-decided enhance preview (D82) lives at a deterministic key.
    deleteS3Key(s3, StoragePaths.derivativeEnhancePreviewKey(metadata.getId()), "enhance preview");
  }

  private void deleteS3Key(BackendStorage s3, String key, String label) {
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

  /**
   * Best-effort storage cleanup for every file in an album. Used by {@link
   * AlbumService#deleteAlbum(Long)} so a 5000-photo album doesn't fan out into 25 000 synchronous
   * S3 calls per request. Behaviour matches the per-file path:
   *
   * <ul>
   *   <li>Files whose {@code file_path} is also referenced by rows in another album are skipped
   *       entirely (cross-album dedupe via {@code duplicateAlbum} shares all five storage paths as
   *       a unit).
   *   <li>Keys are batched via {@link BackendStorage#deleteKeys(java.util.Collection)} (1000 keys
   *       per call); per-key failures are logged, not thrown.
   * </ul>
   *
   * <p>Does NOT touch the database. The caller deletes the rows first and calls this afterwards
   * with the entities it loaded beforehand, so a storage failure can never leave rows pointing at
   * bytes that are gone; the reverse — bytes outliving their rows — is what {@link
   * #purgeOrphanedS3Objects(boolean)} exists for.
   */
  public void bulkDeleteAlbumStorage(
      Long albumId,
      StorageBackend backend,
      List<FileMetadata> files,
      List<SlideshowRecording> recordings) {
    List<String> audioKeysToDelete = new ArrayList<>();
    if (recordings != null) {
      // Narration is album-scoped too, and its rows go with the album's SQL cascade — so the keys
      // have to be named here or they are never freed: the nightly orphan sweep only reads
      // originals/, and only the manual admin purge would ever find a stray audio/ object.
      for (SlideshowRecording recording : recordings) {
        addIfNotBlank(audioKeysToDelete, recording.getAudioPath());
        if (recording.getAudioFilename() != null) {
          addIfNotBlank(audioKeysToDelete, StoragePaths.audioAacKey(recording.getAudioFilename()));
        }
      }
    }
    if (!audioKeysToDelete.isEmpty()) {
      objectStorage.forBackend(backend).deleteKeys(audioKeysToDelete);
    }

    if (files == null || files.isEmpty()) {
      return;
    }

    // Cross-album shared paths: skip physical deletion for those rows.
    Set<String> originalPaths =
        files.stream()
            .map(FileMetadata::getFilePath)
            .filter(p -> p != null && !p.isBlank())
            .collect(Collectors.toSet());
    Set<String> sharedPaths =
        originalPaths.isEmpty()
            ? Set.of()
            : new HashSet<>(
                metadataRepository.findFilePathsSharedOutsideAlbum(albumId, originalPaths));

    List<String> s3KeysToDelete = new ArrayList<>(files.size() * 5);
    int sharedSkipped = 0;
    for (FileMetadata f : files) {
      if (f.getFilePath() != null && sharedPaths.contains(f.getFilePath())) {
        sharedSkipped++;
        log.debug(
            "Skipping physical deletion for {} — file_path shared with another album",
            f.getStoredFilename());
        continue;
      }
      addIfNotBlank(s3KeysToDelete, f.getFilePath());
      addIfNotBlank(s3KeysToDelete, f.getThumbnailPath());
      addIfNotBlank(s3KeysToDelete, f.getMediumPath());
      addIfNotBlank(s3KeysToDelete, f.getLargePath());
      addIfNotBlank(s3KeysToDelete, f.getTranscodedVideoPath());
      s3KeysToDelete.add(StoragePaths.derivativeEnhancePreviewKey(f.getId()));
    }

    if (!s3KeysToDelete.isEmpty()) {
      objectStorage.forBackend(backend).deleteKeys(s3KeysToDelete);
    }
    log.info(
        "Album {} storage purge: {} files processed, {} S3 keys batched, {} cross-album shared skipped",
        albumId,
        files.size(),
        s3KeysToDelete.size(),
        sharedSkipped);
  }

  private static void addIfNotBlank(List<String> sink, String value) {
    if (value != null && !value.isBlank()) {
      sink.add(value);
    }
  }

  public void deleteFile(Long fileId) {
    // Owner-scoped, like every other single-file mutation here. A row that belongs to somebody
    // else answers the same 404 as a row that does not exist.
    User currentUser = userContext.getCurrentUser();
    FileMetadata metadata =
        metadataRepository
            .findByIdAndUserId(fileId, currentUser.getId())
            .orElseThrow(() -> new ResourceNotFoundException("File", "id", fileId));

    // Check if physical files are shared with other FileMetadata records
    boolean isShared = metadataRepository.countByFilePath(metadata.getFilePath()) > 1;

    if (isShared) {
      log.info(
          "Skipping physical file deletion for {} — shared with other records",
          metadata.getStoredFilename());
    } else {
      deleteS3Objects(metadata);
    }

    // Delete metadata (cascade will delete image_tags)
    metadataRepository.delete(metadata);
  }

  /**
   * Put {@code tagName} on one file. Any real tag ends the holding pen (D79): if the file carried
   * {@code hidden}, that row goes in the same transaction. {@code hidden} itself cannot be added by
   * hand — it is the state of a file with no other tag, not a tag one assigns.
   */
  @Transactional
  public List<String> addTagToFile(Long fileId, String tagName) {
    requireAssignable(tagName);
    User currentUser = userContext.getCurrentUser();
    FileMetadata metadata =
        metadataRepository
            .findByIdAndUserId(fileId, currentUser.getId())
            .orElseThrow(() -> new ResourceNotFoundException("File", "id", fileId));

    Tag tag =
        tagRepository
            .findByUserAndName(currentUser, tagName)
            .orElseThrow(() -> new ResourceNotFoundException("Tag", "name", tagName));

    // Enforce album's enabled-tags list (system tags are always allowed)
    if (!SystemTags.isSystemTag(tagName)
        && !albumEnabledTagRepository.existsByAlbumIdAndTagId(
            metadata.getAlbum().getId(), tag.getId())) {
      throw new ValidationException("Tag '" + tagName + "' is not enabled for this album");
    }

    // Check if tag already exists for this file
    if (imageTagRepository.findByFileMetadataIdAndTagId(fileId, tag.getId()).isPresent()) {
      throw new DuplicateResourceException("File already has this tag");
    }

    ImageTag imageTag = new ImageTag();
    imageTag.setFileMetadata(metadata);
    imageTag.setTag(tag);
    imageTagRepository.save(imageTag);

    log.info("Added tag '{}' to file: {}", tagName, metadata.getStoredFilename());

    // The file has a real tag now, so it leaves the holding pen (D79).
    tagRepository
        .findByUserAndName(currentUser, SystemTags.HIDDEN)
        .flatMap(hidden -> imageTagRepository.findByFileMetadataIdAndTagId(fileId, hidden.getId()))
        .ifPresent(
            row -> {
              imageTagRepository.delete(row);
              log.info("Took '{}' off file: {}", SystemTags.HIDDEN, metadata.getStoredFilename());
            });

    return currentTagNames(fileId);
  }

  /**
   * Take {@code tagName} off one file. Taking the last real tag off puts {@code hidden} back on in
   * the same transaction (D79), so the file never sits bare on a published album. Taking {@code
   * hidden} itself off is allowed only while the file has another tag (a state older data can be
   * in); as the only tag it would come straight back, so that is refused with a message saying how
   * to publish the photo instead.
   */
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

    if (SystemTags.HIDDEN.equals(tagName)
        && imageTagRepository.findByFileMetadataId(fileId).size() <= 1) {
      throw new ValidationException(HIDDEN_IS_THE_ONLY_TAG);
    }

    imageTagRepository.delete(imageTag);
    log.info("Removed tag '{}' from file: {}", tagName, metadata.getStoredFilename());

    List<String> remaining = currentTagNames(fileId);
    if (remaining.isEmpty()) {
      // Last real tag gone: back into the holding pen (D79).
      Long hiddenId = systemTagProvisioner.ensureTag(currentUser, SystemTags.HIDDEN);
      addTagRowIfMissing(metadata, hiddenId, SystemTags.HIDDEN);
      remaining = currentTagNames(fileId);
    }
    return remaining;
  }

  /** The file's tag names as the database has them right now. */
  private List<String> currentTagNames(Long fileId) {
    return imageTagRepository.findByFileMetadataId(fileId).stream()
        .map(it -> it.getTag().getName())
        .collect(Collectors.toList());
  }

  /**
   * Add {@code tagName} to every file in the album, skipping files that already carry it. Every
   * file that ends up with the tag also leaves the holding pen (D79), so "add {@code all} to every
   * photo" is the one-click publish. Returns the number of files actually changed. {@code hidden}
   * cannot be added this way, see {@link #addTagToFile}.
   */
  @Transactional
  public int addTagToAllFilesInAlbum(Long albumId, String tagName) {
    requireAssignable(tagName);
    User currentUser = userContext.getCurrentUser();
    Album album = requireOwnedAlbum(currentUser, albumId);
    Tag tag = resolveTagForBulkOperation(currentUser, tagName);

    // Enforce album's enabled-tags list (system tags are always allowed)
    if (!SystemTags.isSystemTag(tagName)
        && !albumEnabledTagRepository.existsByAlbumIdAndTagId(album.getId(), tag.getId())) {
      throw new ValidationException("Tag '" + tagName + "' is not enabled for this album");
    }

    int changed = 0;
    for (FileMetadata metadata : albumFilesWithTags(album, currentUser)) {
      List<ImageTag> imageTags = metadata.getImageTags();
      boolean touched = false;
      if (imageTags.stream().noneMatch(it -> it.getTag().getId().equals(tag.getId()))) {
        ImageTag imageTag = new ImageTag();
        imageTag.setFileMetadata(metadata);
        imageTag.setTag(tag);
        imageTagRepository.save(imageTag);
        imageTags.add(imageTag);
        touched = true;
      }
      // A real tag ends the holding pen — also on a file that already carried this tag next to
      // `hidden`, a state only older data can be in.
      if (removeTagRowFromFetchedFile(metadata, FileStorageService::isHiddenRow)) {
        touched = true;
      }
      if (touched) {
        changed++;
      }
    }

    log.info(
        "Added tag '{}' to {} file(s) in album '{}' for user: {}",
        tagName,
        changed,
        album.getName(),
        currentUser.getEmail());
    return changed;
  }

  /**
   * Remove {@code tagName} from every file in the album, skipping files that don't carry it. A file
   * left with no tag goes back into the holding pen (D79). Removing {@code hidden} itself touches
   * only the files that have another tag; where it is the only tag it would come straight back, so
   * those are skipped rather than churned. Returns the number of files actually changed.
   */
  @Transactional
  public int removeTagFromAllFilesInAlbum(Long albumId, String tagName) {
    User currentUser = userContext.getCurrentUser();
    Album album = requireOwnedAlbum(currentUser, albumId);
    Tag tag =
        tagRepository
            .findByUserAndName(currentUser, tagName)
            .orElseThrow(() -> new ResourceNotFoundException("Tag", "name", tagName));
    boolean removingHidden = SystemTags.HIDDEN.equals(tagName);

    int changed = 0;
    Tag hidden = null; // resolved on first need, so a sweep that empties nothing creates nothing
    for (FileMetadata metadata : albumFilesWithTags(album, currentUser)) {
      List<ImageTag> imageTags = metadata.getImageTags();
      if (removingHidden && imageTags.stream().allMatch(FileStorageService::isHiddenRow)) {
        continue;
      }
      boolean removed =
          removeTagRowFromFetchedFile(metadata, it -> it.getTag().getId().equals(tag.getId()));
      if (!removed) {
        continue;
      }
      changed++;
      if (imageTags.isEmpty()) {
        if (hidden == null) {
          hidden = resolveTagForBulkOperation(currentUser, SystemTags.HIDDEN);
        }
        ImageTag row = new ImageTag();
        row.setFileMetadata(metadata);
        row.setTag(hidden);
        imageTagRepository.save(row);
        imageTags.add(row);
      }
    }

    log.info(
        "Removed tag '{}' from {} file(s) in album '{}' for user: {}",
        tagName,
        changed,
        album.getName(),
        currentUser.getEmail());
    return changed;
  }

  private Album requireOwnedAlbum(User user, Long albumId) {
    return albumRepository
        .findByUserAndId(user, albumId)
        .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId));
  }

  private List<FileMetadata> albumFilesWithTags(Album album, User user) {
    return metadataRepository.findByAlbumIdAndUserIdWithTagsOrderByDisplayOrderAsc(
        album.getId(), user.getId());
  }

  /**
   * Drop a tag row from a file whose {@code imageTags} collection is initialized (the bulk methods
   * JOIN FETCH it). The removal has to go through the collection: it is mapped {@code
   * CascadeType.ALL} + {@code orphanRemoval}, so a row deleted straight through {@code
   * imageTagRepository} is re-persisted by the cascade at flush time and the delete is silently
   * lost. Removing from the collection lets orphanRemoval issue the DELETE. Returns whether the
   * file carried a matching row.
   *
   * <p>The single-file {@link #addTagToFile}/{@link #removeTagFromFile} path is not affected — it
   * loads the file without the fetch join, so the collection stays uninitialized and no cascade
   * runs over it.
   */
  private boolean removeTagRowFromFetchedFile(FileMetadata metadata, Predicate<ImageTag> match) {
    Optional<ImageTag> row = metadata.getImageTags().stream().filter(match).findFirst();
    if (row.isEmpty()) {
      return false;
    }
    metadata.getImageTags().remove(row.get());
    log.debug(
        "Removed tag '{}' from file: {}",
        row.get().getTag().getName(),
        metadata.getStoredFilename());
    return true;
  }

  /**
   * Look up the tag for a bulk add. System tags are lazily created (same as {@code all} on upload)
   * because a user may never have touched them before; any other tag must already exist.
   */
  /**
   * {@code hidden} is not assigned, it is derived: a file carries it exactly while it has no other
   * tag (D79). Adding it by hand would either be a no-op or create the "hidden next to a real tag"
   * state the rule exists to remove, so both single and bulk adds refuse it.
   */
  private static void requireAssignable(String tagName) {
    if (SystemTags.HIDDEN.equals(tagName)) {
      throw new ValidationException(
          "'hidden' is set automatically while a photo has no other tag. "
              + "Remove the photo's tags to hide it again.");
    }
  }

  private static boolean isHiddenRow(ImageTag row) {
    return SystemTags.HIDDEN.equals(row.getTag().getName());
  }

  private Tag resolveTagForBulkOperation(User user, String tagName) {
    Optional<Tag> existing = tagRepository.findByUserAndName(user, tagName);
    if (existing.isPresent()) {
      return existing.get();
    }
    if (!SystemTags.isSystemTag(tagName)) {
      throw new ResourceNotFoundException("Tag", "name", tagName);
    }
    return tagRepository.getReferenceById(systemTagProvisioner.ensureTag(user, tagName));
  }

  @Transactional
  public void reorderFiles(List<Long> fileIds) {
    // Validate that every id exists AND belongs to the caller, in a single query. An id from
    // another user's album is reported exactly like an unknown id.
    User currentUser = userContext.getCurrentUser();
    List<Long> existingIds =
        metadataRepository.findExistingIdsForUser(fileIds, currentUser.getId());
    if (existingIds.size() != new HashSet<>(fileIds).size()) {
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

    // Phase 6 / Gap 4-finish: handle a purged original. After the retention CronJob runs, the
    // original may be NULL while derivatives stay. Two cases:
    //   - Caller explicitly asked for ?size=original on an image (or no transcoded version exists
    //     for a video) → 410 Gone, since the bytes are intentionally and permanently absent.
    //   - Caller didn't ask for a specific size → fall back to the largest derivative we have.
    //     This keeps the gallery and Lightbox working without per-component awareness of purge.
    if (filePath == null) {
      if (isOriginalRequested) {
        throw new ResourceGoneException(
            "Original was purged by retention policy. Request a derivative size instead.");
      }
      String fallback = pickLargestDerivative(metadata);
      if (fallback == null) {
        throw new ResourceGoneException(
            "Original was purged and no derivative is available to fall back to.");
      }
      filePath = fallback;
      // Derivatives are always JPEG/MP4; mime adjustment below mirrors that.
      if (fallback.equals(metadata.getTranscodedVideoPath())) {
        isServingTranscodedVideo = true;
      } else {
        // thumb/medium/large are all JPEG.
        mimeType = "image/jpeg";
      }
    }

    // Adjust MIME type based on what we're actually serving
    if (isServingThumbnail && isVideo) {
      // Video thumbnails are JPEG images
      mimeType = "image/jpeg";
    } else if (isServingTranscodedVideo) {
      // Transcoded videos are always MP4
      mimeType = "video/mp4";
    }

    // Every row holds object keys (originals/... or derivatives/...). A path that is not one is a
    // pre-migration leftover the api pod has no way to read — say so rather than 500.
    if (!StoragePaths.isS3Key(filePath)) {
      throw new ResourceGoneException(
          "This asset is on legacy local storage and can no longer be served.");
    }

    return new FileServeInfo(
        mimeType,
        metadata.getChecksum(),
        metadata.getUploadedAt(),
        metadata.getStoredFilename(),
        metadata.getProcessingStatus(),
        derivativeReady,
        filePath,
        metadata.getAlbum() != null ? metadata.getAlbum().getId() : null);
  }

  /**
   * Pick the best available derivative when the original is gone. Preference order: large → medium
   * → thumbnail (for images, plus same fallback for video stills); transcoded video is preferred
   * over the image still for videos. Returns null if the row truly has no usable derivative —
   * caller should 410.
   */
  private String pickLargestDerivative(FileMetadata metadata) {
    boolean isVideo = metadata.getMimeType() != null && metadata.getMimeType().startsWith("video/");
    if (isVideo && metadata.getTranscodedVideoPath() != null) {
      return metadata.getTranscodedVideoPath();
    }
    if (metadata.getLargePath() != null) {
      return metadata.getLargePath();
    }
    if (metadata.getMediumPath() != null) {
      return metadata.getMediumPath();
    }
    if (metadata.getThumbnailPath() != null) {
      return metadata.getThumbnailPath();
    }
    return null;
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
   * Ensure the user's configured new-asset tag exists, and return its id. Creation runs in its own
   * transaction (see {@link SystemTagProvisioner}) so that two concurrent uploads by a brand-new
   * user cannot roll each other's file_metadata insert back.
   */
  private Long ensureNewAssetTagExists(User user) {
    return systemTagProvisioner.ensureTag(user, user.getNewAssetTag());
  }

  /**
   * Put one tag row on a file, without any checks or side effects. Used for the user's new-asset
   * tag on upload — a per-user setting (D70): {@code hidden} keeps the asset out of every public
   * listing until its owner has looked at it, {@code all} is the D68 behaviour of publishing on
   * arrival — and for putting {@code hidden} back when a file loses its last real tag (D79).
   */
  private void addTagRowIfMissing(FileMetadata metadata, Long tagId, String tagName) {
    // getReferenceById, not a fresh lookup: the row may have been committed by a concurrent
    // request after this transaction took its REPEATABLE READ snapshot, so a SELECT could miss it.
    Tag tag = tagRepository.getReferenceById(tagId);

    // Check if the tag already exists for this file
    if (imageTagRepository.findByFileMetadataIdAndTagId(metadata.getId(), tagId).isEmpty()) {
      ImageTag imageTag = new ImageTag();
      imageTag.setFileMetadata(metadata);
      imageTag.setTag(tag);
      imageTagRepository.save(imageTag);
      log.info("Added '{}' to file: {}", tagName, metadata.getStoredFilename());
    }
  }

  /**
   * Enqueue a rotate-90-CCW job for the given asset (Phase 4.5, D17). The actual ImageMagick work
   * runs on the worker pod via {@link FileProcessingService#rotateAndReprocess(Long)} — the api pod
   * no longer has the thumbnailer beans. Returns immediately so the controller can answer 202
   * Accepted; the UI polls {@code GET /api/assets/{id}/status} until DONE.
   *
   * <p>Same-TX guarantee: the {@code FileMetadata} status flip and the {@code processing_jobs} row
   * insert commit together, so the dispatcher never sees a queued job for an asset whose row still
   * says DONE (which would race the gallery's read-after-rotate).
   */
  public void rotateImageLeft(Long fileId) {
    User currentUser = userContext.getCurrentUser();
    FileMetadata metadata = requireRewritableImage(fileId, currentUser, "rotated");

    log.info(
        "📸 Enqueuing rotate-left for asset {} ({}, current rotation {}°) by user {}",
        fileId,
        metadata.getOriginalName(),
        metadata.getRotation() != null ? metadata.getRotation() : 0,
        currentUser.getEmail());

    transactionTemplate.executeWithoutResult(
        status -> resetAndEnqueue(fileId, JobType.ROTATE_LEFT));
  }

  /**
   * Enqueue a one-tap auto-enhance (D81) for the given asset. Same contract as {@link
   * #rotateImageLeft(Long)}: 202 now, the worker rewrites the original and the derivatives via
   * {@link FileProcessingService#enhanceAndReprocess(Long)}, the client polls the status and then
   * reloads because the {@code publicToken} changes. Like rotate it is irreversible — there is no
   * copy of the un-enhanced original — and a second run compounds on the first.
   */
  public void enhanceImage(Long fileId) {
    User currentUser = userContext.getCurrentUser();
    FileMetadata metadata = requireRewritableImage(fileId, currentUser, "enhanced");

    log.info(
        "✨ Enqueuing enhance for asset {} ({}) by user {}",
        fileId,
        metadata.getOriginalName(),
        currentUser.getEmail());

    transactionTemplate.executeWithoutResult(status -> resetAndEnqueue(fileId, JobType.ENHANCE));
  }

  /**
   * Enqueue the look-before-you-leap half of an enhance (D82): the worker computes the enhanced
   * image at LARGE size into {@link StoragePaths#derivativeEnhancePreviewKey(Long)} and nothing
   * else changes. The client waits on the status endpoint, fetches the preview through {@link
   * #openEnhancePreview(Long)}, and then either calls {@link #enhanceImage(Long)} or {@link
   * #discardEnhancePreview(Long)}.
   */
  public void enqueueEnhancePreview(Long fileId) {
    User currentUser = userContext.getCurrentUser();
    FileMetadata metadata = requireRewritableImage(fileId, currentUser, "enhanced");

    log.info(
        "👀 Enqueuing enhance preview for asset {} ({}) by user {}",
        fileId,
        metadata.getOriginalName(),
        currentUser.getEmail());

    transactionTemplate.executeWithoutResult(
        status -> resetAndEnqueue(fileId, JobType.ENHANCE_PREVIEW));
  }

  /**
   * The bytes of a finished enhance preview (D82), or 404 when there is none — not yet built,
   * already decided, or never asked for. Owner-scoped like every other single-file read; the
   * preview is never reachable through a public token.
   */
  public ResponseInputStream<GetObjectResponse> openEnhancePreview(Long fileId) {
    User currentUser = userContext.getCurrentUser();
    FileMetadata metadata =
        metadataRepository
            .findByIdAndUserId(fileId, currentUser.getId())
            .orElseThrow(() -> new ResourceNotFoundException("File", "id", fileId));
    String key = StoragePaths.derivativeEnhancePreviewKey(fileId);
    BackendStorage s3 = objectStorage.forFile(metadata);
    if (!s3.exists(key)) {
      throw new ResourceNotFoundException("Enhance preview", "file id", fileId);
    }
    return s3.openStream(key);
  }

  /** Declining (D82): drop the preview key. Idempotent; a missing key is not an error. */
  public void discardEnhancePreview(Long fileId) {
    User currentUser = userContext.getCurrentUser();
    FileMetadata metadata =
        metadataRepository
            .findByIdAndUserId(fileId, currentUser.getId())
            .orElseThrow(() -> new ResourceNotFoundException("File", "id", fileId));
    deleteS3Key(
        objectStorage.forFile(metadata),
        StoragePaths.derivativeEnhancePreviewKey(fileId),
        "enhance preview");
    log.info("🗑️  Discarded enhance preview for asset {} by user {}", fileId, currentUser.getEmail());
  }

  /**
   * The checks shared by every job that rewrites an image's stored bytes in place (rotate,
   * enhance): the asset must be the caller's, must be an image, and must have some S3-backed
   * source the worker can read.
   *
   * @param verb past participle for the error copy ("rotated", "enhanced")
   */
  private FileMetadata requireRewritableImage(Long fileId, User currentUser, String verb) {
    FileMetadata metadata =
        metadataRepository
            .findByIdAndUserId(fileId, currentUser.getId())
            .orElseThrow(() -> new ResourceNotFoundException("File", "id", fileId));

    if (!MimeTypePredicates.isImageFile(metadata.getMimeType())) {
      throw new ValidationException("Only image files can be " + verb);
    }
    // Original may have been purged by retention — that's fine. The worker will fall back to the
    // largest available derivative as the source (output is bounded by LARGE=2400px anyway, so
    // feeding `large` produces pixel-equivalent derivatives to feeding the original). What we
    // cannot tolerate is a legacy local-disk filePath that has neither been migrated nor purged —
    // the worker pod has no PVC mount, so it cannot read those bytes.
    if (metadata.getFilePath() != null && !StoragePaths.isS3Key(metadata.getFilePath())) {
      throw new ValidationException(
          "This asset is on legacy local storage. Migrate to object storage before it can be "
              + verb
              + ".");
    }
    // No usable source at all — original purged AND no S3-backed derivative either. Should be
    // unreachable in practice (every DONE asset has at least a thumbnail) but explicit rejection
    // beats a confusing worker-side failure.
    if (metadata.getFilePath() == null
        && !StoragePaths.isS3Key(metadata.getLargePath())
        && !StoragePaths.isS3Key(metadata.getMediumPath())
        && !StoragePaths.isS3Key(metadata.getThumbnailPath())) {
      throw new ResourceGoneException(
          "Original was purged and no derivative is available to be " + verb + ".");
    }
    return metadata;
  }

  /**
   * Inside the caller's transaction: put the row back to QUEUED with a clean slate and insert the
   * job in the same unit of work, so the dispatcher never sees a queued job for an asset whose row
   * still says DONE.
   */
  /**
   * Refuse to pile more work onto a queue that is already at the backpressure threshold.
   *
   * <p>Guards the re-processing jobs only — the ones a user asks for on assets that are already
   * stored. Rejecting one costs nothing: the asset keeps its current derivatives and the client
   * can retry. The ingest jobs are deliberately not guarded here, because by the time a PROCESS
   * job is enqueued the bytes are already in object storage and refusing would strand an asset
   * with no derivatives at all — those paths refuse earlier instead, before the body is read
   * ({@code UploadBackpressureFilter}) or before tusd allocates the upload ({@code
   * TusHookService.handlePreCreate}), against this same threshold.
   *
   * <p>What this stops is the stampede: one bulk enhance or rotate over a large album used to
   * enqueue a job per photo in a single click, and each of those pulls the original onto a
   * worker's local disk. Two workers cope with the queue; the nodes under them did not
   * (incident 2026-09-06).
   */
  private void requireQueueHeadroom(JobType jobType) {
    int threshold = jobsProperties.getBackpressure().getQueueDepthThreshold();
    long depth = queueDepthService.getDepth();
    if (depth >= threshold) {
      log.info("Rejecting {} — queue depth {} >= threshold {}", jobType, depth, threshold);
      throw new JobQueueSaturatedException(
          "Job queue depth " + depth + " is at the threshold of " + threshold);
    }
  }

  private void resetAndEnqueue(Long fileId, JobType jobType) {
    requireQueueHeadroom(jobType);
    FileMetadata locked =
        metadataRepository
            .findById(fileId)
            .orElseThrow(() -> new ResourceNotFoundException("File", "id", fileId));
    locked.setProcessingStatus(ProcessingStatus.QUEUED);
    locked.setProcessingAttempts(0);
    locked.setProcessingError(null);
    locked.setProcessingCompletedAt(null);
    metadataRepository.save(locked);
    jobEnqueueService.enqueue(fileId, jobType);
  }

  /**
   * Shared body of the admin backfill sweeps: one API-side transaction that flips every selected
   * row to QUEUED and inserts its job, so a crash mid-batch leaves no row "claimed but never
   * queued". The repository queries already skip rows with a live job, so re-invoking converges.
   *
   * @return how many jobs were enqueued — the caller pages by re-invoking until this is 0
   */
  private int enqueueSweep(String label, List<Long> ids, int cap, JobType jobType) {
    if (ids.isEmpty()) {
      log.info("{} sweep: no eligible assets", label);
      return 0;
    }
    log.info("{} sweep: enqueuing {} jobs (cap={})", label, ids.size(), cap);
    transactionTemplate.executeWithoutResult(
        status -> {
          for (Long id : ids) {
            resetAndEnqueue(id, jobType);
          }
        });
    log.info("{} sweep: enqueued {} jobs", label, ids.size());
    return ids.size();
  }

  /** {@code maxRows} clamped to what a single API call may enqueue. */
  private static int sweepCap(int maxRows) {
    return Math.max(1, Math.min(maxRows, 5000));
  }

  /**
   * Phase 4.5 follow-up — walk image-typed DONE rows that are missing one or more derivatives and
   * enqueue a {@code REGEN_THUMBNAILS} job for each. Used by the admin endpoint to mop up assets
   * stranded by an old processing failure or a vips-output gap that got past the markFailed
   * happy-path.
   *
   * <p>Single API-side TX: status flip + job insert per row, so a partial crash leaves no row in an
   * "I claimed it but never queued" state. Repository query already excludes assets with an active
   * job, so re-running the endpoint converges idempotently.
   *
   * <p>{@code maxRows} caps the batch size — caller pages by re-invoking. Default upstream is 500
   * which keeps any single tick of the worker's drain loop bounded too.
   *
   * @return number of jobs actually enqueued
   */
  public int enqueueRegenForMissingThumbnails(int maxRows) {
    int cap = sweepCap(maxRows);
    return enqueueSweep(
        "Regen-thumbnails",
        metadataRepository.findMissingThumbnailIds(cap),
        cap,
        JobType.REGEN_THUMBNAILS);
  }

  /**
   * Re-enqueues a full {@code PROCESS} job for every video whose transcode never produced an MP4.
   *
   * <p>Deliberately {@code PROCESS} and not {@code REGEN_THUMBNAILS}: the latter rejects anything
   * whose mime type isn't {@code image/*} and would mark these rows FAILED. {@code PROCESS} re-runs
   * the whole pipeline — transcode, thumbnail, EXIF — which redoes a little work that already
   * succeeded, but it is the only path that reaches {@code FfmpegService.transcodeVideo}.
   *
   * <p>Safe to re-run: {@code processFile} resets the row to PROCESSING and clears the previous
   * error, and every derivative key is derived from the asset id, so a second pass overwrites in
   * place rather than orphaning bytes.
   *
   * <p>Idempotent across calls — the query skips rows with a live job, and a row leaves the set as
   * soon as it has a transcode. Page by re-invoking until {@code enqueued == 0}.
   */
  public int enqueueReprocessForMissingVideoTranscodes(int maxRows) {
    int cap = sweepCap(maxRows);
    return enqueueSweep(
        "Video-transcode",
        metadataRepository.findMissingVideoTranscodeIds(cap),
        cap,
        JobType.PROCESS);
  }

  /**
   * Enqueues an {@code EXTRACT_CAPTURE_DATE} job per asset whose capture date still comes from the
   * old extractor. Photos stored a local wall clock as if it were UTC while videos stored a true
   * instant, so sorting an album by EXIF date sheared the two apart by the capture zone's UTC
   * offset; re-reading the original fixes the value in place.
   *
   * <p>Metadata-only on the worker side — no transcode, no thumbnail regeneration — so a full
   * backfill costs one object GET and one probe per asset.
   *
   * <p>Same shape as the other sweeps: single API-side TX per batch, repository query skips rows
   * with a live job, {@code maxRows} capped at 5000. Page by re-invoking until {@code enqueued ==
   * 0}. Retention-purged rows are never eligible — their originals are gone.
   *
   * @return number of jobs actually enqueued
   */
  public int enqueueCaptureDateReextract(int maxRows) {
    int cap = sweepCap(maxRows);
    return enqueueSweep(
        "Capture-date",
        metadataRepository.findStaleCaptureDateIds(cap),
        cap,
        JobType.EXTRACT_CAPTURE_DATE);
  }

  /**
   * Enqueues an {@code EXTRACT_GPS} job per asset that was never inspected for a capture location
   * ({@code gps_source IS NULL}) — the backfill for everything uploaded before the map filter
   * existed. Mirrors {@link #enqueueCaptureDateReextract}: metadata-only work, capped per call,
   * idempotent because the worker always stamps a source.
   *
   * @return how many jobs were enqueued; re-invoke until this returns 0
   */
  public int enqueueGpsExtract(int maxRows) {
    int cap = sweepCap(maxRows);
    return enqueueSweep("GPS", metadataRepository.findMissingGpsIds(cap), cap, JobType.EXTRACT_GPS);
  }
}
