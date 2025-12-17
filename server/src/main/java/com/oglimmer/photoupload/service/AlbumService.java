/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.DuplicateResourceException;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.mapper.AlbumMapper;
import com.oglimmer.photoupload.model.AlbumInfo;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Slf4j
@RequiredArgsConstructor
public class AlbumService {

  private final AlbumRepository albumRepository;
  private final FileMetadataRepository fileMetadataRepository;
  private final JdbcTemplate jdbcTemplate;
  private final FileStorageService fileStorageService;
  private final UserContext userContext;
  private final AlbumMapper albumMapper;

  @Transactional
  public AlbumInfo createAlbum(String name, String description) {
    User currentUser = userContext.getCurrentUser();

    // Check if album with this name already exists for this user
    if (albumRepository.findByUserAndName(currentUser, name).isPresent()) {
      throw new DuplicateResourceException("Album", "name", name);
    }

    Album album = new Album();
    album.setUser(currentUser);
    album.setName(name);
    album.setDescription(description);
    album.setCreatedAt(Instant.now());
    album.setUpdatedAt(Instant.now());

    // Generate a new random token (64 hex chars)
    byte[] bytes = new byte[32];
    new SecureRandom().nextBytes(bytes);
    String token = HexFormat.of().formatHex(bytes);
    album.setShareToken(token);

    // Set display order to be at the end for this user
    Integer maxOrder = albumRepository.findMaxDisplayOrderByUser(currentUser);
    album.setDisplayOrder(maxOrder != null ? maxOrder + 1 : 0);

    album = albumRepository.save(album);
    log.info("Created album: {} for user: {}", name, currentUser.getEmail());

    return convertToAlbumInfo(album);
  }

  public List<AlbumInfo> listAlbums() {
    User currentUser = userContext.getCurrentUser();
    return albumRepository.findByUserOrderByDisplayOrderAsc(currentUser).stream()
        .map(this::convertToAlbumInfo)
        .collect(Collectors.toList());
  }

  public AlbumInfo getAlbum(Long albumId) {
    User currentUser = userContext.getCurrentUser();
    Album album =
        albumRepository
            .findByUserAndId(currentUser, albumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId));
    return convertToAlbumInfo(album);
  }

  @Transactional
  public AlbumInfo updateAlbum(Long albumId, String name, String description) {
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

    album.setUpdatedAt(Instant.now());
    album = albumRepository.save(album);

    log.info("Updated album: {} for user: {}", album.getName(), currentUser.getEmail());
    return convertToAlbumInfo(album);
  }

  @Transactional
  public void deleteAlbum(Long albumId) {
    User currentUser = userContext.getCurrentUser();
    Album album =
        albumRepository
            .findByUserAndId(currentUser, albumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId));

    // Get all files in this album
    List<FileMetadata> files =
        fileMetadataRepository.findByAlbumIdAndUserIdOrderByDisplayOrderAsc(
            albumId, currentUser.getId());

    // Delete all files (both physical files and database records)
    for (FileMetadata file : files) {
      try {
        fileStorageService.deleteFile(file.getId());
      } catch (Exception e) {
        log.error("Error deleting file {} during album deletion: {}", file.getId(), e.getMessage());
        // Continue with other files even if one fails
      }
    }

    // Delete the album (cascade will handle any remaining database relationships)
    albumRepository.delete(album);
    log.info(
        "Deleted album '{}' with {} photos for user: {}",
        album.getName(),
        files.size(),
        currentUser.getEmail());
  }

  @Transactional
  public void reorderAlbums(List<Long> albumIds) {
    User currentUser = userContext.getCurrentUser();

    // Validate all album IDs exist and belong to current user
    for (Long albumId : albumIds) {
      if (albumRepository.findByUserAndId(currentUser, albumId).isEmpty()) {
        throw new ResourceNotFoundException("Album", "id", albumId);
      }
    }

    // Update display order for each album
    for (int i = 0; i < albumIds.size(); i++) {
      Long albumId = albumIds.get(i);
      Album album = albumRepository.findByUserAndId(currentUser, albumId).orElseThrow();
      album.setDisplayOrder(i);
      albumRepository.save(album);
    }

    log.info("Reordered {} albums for user: {}", albumIds.size(), currentUser.getEmail());
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

    // Find the first sequence of digits
    java.util.regex.Matcher matcher = java.util.regex.Pattern.compile("\\d+").matcher(filename);
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

  public AlbumInfo getAlbumByShareToken(String shareToken) {
    Album album =
        albumRepository
            .findByShareToken(shareToken)
            .orElseThrow(() -> new ResourceNotFoundException("Album not found with share token"));

    // Return minimal info for public access (just name and id)
    AlbumInfo info = new AlbumInfo();
    info.setId(album.getId());
    info.setName(album.getName());
    info.setShareToken(album.getShareToken());

    return info;
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

    // Get files in this album (use user-scoped query)
    List<FileMetadata> files =
        fileMetadataRepository.findByAlbumIdAndUserIdOrderByDisplayOrderAsc(
            album.getId(), album.getUser().getId());
    info.setFileCount(files.size());

    // Set cover image (first image in album - not a video)
    if (!files.isEmpty()) {
      FileMetadata cover =
          files.stream()
              .filter(file -> file.getMimeType() != null && file.getMimeType().startsWith("image/"))
              .findFirst()
              .orElse(null);

      if (cover != null) {
        String coverFilename = cover.getStoredFilename();
        log.info(
            "Album {} - Setting cover image: {} (found {} files)",
            album.getName(),
            coverFilename,
            files.size());
        info.setCoverImageFilename(coverFilename);
        info.setCoverImageToken(cover.getPublicToken());
      } else {
        log.info("Album {} - No image files found for cover (only videos/other)", album.getName());
      }
    } else {
      log.info("Album {} - No files found for cover image", album.getName());
    }

    return info;
  }
}
