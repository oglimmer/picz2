/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.AlbumEnabledTag;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ImageTag;
import com.oglimmer.photoupload.entity.SlideshowRecording;
import com.oglimmer.photoupload.entity.StorageBackend;
import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.DuplicateResourceException;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.model.AlbumInfo;
import com.oglimmer.photoupload.model.MapView;
import com.oglimmer.photoupload.repository.AlbumEnabledTagRepository;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.ImageTagRepository;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.repository.StorageBackendRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import com.oglimmer.photoupload.util.RandomTokens;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Profile(Profiles.API)
@Slf4j
@RequiredArgsConstructor
public class AlbumService {

  private final AlbumRepository albumRepository;
  private final FileMetadataRepository fileMetadataRepository;
  private final TagRepository tagRepository;
  private final ImageTagRepository imageTagRepository;
  private final AlbumEnabledTagRepository albumEnabledTagRepository;
  private final StorageBackendRepository storageBackendRepository;
  private final SlideshowRecordingRepository slideshowRecordingRepository;
  private final FileStorageService fileStorageService;
  private final UserContext userContext;
  private final SystemTagProvisioner systemTagProvisioner;

  /** First run of digits in a filename; compiled once, not once per comparison in a sort. */
  private static final Pattern FIRST_NUMBER = Pattern.compile("\\d+");

  @Transactional
  public AlbumInfo createAlbum(String name, String description) {
    return createAlbum(name, description, null);
  }

  /**
   * Creates an album on a chosen storage backend. {@code storageBackendId} null means the
   * instance's own storage; anything else must be a backend this user owns, checked here rather
   * than trusted from the request — otherwise one user could park albums in another's bucket.
   *
   * <p>The choice is permanent. Nothing in the API can move an album afterwards.
   */
  @Transactional
  public AlbumInfo createAlbum(String name, String description, Long storageBackendId) {
    User currentUser = userContext.getCurrentUser();

    // Check if album with this name already exists for this user
    if (albumRepository.findByUserAndName(currentUser, name).isPresent()) {
      throw new DuplicateResourceException("Album", "name", name);
    }

    Album album = new Album();
    album.setUser(currentUser);
    album.setStorageBackend(resolveBackend(currentUser, storageBackendId));
    album.setName(name);
    album.setDescription(description);
    album.setCreatedAt(Instant.now());
    album.setUpdatedAt(Instant.now());

    // 64 hex chars. The link stays dead until the owner publishes — see below.
    album.setShareToken(RandomTokens.hex(32));

    // Set display order to be at the end for this user
    Integer maxOrder = albumRepository.findMaxDisplayOrderByUser(currentUser);
    album.setDisplayOrder(maxOrder != null ? maxOrder + 1 : 0);

    // A share token exists from the start, but the link stays dead until the owner publishes.
    // Nothing about a brand-new album is ready for strangers, and this is the difference between
    // "has a link" and "is public".
    album.setPublished(false);

    album = albumRepository.save(album);
    log.info("Created album: {} for user: {} (unpublished)", name, currentUser.getEmail());

    return convertToAlbumInfo(album);
  }

  /**
   * The backend a new album may use: the system default, or one this user owns. A backend id
   * belonging to somebody else answers 404 rather than 403 — the caller has no business knowing
   * whether that id exists.
   */
  private StorageBackend resolveBackend(User user, Long storageBackendId) {
    if (storageBackendId == null) {
      return storageBackendRepository
          .findBySystemDefaultTrue()
          .orElseThrow(
              () ->
                  new IllegalStateException(
                      "No system default storage backend row — V44 migration did not run"));
    }
    return storageBackendRepository
        .findById(storageBackendId)
        .filter(
            b ->
                b.isSystemDefault()
                    || (b.getUser() != null && b.getUser().getId().equals(user.getId())))
        .orElseThrow(() -> new ResourceNotFoundException("StorageBackend", "id", storageBackendId));
  }

  /**
   * Turns public access to the album on or off.
   *
   * <p>Publishing opens the share link and lets the notifier mail this album's subscribers.
   * Unpublishing closes both again — existing subscriptions survive, they simply stop producing
   * mail while the album is dark.
   *
   * <p>{@code publishedAt} is stamped only the first time, so republishing an album does not
   * re-announce it to everyone who already heard about it.
   */
  @Transactional
  public AlbumInfo setPublished(Long albumId, boolean published) {
    User currentUser = userContext.getCurrentUser();
    Album album =
        albumRepository
            .findByUserAndId(currentUser, albumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId));

    album.setPublished(published);
    if (published && album.getPublishedAt() == null) {
      album.setPublishedAt(Instant.now());
    }
    album.setUpdatedAt(Instant.now());

