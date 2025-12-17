/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.SlideshowRecording;
import com.oglimmer.photoupload.entity.SlideshowRecordingImage;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.mapper.RecordingInfoMapper;
import com.oglimmer.photoupload.model.RecordingAudioInfo;
import com.oglimmer.photoupload.model.RecordingInfo;
import com.oglimmer.photoupload.model.RecordingRequest;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.security.UserContext;
import jakarta.annotation.PostConstruct;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

@Service
@Slf4j
@RequiredArgsConstructor
public class SlideshowRecordingService {

  private final SlideshowRecordingRepository slideshowRecordingRepository;
  private final AlbumRepository albumRepository;
  private final FileMetadataRepository fileMetadataRepository;
  private final FileStorageProperties fileStorageProperties;
  private final AudioReencodingService audioReencodingService;
  private final UserContext userContext;
  private final RecordingInfoMapper recordingInfoMapper;

  private Path recordingsDirectory;

  @PostConstruct
  public void init() {
    try {
      // Create recordings directory as a subdirectory of the main upload directory
      Path uploadDir = Paths.get(fileStorageProperties.getUploadDir()).toAbsolutePath().normalize();
      recordingsDirectory = uploadDir.resolve("recordings");
      Files.createDirectories(recordingsDirectory);
      log.info("Recordings directory initialized at: {}", recordingsDirectory);
    } catch (Exception ex) {
      throw new RuntimeException("Could not create recordings directory!", ex);
    }
  }

  @Transactional
  public RecordingInfo saveRecording(
      Long albumId, MultipartFile audioFile, RecordingRequest request) throws IOException {
    User currentUser = userContext.getCurrentUser();

    // Validate album exists and belongs to current user
    Album album =
        albumRepository
            .findByUserAndId(currentUser, albumId)
            .orElseThrow(() -> new IllegalArgumentException("Album not found with id: " + albumId));

    // Generate unique filename for audio
    String originalFilename = audioFile.getOriginalFilename();
    String extension =
        originalFilename != null && originalFilename.contains(".")
            ? originalFilename.substring(originalFilename.lastIndexOf("."))
            : ".webm";
    String audioFilename = UUID.randomUUID() + extension;
    Path audioPath = recordingsDirectory.resolve(audioFilename);

    // Save audio file
    Files.copy(audioFile.getInputStream(), audioPath);

    // Re-encode audio file to ensure spec compliance
    // Browser-recorded audio may not be 100% according to spec
    try {
      audioReencodingService.reencodeAudio(audioPath);
    } catch (IOException e) {
      log.error("Failed to re-encode audio file: {}", audioPath, e);
      // Clean up the original file since re-encoding failed
      Files.deleteIfExists(audioPath);
      throw new IOException("Failed to re-encode audio file", e);
    }

    // Create recording entity
    SlideshowRecording recording = new SlideshowRecording();
    recording.setAlbum(album);
    recording.setFilterTag(request.getFilterTag());
    recording.setLanguage(request.getLanguage());
    recording.setAudioFilename(audioFilename);
    // Store relative path in database (recordings/filename.webm)
    recording.setAudioPath("recordings/" + audioFilename);
    // Generate public token for unauthenticated access
    recording.setPublicToken(UUID.randomUUID().toString().replace("-", "").toLowerCase());
    recording.setDurationMs(request.getDurationMs());
    recording.setCreatedAt(Instant.now());

    // Add image timing data
    for (int i = 0; i < request.getImages().size(); i++) {
      RecordingRequest.RecordingImageData imageData = request.getImages().get(i);

      // Validate file exists
      FileMetadata file =
          fileMetadataRepository
              .findById(imageData.getFileId())
              .orElseThrow(
                  () ->
                      new IllegalArgumentException(
                          "File not found with id: " + imageData.getFileId()));

      SlideshowRecordingImage recordingImage = new SlideshowRecordingImage();
      recordingImage.setRecording(recording);
      recordingImage.setFile(file);
      recordingImage.setStartTimeMs(imageData.getStartTimeMs());
      recordingImage.setDurationMs(imageData.getDurationMs());
      recordingImage.setSequenceOrder(i);

      recording.getImages().add(recordingImage);
    }

    // Save to database
    recording = slideshowRecordingRepository.save(recording);

    log.info(
        "Saved slideshow recording for album {} with {} images",
        albumId,
        request.getImages().size());

    return convertToRecordingInfo(recording);
  }

  public List<RecordingInfo> getAlbumRecordings(Long albumId) {
    User currentUser = userContext.getCurrentUser();

    // Validate album exists and belongs to current user
    if (albumRepository.findByUserAndId(currentUser, albumId).isEmpty()) {
      throw new IllegalArgumentException("Album not found with id: " + albumId);
    }

    return slideshowRecordingRepository
        .findByAlbumIdAndUserIdOrderByCreatedAtDesc(albumId, currentUser.getId())
        .stream()
        .map(this::convertToRecordingInfo)
        .collect(Collectors.toList());
  }

