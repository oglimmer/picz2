/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import org.springframework.context.annotation.Profile;

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
import com.oglimmer.photoupload.storage.StoragePaths;
import jakarta.annotation.PostConstruct;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

@Profile(Profiles.API)
@Service
@Slf4j
@RequiredArgsConstructor
public class SlideshowRecordingService {

  private static final String AUDIO_TMP = ".audio-tmp";

  private final SlideshowRecordingRepository slideshowRecordingRepository;
  private final AlbumRepository albumRepository;
  private final FileMetadataRepository fileMetadataRepository;
  private final FileStorageProperties fileStorageProperties;
  private final AudioReencodingService audioReencodingService;
  private final UserContext userContext;
  private final RecordingInfoMapper recordingInfoMapper;
  // Optional: present iff storage.s3.enabled=true. When present, new audio uploads PUT directly
  // to MinIO with key audio/{filename} and the audio_path column stores that key. Legacy rows
  // continue to use audio_path = "recordings/{filename}" (local disk relative path).
  private final Optional<ObjectStorageService> objectStorage;

  @PostConstruct
  public void init() {
    try {
      Path uploadDir = uploadDir();
      Path recordingsDir = uploadDir.resolve("recordings");
      // Always ensure the legacy directory exists so the disk-backed code path stays viable
      // (until the helm chart drops the PVC mount).
      Files.createDirectories(recordingsDir);
      Files.createDirectories(uploadDir.resolve(AUDIO_TMP));
      log.info(
          "Recordings directory: {} (S3 mode: {})", recordingsDir, objectStorage.isPresent());
    } catch (Exception ex) {
      throw new RuntimeException("Could not create recordings directory!", ex);
    }
  }

  /**
   * Resolved on demand — keeping it stateless makes unit tests work without invoking
   * {@link #init()} via Spring's {@code @PostConstruct} machinery.
   */
  private Path uploadDir() {
    return Paths.get(fileStorageProperties.getUploadDir()).toAbsolutePath().normalize();
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

    String storedAudioPath = persistAudio(audioFile, audioFilename);

    // Create recording entity
    SlideshowRecording recording = new SlideshowRecording();
    recording.setAlbum(album);
    recording.setFilterTag(request.getFilterTag());
    recording.setLanguage(request.getLanguage());
    recording.setAudioFilename(audioFilename);
    recording.setAudioPath(storedAudioPath);
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
        "Saved slideshow recording for album {} with {} images (storage={})",
        albumId,
        request.getImages().size(),
        storedAudioPath);

    return convertToRecordingInfo(recording);
  }

  /**
   * Stage the upload to a local temp file, re-encode it with ffmpeg (which needs a local file),
   * then either PUT to S3 (and delete the temp) or move to the durable {@code recordings/}
   * directory. Returns the value to store in {@code audio_path}.
   */
  private String persistAudio(MultipartFile audioFile, String audioFilename) throws IOException {
    Path uploadDir = uploadDir();
    Path tempDir = uploadDir.resolve(AUDIO_TMP);
    Files.createDirectories(tempDir);
    Path tempPath = tempDir.resolve(audioFilename);

    try {
      Files.copy(audioFile.getInputStream(), tempPath);

      // Re-encode (browser-recorded WebM is often not strictly spec-compliant; ffmpeg fixes it
      // and replaces the file in-place).
      try {
        audioReencodingService.reencodeAudio(tempPath);
      } catch (IOException e) {
        log.error("Failed to re-encode audio file: {}", tempPath, e);
        Files.deleteIfExists(tempPath);
        throw new IOException("Failed to re-encode audio file", e);
      }

      if (objectStorage.isPresent()) {
        String key = StoragePaths.audioKey(audioFilename);
        objectStorage.get().putFile(key, tempPath, contentTypeFor(audioFilename));
        Files.deleteIfExists(tempPath);
        return key;
      }

      // Legacy path: move re-encoded file to the durable recordings dir, keep DB pointer
      // relative (recordings/{filename}) just like before.
      Path durable = uploadDir.resolve("recordings").resolve(audioFilename);
      Files.createDirectories(durable.getParent());
      Files.move(tempPath, durable);
      return "recordings/" + audioFilename;
    } catch (IOException e) {
      try {
        Files.deleteIfExists(tempPath);
      } catch (IOException cleanup) {
        e.addSuppressed(cleanup);
      }
      throw e;
    }
  }

  private String contentTypeFor(String filename) {
    if (filename.endsWith(".ogg")) {
      return "audio/ogg";
    }
    if (filename.endsWith(".mp3")) {
      return "audio/mpeg";
    }
    return "audio/webm";
  }

  @Transactional(readOnly = true)
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
  @Transactional(readOnly = true)
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
  @Transactional(readOnly = true)
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

  @Transactional(readOnly = true)
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
  @Transactional(readOnly = true)
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
  @Transactional(readOnly = true)
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
  @Transactional(readOnly = true)
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

    String audioPath = recording.getAudioPath();
    if (StoragePaths.isAudioS3Key(audioPath) && objectStorage.isPresent()) {
      try {
        objectStorage.get().delete(audioPath);
        log.info("Deleted audio object: s3://.../{}", audioPath);
      } catch (Exception e) {
        // Non-fatal: leaves an orphan object but the row is gone. Logged for follow-up.
        log.warn("Could not delete audio object {}: {}", audioPath, e.toString());
      }
    } else if (audioPath != null) {
      Path local = uploadDir().resolve(audioPath);
      if (Files.exists(local)) {
        Files.delete(local);
        log.info("Deleted audio file: {}", local);
      }
    }

    // Delete database record (cascade will handle images)
    slideshowRecordingRepository.delete(recording);

    log.info("Deleted slideshow recording: {}", recordingId);
  }

  private RecordingInfo convertToRecordingInfo(SlideshowRecording recording) {
    return recordingInfoMapper.recordingToRecordingInfo(recording);
  }

  private RecordingAudioInfo convertToRecordingAudioInfo(SlideshowRecording recording) {
    String audioPath = recording.getAudioPath();
    if (StoragePaths.isAudioS3Key(audioPath)) {
      // S3-backed: pass the key, leave audioPath null so the controller branches to presigned-URL
      // serving.
      return new RecordingAudioInfo(recording.getAudioFilename(), null, audioPath);
    }
    Path local = uploadDir().resolve(audioPath);
    return new RecordingAudioInfo(recording.getAudioFilename(), local, null);
  }
}