    log.info(
        "{} album '{}' for user: {}",
        published ? "Published" : "Unpublished",
        album.getName(),
        currentUser.getEmail());
    return convertToAlbumInfo(album);
  }

  /**
   * Resolves a share token for public use, or throws the same not-found a bogus token throws.
   *
   * <p>Every anonymous read of an album goes through here. Deliberately indistinguishable from an
   * unknown token: a visitor holding an old link should not be able to tell "this album is hidden
   * right now" from "no such album", and the owner should not have their draft's existence
   * confirmed to whoever kept the URL.
   */
  @Transactional(readOnly = true)
  public Album requirePublishedByShareToken(String shareToken) {
    return albumRepository
        .findByShareTokenAndPublishedTrue(shareToken)
        .orElseThrow(() -> new ResourceNotFoundException("Album not found with share token"));
  }

  @Transactional(readOnly = true)
  public List<AlbumInfo> listAlbums() {
    User currentUser = userContext.getCurrentUser();
    return albumRepository.findByUserOrderByDisplayOrderAsc(currentUser).stream()
        .map(this::convertToAlbumInfo)
        .collect(Collectors.toList());
  }

  @Transactional(readOnly = true)
  public AlbumInfo getAlbum(Long albumId) {
    User currentUser = userContext.getCurrentUser();
    Album album =
        albumRepository
            .findByUserAndId(currentUser, albumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId));
    return convertToAlbumInfo(album);
  }

  @Transactional
  public AlbumInfo updateAlbum(
      Long albumId, String name, String description, Long storageBackendId) {
    User currentUser = userContext.getCurrentUser();
    Album album =
        albumRepository
            .findByUserAndId(currentUser, albumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId));

    // Check if new name conflicts with another album for this user
    if (name != null && !name.equals(album.getName())) {
      if (albumRepository.findByUserAndName(currentUser, name).isPresent()) {
        throw new DuplicateResourceException("Album", "name", name);
      }
      album.setName(name);
    }

    if (description != null) {
      album.setDescription(description);
    }

    if (storageBackendId != null && !storageBackendId.equals(album.getStorageBackend().getId())) {
      // Honouring this would mean copying every original and derivative to the new backend, and
      // until that finished the album would serve presigned URLs for objects that are not there.
      // Refusing is the honest answer; the user can create a new album on the other storage.
      throw new ValidationException("An album's storage cannot be changed after it is created.");
    }

    album.setUpdatedAt(Instant.now());

    log.info("Updated album: {} for user: {}", album.getName(), currentUser.getEmail());
    return convertToAlbumInfo(album);
  }

  /**
   * Stores (or clears) the album's default map view.
   *
   * <p>Pass null to clear, which puts the map back to framing every pin. A {@code view} that failed
   * {@link MapView#of} validation arrives here as null too, and clearing is the right answer for
   * garbage input: the alternative is persisting a region the owner cannot pan out of.
   */
  @Transactional
  public AlbumInfo updateMapView(Long albumId, MapView view) {
    User currentUser = userContext.getCurrentUser();
    Album album =
        albumRepository
            .findByUserAndId(currentUser, albumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId));

    album.setMapCenterLat(view == null ? null : view.centerLat());
    album.setMapCenterLng(view == null ? null : view.centerLng());
    album.setMapSpanLat(view == null ? null : view.spanLat());
    album.setMapSpanLng(view == null ? null : view.spanLng());
    album.setUpdatedAt(Instant.now());

    log.info(
        "{} map view for album {} (user {})",
        view == null ? "Cleared" : "Saved",
        album.getName(),
        currentUser.getEmail());
    return convertToAlbumInfo(album);
  }

  @Transactional
  public void deleteAlbum(Long albumId) {
    User currentUser = userContext.getCurrentUser();
    Album album =
        albumRepository
            .findByUserAndId(currentUser, albumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId));

    // Everything the storage cleanup will need, loaded while the rows still exist: the files, the
    // narration (its rows go with the album's SQL cascade) and the backend the bytes live in —
    // after the album row is gone, nothing can answer "which bucket" any more.
    List<FileMetadata> files =
        fileMetadataRepository.findByAlbumIdAndUserIdOrderByDisplayOrderAsc(
            albumId, currentUser.getId());
    List<SlideshowRecording> recordings =
        slideshowRecordingRepository.findByAlbumIdAndUserIdOrderByCreatedAtDesc(
            albumId, currentUser.getId());
    StorageBackend backend = album.getStorageBackend();

    // Rows first: a single bulk SQL delete for file_metadata (cascades image_tags,
    // processing_jobs, slideshow_recording_images via FK), then the album row (cascades the
    // remaining album-scoped tables). Replaces N+1 per-row JPA deletes that used to hit the
    // proxy timeout.
    fileMetadataRepository.bulkDeleteByAlbumId(albumId);
    albumRepository.bulkDeleteById(albumId);

    // Storage second, and never fatal. The old order — bytes first, then rows — meant a DB failure
    // left rows pointing at objects that were already gone. Bytes that outlive their rows are the
    // orphan sweep's job; rows that outlive their bytes are a 404 nothing repairs.
    try {
      fileStorageService.bulkDeleteAlbumStorage(albumId, backend, files, recordings);
    } catch (Exception e) {
      log.warn(
          "Album {} rows deleted but storage cleanup failed; orphan sweep will mop up: {}",
          albumId,
          e.toString());
    }

    log.info(
        "Deleted album '{}' with {} photos and {} recordings for user: {}",
        album.getName(),
        files.size(),
        recordings.size(),
        currentUser.getEmail());
  }

  // Removed: Images cannot move between albums

  @Transactional
  public int reorderFilesByFilename(Long albumId) {
    User currentUser = userContext.getCurrentUser();

    // Verify album exists and belongs to current user
    Album album =
        albumRepository
            .findByUserAndId(currentUser, albumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId));

    // Get all files in the album
    List<FileMetadata> files =
        fileMetadataRepository.findByAlbumIdAndUserIdOrderByDisplayOrderAsc(
            albumId, currentUser.getId());

    if (files.isEmpty()) {
      return 0;
    }

    // Sort files by extracting the first number from their filename
    files.sort(
        (f1, f2) -> {
          Long num1 = extractFirstNumber(f1.getOriginalName());
          Long num2 = extractFirstNumber(f2.getOriginalName());

          // If both have numbers, compare them
          if (num1 != null && num2 != null) {
            return num1.compareTo(num2);
          }
          // Files with numbers come before files without
          if (num1 != null) {
            return -1;
          }
          if (num2 != null) {
            return 1;
          }
          // Both without numbers, compare alphabetically
          return f1.getOriginalName().compareTo(f2.getOriginalName());
        });

    // Update display_order to sequential values (0, 1, 2, ...)
    for (int i = 0; i < files.size(); i++) {
      files.get(i).setDisplayOrder(i);
    }

    // Save all files
    fileMetadataRepository.saveAll(files);

    log.info("Reordered {} files in album {} by filename numbers", files.size(), album.getName());
    return files.size();
  }

  @Transactional
  public int reorderFilesByExifDate(Long albumId) {
    User currentUser = userContext.getCurrentUser();

    // Verify album exists and belongs to current user
    Album album =
        albumRepository
            .findByUserAndId(currentUser, albumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId));

    // Get all files in the album
    List<FileMetadata> files =
        fileMetadataRepository.findByAlbumIdAndUserIdOrderByDisplayOrderAsc(
            albumId, currentUser.getId());

    if (files.isEmpty()) {
      return 0;
    }

    // Sort files by EXIF DateTimeOriginal
    files.sort(
        (f1, f2) -> {
          Instant exif1 = f1.getExifDateTimeOriginal();
          Instant exif2 = f2.getExifDateTimeOriginal();

          // If both have EXIF dates, compare them (older first)
          if (exif1 != null && exif2 != null) {
            return exif1.compareTo(exif2);
          }
          // Files with EXIF dates come before files without
          if (exif1 != null) {
            return -1;
          }
          if (exif2 != null) {
            return 1;
          }
          // Both without EXIF dates, fall back to upload date
          return f1.getUploadedAt().compareTo(f2.getUploadedAt());
        });

    // Update display_order to sequential values (0, 1, 2, ...)
    for (int i = 0; i < files.size(); i++) {
      files.get(i).setDisplayOrder(i);
    }

    // Save all files
    fileMetadataRepository.saveAll(files);

    log.info("Reordered {} files in album {} by EXIF date", files.size(), album.getName());
    return files.size();
  }

  /**
   * Extract the first number from a filename
   *
   * @param filename The filename to parse
   * @return The first number found, or null if no number exists
   */
  private Long extractFirstNumber(String filename) {
    if (filename == null) {
      return null;
    }

    Matcher matcher = FIRST_NUMBER.matcher(filename);
    if (matcher.find()) {
      try {
        return Long.parseLong(matcher.group());
      } catch (NumberFormatException e) {
        // Number too large for Long, return null
        return null;
      }
    }
    return null;
  }

  @Transactional(readOnly = true)
  public AlbumInfo getAlbumByShareToken(String shareToken) {
    Album album = requirePublishedByShareToken(shareToken);

    // Return minimal info for public access (just name and id)
    AlbumInfo info = new AlbumInfo();
    info.setId(album.getId());
    info.setName(album.getName());
    info.setShareToken(album.getShareToken());
    // The saved map view ships to share-link visitors too — it is how the owner framed the album,
    // and they are the ones the framing is for. It reveals nothing the pins do not already.
    info.setMapCenterLat(album.getMapCenterLat());
    info.setMapCenterLng(album.getMapCenterLng());
    info.setMapSpanLat(album.getMapSpanLat());
    info.setMapSpanLng(album.getMapSpanLng());

    return info;
  }

  @Transactional
  public AlbumInfo duplicateAlbum(Long sourceAlbumId) {
    User currentUser = userContext.getCurrentUser();

    Album sourceAlbum =
        albumRepository
            .findByUserAndId(currentUser, sourceAlbumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", sourceAlbumId));

    // Create new album
    Album newAlbum = new Album();
    newAlbum.setUser(currentUser);
    // The copy reuses the source's storage keys rather than re-uploading the bytes, so it has to
    // stay on the source's backend. Putting it anywhere else would give every copied row a
    // file_path that resolves to nothing.
    newAlbum.setStorageBackend(sourceAlbum.getStorageBackend());
    newAlbum.setName(generateCopyName(currentUser, sourceAlbum.getName()));
    newAlbum.setDescription(sourceAlbum.getDescription());
    newAlbum.setCreatedAt(Instant.now());
    newAlbum.setUpdatedAt(Instant.now());

    newAlbum.setShareToken(RandomTokens.hex(32));

    // A copy is a draft, however public its source was. The duplicate is usually about to be
    // re-curated, and publishing it here would put a half-edited album behind a live link.
    newAlbum.setPublished(false);
    newAlbum.setPublishedAt(null);

    Integer maxOrder = albumRepository.findMaxDisplayOrderByUser(currentUser);
    newAlbum.setDisplayOrder(maxOrder != null ? maxOrder + 1 : 0);

    newAlbum = albumRepository.save(newAlbum);

    // Copy enabled tags from source album so the duplicate has the same tag configuration
    for (AlbumEnabledTag sourceEnabled :
        albumEnabledTagRepository.findByAlbumId(sourceAlbum.getId())) {
      AlbumEnabledTag copyEnabled = new AlbumEnabledTag();
      copyEnabled.setAlbum(newAlbum);
      copyEnabled.setTag(sourceEnabled.getTag());
      albumEnabledTagRepository.save(copyEnabled);
    }

    // Duplicate files
    List<FileMetadata> sourceFiles =
        fileMetadataRepository.findByAlbumIdAndUserIdOrderByDisplayOrderAsc(
            sourceAlbumId, currentUser.getId());

    // A duplicate is a new asset, so it gets the user's new-asset tag like any other (D70).
    // The duplicate is also created unpublished, so `hidden` here costs nothing and `all` on a
    // user who chose it keeps the D68 behaviour.
    Tag newAssetTag = ensureNewAssetTagExists(currentUser);

    for (FileMetadata source : sourceFiles) {
      FileMetadata copy = new FileMetadata();
      copy.setOriginalName(source.getOriginalName());
      copy.setStoredFilename(generateUniqueStoredFilename(source.getOriginalName()));
      copy.setFileSize(source.getFileSize());
      copy.setMimeType(source.getMimeType());
      copy.setChecksum(source.getChecksum());
      copy.setContentId(source.getContentId());
      copy.setWidth(source.getWidth());
      copy.setHeight(source.getHeight());
      copy.setDuration(source.getDuration());
      copy.setExifDateTimeOriginal(source.getExifDateTimeOriginal());
      copy.setExifDateSource(source.getExifDateSource());
      copy.setCaptureUtcOffsetSeconds(source.getCaptureUtcOffsetSeconds());
      // Capture location, or the duplicate falls out of the map filter and out of "by day &
      // region" — the coordinates live in the original's EXIF, which the copy shares but never
      // re-reads, so a dropped value here is a value nothing can recover.
      copy.setGpsLatitude(source.getGpsLatitude());
      copy.setGpsLongitude(source.getGpsLongitude());
      copy.setGpsSource(source.getGpsSource());
      copy.setRotation(source.getRotation());
      copy.setDisplayOrder(source.getDisplayOrder());
      copy.setUploadedAt(Instant.now());
      copy.setAlbum(newAlbum);

      // Share physical files
      copy.setFilePath(source.getFilePath());
      copy.setThumbnailPath(source.getThumbnailPath());
      copy.setMediumPath(source.getMediumPath());
      copy.setLargePath(source.getLargePath());
      copy.setTranscodedVideoPath(source.getTranscodedVideoPath());

      // …and share their processing state with them. The derivatives above already exist, and no
      // job is enqueued for a copy, so leaving the entity's QUEUED default in place would strand
      // every duplicated asset as "still processing" for good: the gallery greys it out, and every
      // admin backfill sweep filters on DONE and would skip it forever.
      copy.setProcessingStatus(source.getProcessingStatus());
      copy.setProcessingCompletedAt(source.getProcessingCompletedAt());

      // publicToken is auto-generated by @PrePersist
      copy = fileMetadataRepository.save(copy);

      ImageTag imageTag = new ImageTag();
      imageTag.setFileMetadata(copy);
      imageTag.setTag(newAssetTag);
      imageTagRepository.save(imageTag);
    }

    log.info(
        "Duplicated album '{}' -> '{}' with {} files for user: {}",
        sourceAlbum.getName(),
        newAlbum.getName(),
        sourceFiles.size(),
        currentUser.getEmail());

    return convertToAlbumInfo(newAlbum);
  }

  private String generateCopyName(User user, String originalName) {
    String candidateName = originalName + " (Copy)";
    if (albumRepository.findByUserAndName(user, candidateName).isEmpty()) {
      return candidateName;
    }

    for (int i = 2; ; i++) {
      candidateName = originalName + " (Copy " + i + ")";
      if (albumRepository.findByUserAndName(user, candidateName).isEmpty()) {
        return candidateName;
      }
    }
  }

  private String generateUniqueStoredFilename(String originalName) {
    String nameWithoutExtension = originalName;
    String extension = "";
    int dotIndex = originalName.lastIndexOf('.');
    if (dotIndex > 0) {
      nameWithoutExtension = originalName.substring(0, dotIndex);
      extension = originalName.substring(dotIndex + 1);
    }
    String uniqueSuffix =
        System.currentTimeMillis() + "-" + UUID.randomUUID().toString().substring(0, 9);
    return nameWithoutExtension + "-" + uniqueSuffix + "." + extension;
  }

  /**
   * Same race-safe path as the upload flow: creation happens in its own transaction so a duplicate
   * key from a concurrent request cannot roll this album duplication back. See {@link
   * SystemTagProvisioner}.
   */
  private Tag ensureNewAssetTagExists(User user) {
    Long tagId = systemTagProvisioner.ensureTag(user, user.getNewAssetTag());
    // Reference, not a lookup: a concurrently committed row is invisible to this transaction's
    // REPEATABLE READ snapshot, but the FK write only needs the id.
    return tagRepository.getReferenceById(tagId);
  }

  private AlbumInfo convertToAlbumInfo(Album album) {
    AlbumInfo info = new AlbumInfo();
    info.setId(album.getId());
    info.setName(album.getName());
    info.setDescription(album.getDescription());
    info.setCreatedAt(album.getCreatedAt());
    info.setUpdatedAt(album.getUpdatedAt());
    info.setDisplayOrder(album.getDisplayOrder());
    info.setShareToken(album.getShareToken());
    info.setPublished(album.isPublished());
    info.setPublishedAt(album.getPublishedAt());
    info.setMapCenterLat(album.getMapCenterLat());
    info.setMapCenterLng(album.getMapCenterLng());
    info.setMapSpanLat(album.getMapSpanLat());
    info.setMapSpanLng(album.getMapSpanLng());
    // Owner-facing only. getAlbumByShareToken builds its own minimal AlbumInfo, so a share-link
    // visitor is never told whose bucket the photos sit in. Every caller of this method is
    // @Transactional, which is what lets the lazy backend load for its name.
    if (album.getStorageBackend() != null) {
      info.setStorageBackendId(album.getStorageBackend().getId());
      info.setStorageBackendName(album.getStorageBackend().getName());
    }

    // One COUNT and one single-row lookup per album. This used to load every file entity of every
    // album on GET /api/albums just to size the list and pick a cover.
    info.setFileCount((int) fileMetadataRepository.countByAlbumId(album.getId()));
    Optional<FileMetadata> cover =
        fileMetadataRepository.findFirstByAlbumIdAndMimeTypeStartingWithOrderByDisplayOrderAsc(
            album.getId(), "image/");
    cover.ifPresent(
        c -> {
          info.setCoverImageFilename(c.getStoredFilename());
          info.setCoverImageToken(c.getPublicToken());
        });

    return info;
  }
}