  /**
   * Get recordings for a specific album and filter tag
   *
   * @param albumId Album ID
   * @param filterTag Tag name to filter by
   * @return List of recordings for the specified tag
   */
  public List<RecordingInfo> getRecordingsByAlbumAndTag(Long albumId, String filterTag) {
    User currentUser = userContext.getCurrentUser();

    // Validate album exists and belongs to current user
    if (albumRepository.findByUserAndId(currentUser, albumId).isEmpty()) {
      throw new IllegalArgumentException("Album not found with id: " + albumId);
    }

    return slideshowRecordingRepository
        .findByAlbumIdAndUserIdOrderByCreatedAtDesc(albumId, currentUser.getId())
        .stream()
        .filter(recording -> filterTag.equals(recording.getFilterTag()))
        .map(this::convertToRecordingInfo)
        .collect(Collectors.toList());
  }

  /**
   * Get recordings for an album by share token (public access)
   *
   * @param shareToken Album share token
   * @param filterTag Optional filter tag
   * @return List of recordings
   */
  public List<RecordingInfo> getRecordingsByShareToken(String shareToken, String filterTag) {
    // Validate album exists by share token
    Album album =
        albumRepository
            .findByShareToken(shareToken)
            .orElseThrow(() -> new IllegalArgumentException("Album not found with share token"));

    // Get all recordings for this album
    List<SlideshowRecording> recordings =
        slideshowRecordingRepository.findByAlbumIdAndUserIdOrderByCreatedAtDesc(
            album.getId(), album.getUser().getId());

    // Filter by tag if provided
    if (filterTag != null && !filterTag.isEmpty()) {
      recordings =
          recordings.stream()
              .filter(recording -> filterTag.equals(recording.getFilterTag()))
              .collect(Collectors.toList());
    }

    return recordings.stream().map(this::convertToRecordingInfo).collect(Collectors.toList());
  }

  public RecordingInfo getRecording(Long recordingId) {
    User currentUser = userContext.getCurrentUser();
    SlideshowRecording recording =
        slideshowRecordingRepository
            .findByIdAndUserId(recordingId, currentUser.getId())
            .orElseThrow(
                () -> new IllegalArgumentException("Recording not found with id: " + recordingId));

    return convertToRecordingInfo(recording);
  }

  /**
   * Get recording by public token (for unauthenticated access)
   *
   * @param publicToken The public token
   * @return Recording info
   */
  public RecordingInfo getRecordingByPublicToken(String publicToken) {
    SlideshowRecording recording =
        slideshowRecordingRepository
            .findByPublicToken(publicToken)
            .orElseThrow(
                () -> new IllegalArgumentException("Recording not found with public token"));

    return convertToRecordingInfo(recording);
  }

  /**
   * Get the recording audio info (for serving audio files)
   *
   * @param recordingId The recording ID
   * @return Recording audio information DTO
   */
  public RecordingAudioInfo getRecordingAudioInfo(Long recordingId) {
    User currentUser = userContext.getCurrentUser();
    SlideshowRecording recording =
        slideshowRecordingRepository
            .findByIdAndUserId(recordingId, currentUser.getId())
            .orElseThrow(
                () -> new IllegalArgumentException("Recording not found with id: " + recordingId));

    return convertToRecordingAudioInfo(recording);
  }

  /**
   * Get the recording audio info by public token (for serving audio files)
   *
   * @param publicToken The public token
   * @return Recording audio information DTO
   */
  public RecordingAudioInfo getRecordingAudioInfoByPublicToken(String publicToken) {
    SlideshowRecording recording =
        slideshowRecordingRepository
            .findByPublicToken(publicToken)
            .orElseThrow(
                () -> new IllegalArgumentException("Recording not found with public token"));

    return convertToRecordingAudioInfo(recording);
  }

  @Transactional
  public void deleteRecording(Long recordingId) throws IOException {
    User currentUser = userContext.getCurrentUser();
    SlideshowRecording recording =
        slideshowRecordingRepository
            .findByIdAndUserId(recordingId, currentUser.getId())
            .orElseThrow(
                () -> new IllegalArgumentException("Recording not found with id: " + recordingId));

    // Delete audio file using absolute path
    Path uploadDir = Paths.get(fileStorageProperties.getUploadDir()).toAbsolutePath().normalize();
    Path audioPath = uploadDir.resolve(recording.getAudioPath());
    if (Files.exists(audioPath)) {
      Files.delete(audioPath);
      log.info("Deleted audio file: {}", audioPath);
    }

    // Delete database record (cascade will handle images)
    slideshowRecordingRepository.delete(recording);

    log.info("Deleted slideshow recording: {}", recordingId);
  }

  private RecordingInfo convertToRecordingInfo(SlideshowRecording recording) {
    return recordingInfoMapper.recordingToRecordingInfo(recording);
  }

  private RecordingAudioInfo convertToRecordingAudioInfo(SlideshowRecording recording) {
    Path uploadDir = Paths.get(fileStorageProperties.getUploadDir()).toAbsolutePath().normalize();
    Path audioPath = uploadDir.resolve(recording.getAudioPath());

    return new RecordingAudioInfo(recording.getAudioFilename(), audioPath);
  }
}
