/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.entity.SlideshowRecording;
import com.oglimmer.photoupload.model.RecordingAudioInfo;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.storage.StoragePaths;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Owns the AAC sibling of a recording's audio — the rendition every Apple client plays.
 *
 * <p>Apple's media stack has no WebM demuxer, so the Opus/WebM master an iPhone is handed simply
 * never opens. The sibling is a plain {@code .m4a} next to the master, addressed by deriving its
 * name ({@link StoragePaths#aacFilename}) rather than by a second column.
 *
 * <p>Deliberately carries no {@code @Profile}: the api pod only ever <em>asks</em> whether the
 * sibling is there ({@link #isAacReady}), and the worker pod is the only one that <em>makes</em> it
 * ({@link #materialiseAac}). Producing it inside an api request is what this class exists to stop —
 * a transcode on the Pi runs for around a minute, and {@code AVPlayer} abandons the request long
 * before that, which is exactly the "cannot be played on iPhone" error users saw on first play.
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class RecordingAudioService {

  public static final String AAC_CONTENT_TYPE = "audio/mp4";

  private static final String AUDIO_TMP = ".audio-tmp";

  private final SlideshowRecordingRepository slideshowRecordingRepository;
  private final FileStorageProperties fileStorageProperties;
  private final AudioReencodingService audioReencodingService;
  private final Optional<ObjectStorageService> objectStorage;

  /** True when the sibling already exists and can be served straight away. */
  public boolean isAacReady(SlideshowRecording recording) {
    String audioPath = recording.getAudioPath();
    if (audioPath == null || recording.getAudioFilename() == null) {
      return false;
    }
    try {
      if (StoragePaths.isAudioS3Key(audioPath) && objectStorage.isPresent()) {
        return objectStorage.get().exists(StoragePaths.audioAacKey(recording.getAudioFilename()));
      }
      return Files.exists(localAac(recording));
    } catch (Exception e) {
      // "Cannot tell" must not read as "ready": a false here costs one queued job, a false
      // positive hands the client a 404 mid-playback.
      log.warn(
          "Could not check the AAC sibling for recording {}: {}", recording.getId(), e.toString());
      return false;
    }
  }

  /** Where the sibling lives, for the controller to stream. Only valid once {@link #isAacReady}. */
  public RecordingAudioInfo aacLocation(SlideshowRecording recording) {
    String aacFilename = StoragePaths.aacFilename(recording.getAudioFilename());
    if (StoragePaths.isAudioS3Key(recording.getAudioPath()) && objectStorage.isPresent()) {
      return new RecordingAudioInfo(
          aacFilename, null, StoragePaths.audioAacKey(recording.getAudioFilename()));
    }
    return new RecordingAudioInfo(aacFilename, localAac(recording), null);
  }

  /**
   * Makes the sibling. Runs on the worker pod, off the request path, driven by a {@code
   * TRANSCODE_AUDIO_AAC} job.
   *
   * <p>Every intermediate file is uniquely named and only moved/PUT once it is complete, so two
   * workers racing on the same recording cannot hand each other a half-written file. The last one
   * to finish wins, and both wrote the same bytes.
   */
  public void materialiseAac(Long recordingId) throws IOException {
    SlideshowRecording recording =
        slideshowRecordingRepository
            .findById(recordingId)
            .orElseThrow(() -> new IOException("Recording not found with id: " + recordingId));

    String masterFilename = recording.getAudioFilename();
    String audioPath = recording.getAudioPath();
    if (masterFilename == null || audioPath == null) {
      throw new IOException("Recording " + recordingId + " has no audio to transcode");
    }

    if (isAacReady(recording)) {
      log.info("AAC sibling for recording {} already exists — nothing to do", recordingId);
      return;
    }

    Path tempDir = uploadDir().resolve(AUDIO_TMP);
    Files.createDirectories(tempDir);
    Path scratch = tempDir.resolve("aac-out-" + UUID.randomUUID() + ".m4a");

    try {
      if (StoragePaths.isAudioS3Key(audioPath) && objectStorage.isPresent()) {
        Path master = tempDir.resolve("aac-src-" + UUID.randomUUID());
        try {
          objectStorage.get().getToFile(audioPath, master);
          audioReencodingService.transcodeToAac(master, scratch);
        } finally {
          Files.deleteIfExists(master);
        }
        String aacKey = StoragePaths.audioAacKey(masterFilename);
        objectStorage.get().putFile(aacKey, scratch, AAC_CONTENT_TYPE);
        log.info("Stored AAC sibling s3://.../{}", aacKey);
        return;
      }

      Path master = uploadDir().resolve(audioPath);
      audioReencodingService.transcodeToAac(master, scratch);
      Path destination = localAac(recording);
      Files.createDirectories(destination.getParent());
      Files.move(scratch, destination, StandardCopyOption.REPLACE_EXISTING);
      log.info("Stored AAC sibling {}", destination);
    } finally {
      Files.deleteIfExists(scratch);
    }
  }

  private Path localAac(SlideshowRecording recording) {
    Path master = uploadDir().resolve(recording.getAudioPath());
    return master.resolveSibling(StoragePaths.aacFilename(recording.getAudioFilename()));
  }

  private Path uploadDir() {
    return Paths.get(fileStorageProperties.getUploadDir()).toAbsolutePath().normalize();
  }
}
