/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.JobStatus;
import com.oglimmer.photoupload.entity.JobType;
import com.oglimmer.photoupload.entity.SlideshowRecording;
import com.oglimmer.photoupload.entity.SlideshowRecordingImage;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.AudioNotReadyException;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.mapper.RecordingInfoMapper;
import com.oglimmer.photoupload.model.RecordingAudioInfo;
import com.oglimmer.photoupload.model.RecordingAudioStatus;
import com.oglimmer.photoupload.model.RecordingInfo;
import com.oglimmer.photoupload.model.RecordingRequest;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.ProcessingJobRepository;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.security.UserContext;
import com.oglimmer.photoupload.storage.BackendStorage;
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
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

@Profile(Profiles.API)
@Service
@Slf4j
@RequiredArgsConstructor
public class SlideshowRecordingService {

  private static final String AUDIO_TMP = ".audio-tmp";

  /** The {@code ?format=} value that asks for the AAC sibling instead of the Opus master. */
  private static final String AAC_FORMAT = "m4a";

  private final SlideshowRecordingRepository slideshowRecordingRepository;
  private final AlbumRepository albumRepository;
  private final FileMetadataRepository fileMetadataRepository;
  private final FileStorageProperties fileStorageProperties;
  private final AudioReencodingService audioReencodingService;
  private final UserContext userContext;
  private final StorageQuotaService storageQuotaService;
  private final RecordingInfoMapper recordingInfoMapper;
  private final RecordingAudioService recordingAudioService;
  private final JobEnqueueService jobEnqueueService;
  private final ProcessingJobRepository processingJobRepository;
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
      log.info("Recordings directory: {} (S3 mode: {})", recordingsDir, objectStorage.isPresent());
    } catch (Exception ex) {
      throw new RuntimeException("Could not create recordings directory!", ex);
    }
  }

  /**
   * Resolved on demand — keeping it stateless makes unit tests work without invoking {@link
   * #init()} via Spring's {@code @PostConstruct} machinery.
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
            .orElseThrow(
                () -> new ResourceNotFoundException("Album not found with id: " + albumId));

    // Generate unique filename for audio
    String originalFilename = audioFile.getOriginalFilename();
    String extension =
        originalFilename != null && originalFilename.contains(".")
            ? originalFilename.substring(originalFilename.lastIndexOf("."))
            : ".webm";
    String audioFilename = UUID.randomUUID() + extension;

    // Narration counts against the quota like any other object we keep. Checked on the upload's
    // own size: re-encoding changes it a little, never by an order of magnitude.
    storageQuotaService.requireRoomFor(currentUser, albumId, audioFile.getSize());

    StoredAudio storedAudio = persistAudio(audioFile, audioFilename, albumId);
    String storedAudioPath = storedAudio.path();

    // Create recording entity
    SlideshowRecording recording = new SlideshowRecording();
    recording.setAlbum(album);
    recording.setFilterTag(request.getFilterTag());
    recording.setLanguage(request.getLanguage());
    recording.setAudioFilename(audioFilename);
    recording.setAudioPath(storedAudioPath);
    recording.setAudioBytes(storedAudio.bytes());
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
                      new ResourceNotFoundException(
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
  /** Where the narration ended up, and what it costs — master plus its derived AAC sibling. */
  private record StoredAudio(String path, long bytes) {}

  private StoredAudio persistAudio(MultipartFile audioFile, String audioFilename, Long albumId)
      throws IOException {
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

      // Make the AAC sibling now rather than on first playback: Apple's media stack cannot open
      // the Opus/WebM master at all, and doing it here means an iPhone never waits on ffmpeg.
      // A failure is not fatal — the master is still saved, and the sibling is retried on demand.
      Path aacPath = tempPath.resolveSibling(StoragePaths.aacFilename(audioFilename));
      boolean haveAac = true;
      try {
        audioReencodingService.transcodeToAac(tempPath, aacPath);
      } catch (IOException e) {
        haveAac = false;
        log.warn("Could not make the AAC sibling for {}: {}", audioFilename, e.toString());
      }

      if (objectStorage.isPresent()) {
        // Commentary follows its album's storage, same as the photos it talks over — otherwise a
        // user on their own S3 would have the pictures on their bill and the audio on ours.
        BackendStorage storage = objectStorage.get().forAlbumId(albumId);
        String key = StoragePaths.audioKey(audioFilename);
        // Sized before the PUTs, while both files are still on disk.
        long bytes = Files.size(tempPath) + (haveAac ? Files.size(aacPath) : 0);
        storage.putFile(key, tempPath, contentTypeFor(audioFilename));
        if (haveAac) {
          storage.putFile(
              StoragePaths.audioAacKey(audioFilename),
              aacPath,
              RecordingAudioService.AAC_CONTENT_TYPE);
        }
        Files.deleteIfExists(tempPath);
        Files.deleteIfExists(aacPath);
        return new StoredAudio(key, bytes);
      }

      // Legacy path: move re-encoded file to the durable recordings dir, keep DB pointer
      // relative (recordings/{filename}) just like before.
      Path durable = uploadDir.resolve("recordings").resolve(audioFilename);
      Files.createDirectories(durable.getParent());
      Files.move(tempPath, durable);
      if (haveAac) {
        Files.move(aacPath, durable.resolveSibling(StoragePaths.aacFilename(audioFilename)));
      }
      long localBytes =
          Files.size(durable)
              + (haveAac
                  ? Files.size(durable.resolveSibling(StoragePaths.aacFilename(audioFilename)))
                  : 0);
      return new StoredAudio("recordings/" + audioFilename, localBytes);
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
      throw new ResourceNotFoundException("Album not found with id: " + albumId);
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
      throw new ResourceNotFoundException("Album not found with id: " + albumId);
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
            .findByShareTokenAndPublishedTrue(shareToken)
            .orElseThrow(() -> new ResourceNotFoundException("Album not found with share token"));

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

  /**
   * @param format {@code "m4a"} for the AAC sibling Apple clients need, null/blank for the master
   * @throws AudioNotReadyException if the AAC sibling has still to be made — a job is queued
   */
  @Transactional
  public RecordingAudioInfo getRecordingAudioInfoByPublicToken(String publicToken, String format) {
    SlideshowRecording recording =
        slideshowRecordingRepository
            .findByPublicToken(publicToken)
            .orElseThrow(
                () -> new ResourceNotFoundException("Recording not found with public token"));

    return convertToRecordingAudioInfo(recording, format);
  }

  @Transactional
  public void deleteRecording(Long recordingId) throws IOException {
    User currentUser = userContext.getCurrentUser();
    SlideshowRecording recording =
        slideshowRecordingRepository
            .findByIdAndUserId(recordingId, currentUser.getId())
            .orElseThrow(
                () -> new ResourceNotFoundException("Recording not found with id: " + recordingId));

    String audioPath = recording.getAudioPath();
    String aacFilename = StoragePaths.aacFilename(recording.getAudioFilename());
    if (StoragePaths.isAudioS3Key(audioPath) && objectStorage.isPresent()) {
      BackendStorage storage = objectStorage.get().forAlbumId(recording.getAlbum().getId());
      try {
        storage.delete(audioPath);
        log.info("Deleted audio object: s3://.../{}", audioPath);
      } catch (Exception e) {
        // Non-fatal: leaves an orphan object but the row is gone. Logged for follow-up.
        log.warn("Could not delete audio object {}: {}", audioPath, e.toString());
      }
      // The AAC sibling is derived, not recorded in the row, so it has to be named here. It may
      // legitimately not exist — it is only made on demand for older recordings.
      String aacKey = StoragePaths.audioAacKey(recording.getAudioFilename());
      try {
        storage.delete(aacKey);
      } catch (Exception e) {
        log.warn("Could not delete AAC sibling {}: {}", aacKey, e.toString());
      }
    } else if (audioPath != null) {
      Path local = uploadDir().resolve(audioPath);
      if (Files.exists(local)) {
        Files.delete(local);
        log.info("Deleted audio file: {}", local);
      }
      Files.deleteIfExists(local.resolveSibling(aacFilename));
    }

    // Delete database record (cascade will handle images)
    slideshowRecordingRepository.delete(recording);

    log.info("Deleted slideshow recording: {}", recordingId);
  }

  private RecordingInfo convertToRecordingInfo(SlideshowRecording recording) {
    return recordingInfoMapper.recordingToRecordingInfo(recording);
  }

  private RecordingAudioInfo convertToRecordingAudioInfo(
      SlideshowRecording recording, String format) {
    if (AAC_FORMAT.equalsIgnoreCase(format)) {
      return aacRendition(recording);
    }

    String audioPath = recording.getAudioPath();
    if (StoragePaths.isAudioS3Key(audioPath)) {
      // S3-backed: pass the key, leave audioPath null so the controller streams from MinIO.
      return new RecordingAudioInfo(
          recording.getAudioFilename(), null, audioPath, recording.getAlbum().getId());
    }
    Path local = uploadDir().resolve(audioPath);
    return new RecordingAudioInfo(
        recording.getAudioFilename(), local, null, recording.getAlbum().getId());
  }

  /**
   * Where the AAC sibling for this recording lives — never making it here.
   *
   * <p>Transcoding used to happen inline on the first request. On the Pi that runs for about a
   * minute, and {@code AVPlayer} abandons the connection long before it finishes, so the very play
   * that triggered the work was always the one that failed. Worse, the abandoned response then
   * threw from inside the streaming body and corrupted the Tomcat connection for whatever request
   * came next, which is why a second attempt could fail too.
   *
   * <p>So: if the sibling is there, serve it. If not, queue it on the worker and tell the client to
   * come back — {@code AudioNotReadyException} maps to a 503 with {@code Retry-After}, and iOS
   * shows "Preparing audio" while it polls {@link #audioStatusByPublicToken}.
   */
  private RecordingAudioInfo aacRendition(SlideshowRecording recording) {
    if (recordingAudioService.isAacReady(recording)) {
      return recordingAudioService.aacLocation(recording);
    }
    boolean failed = requestAacTranscode(recording);
    throw new AudioNotReadyException(
        failed
            ? "Making an iPhone-playable copy of this commentary failed."
            : "This commentary is still being prepared for iPhone.",
        failed);
  }

  /** Readiness of the AAC sibling, queueing the work if it has not been queued yet. */
  @Transactional
  public RecordingAudioStatus audioStatusByPublicToken(String publicToken) {
    SlideshowRecording recording =
        slideshowRecordingRepository
            .findByPublicToken(publicToken)
            .orElseThrow(
                () -> new ResourceNotFoundException("Recording not found with public token"));

    if (recordingAudioService.isAacReady(recording)) {
      return new RecordingAudioStatus(true, true, false);
    }
    boolean failed = requestAacTranscode(recording);
    return new RecordingAudioStatus(true, false, failed);
  }

  /**
   * Queue the transcode unless it is already queued, already running, or already given up on.
   *
   * @return true when the transcode has dead-lettered — the client should stop polling and say so
   *     rather than wait for something that will not arrive
   */
  private boolean requestAacTranscode(SlideshowRecording recording) {
    Long id = recording.getId();
    if (processingJobRepository.existsByRecordingIdAndJobTypeAndStatusIn(
        id, JobType.TRANSCODE_AUDIO_AAC, List.of(JobStatus.DEAD_LETTER))) {
      return true;
    }
    // A client polls every couple of seconds; without this guard each poll would queue another
    // copy of a job that takes a minute to run.
    if (!processingJobRepository.existsByRecordingIdAndJobTypeAndStatusIn(
        id, JobType.TRANSCODE_AUDIO_AAC, List.of(JobStatus.QUEUED, JobStatus.PROCESSING))) {
      jobEnqueueService.enqueueForRecording(id, JobType.TRANSCODE_AUDIO_AAC);
      log.info("Queued TRANSCODE_AUDIO_AAC for recording {}", id);
    }
    return false;
  }
}
