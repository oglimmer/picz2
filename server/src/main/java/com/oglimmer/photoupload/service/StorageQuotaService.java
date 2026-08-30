/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.SlideshowRecording;
import com.oglimmer.photoupload.entity.StorageBackend;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.StorageQuotaExceededException;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.repository.StorageBackendRepository;
import com.oglimmer.photoupload.storage.BackendStorage;
import com.oglimmer.photoupload.storage.StoragePaths;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * How much of the instance's own storage a user is allowed, and how much of it they have used.
 *
 * <p>Only the system backend is metered. An album on the user's own S3 costs the operator nothing,
 * so it is neither counted nor capped — capping it would be rationing someone else's disk. Bytes
 * staged under {@code tus-uploads/} are not counted either: they live for minutes, are swept by
 * retention whether or not the upload finished, and an album on a user's own storage passes its
 * bytes through that prefix on the way out. Charging for that would bill transport as storage.
 *
 * <p>Usage is computed on demand rather than kept in a counter column. Two uploads racing against a
 * nearly-full quota can therefore both pass the check and land slightly over it; that is
 * deliberate. A counter would need its own locking on the hottest path in the app to buy a
 * precision nobody is asking for — the limit is a guard against filling a disk, not a billing
 * meter.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class StorageQuotaService {

  private final FileMetadataRepository metadataRepository;
  private final SlideshowRecordingRepository recordingRepository;
  private final StorageBackendRepository backendRepository;
  private final AlbumRepository albumRepository;
  private final Optional<ObjectStorageService> objectStorage;

  /**
   * A user's standing with the metered backend.
   *
   * @param usedBytes what they currently keep on the instance's storage
   * @param quotaBytes what they are allowed
   */
  public record Usage(long usedBytes, long quotaBytes) {
    public long remainingBytes() {
      return Math.max(0, quotaBytes - usedBytes);
    }

    public boolean isFull() {
      return usedBytes >= quotaBytes;
    }
  }

  @Transactional(readOnly = true)
  public Usage usageFor(User user) {
    Long backendId = systemBackendId();
    if (backendId == null) {
      return new Usage(0, quotaOf(user));
    }
    long used =
        metadataRepository.sumOriginalBytes(user.getId(), backendId)
            + metadataRepository.sumDerivativeBytes(user.getId(), backendId)
            + recordingRepository.sumAudioBytes(user.getId(), backendId);
    return new Usage(used, quotaOf(user));
  }

  /**
   * Refuse an upload that would not fit. A no-op when the target album lives on the user's own
   * storage — that is theirs to fill.
   *
   * @param albumId the album the bytes are destined for; null means the user's default album
   * @param incomingBytes size of the object about to be written
   */
  @Transactional(readOnly = true)
  public void requireRoomFor(User user, Long albumId, long incomingBytes) {
    if (!isMetered(albumId, user)) {
      return;
    }
    Usage usage = usageFor(user);
    if (usage.usedBytes() + incomingBytes > usage.quotaBytes()) {
      throw new StorageQuotaExceededException(usage.usedBytes(), usage.quotaBytes(), incomingBytes);
    }
  }

  /**
   * Whether bytes going into this album count against the quota — i.e. whether the album sits on
   * the instance's own storage.
   *
   * <p>An album we cannot resolve counts as metered. Guessing "unmetered" would let a bad album id
   * become a way past the limit, and the upload is about to fail on that id anyway.
   */
  @Transactional(readOnly = true)
  public boolean isMetered(Long albumId, User user) {
    Long effectiveAlbumId = albumId != null ? albumId : user.getDefaultAlbumId();
    if (effectiveAlbumId == null) {
      return true;
    }
    return albumRepository
        .findStorageBackendByAlbumId(effectiveAlbumId)
        .map(StorageBackend::isSystemDefault)
        .orElse(true);
  }

  /**
   * One-off repair for data written before the byte columns existed: reads the real object sizes
   * out of the instance's own bucket and writes them onto the rows.
   *
   * <p>Needed because a migration cannot compute this — the sizes only exist in the object store.
   * Until it runs, assets uploaded before the quota feature meter as costing nothing, so a long-
   * standing account would appear empty. Idempotent, and safe to run while the app serves traffic:
   * it only touches rows whose recorded size is still zero.
   *
   * @return how many assets and recordings were given a size
   */
  @Transactional
  public Map<String, Object> backfillStoredBytes() {
    Map<String, Object> result = new HashMap<>();
    if (objectStorage.isEmpty()) {
      result.put("skipped", "object storage is not enabled");
      return result;
    }
    StorageBackend system =
        backendRepository
            .findBySystemDefaultTrue()
            .orElseThrow(() -> new IllegalStateException("No system default storage backend row"));
    BackendStorage storage = objectStorage.get().forBackend(system);

    Map<String, Long> derivativeSizes = storage.listKeySizes(StoragePaths.DERIVATIVES_PREFIX);
    Map<String, Long> audioSizes = storage.listKeySizes(StoragePaths.AUDIO_PREFIX);

    int assets = 0;
    for (FileMetadata metadata :
        metadataRepository.findWithUnknownDerivativeBytes(system.getId())) {
      long total =
          sizeOf(derivativeSizes, metadata.getThumbnailPath())
              + sizeOf(derivativeSizes, metadata.getMediumPath())
              + sizeOf(derivativeSizes, metadata.getLargePath())
              + sizeOf(derivativeSizes, metadata.getTranscodedVideoPath());
      if (total > 0) {
        metadata.setDerivativeBytes(total);
        metadataRepository.save(metadata);
        assets++;
      }
    }

    int recordings = 0;
    for (SlideshowRecording recording :
        recordingRepository.findByStorageBackendWithUnknownAudioBytes(system.getId())) {
      long total = sizeOf(audioSizes, recording.getAudioPath());
      if (recording.getAudioFilename() != null) {
        total += sizeOf(audioSizes, StoragePaths.audioAacKey(recording.getAudioFilename()));
      }
      if (total > 0) {
        recording.setAudioBytes(total);
        recordingRepository.save(recording);
        recordings++;
      }
    }

    log.info("Storage-usage backfill: sized {} assets and {} recordings", assets, recordings);
    result.put("assetsSized", assets);
    result.put("recordingsSized", recordings);
    result.put("derivativeKeysListed", derivativeSizes.size());
    result.put("audioKeysListed", audioSizes.size());
    return result;
  }

  private static long sizeOf(Map<String, Long> sizes, String key) {
    if (key == null) {
      return 0L;
    }
    Long size = sizes.get(key);
    return size != null ? size : 0L;
  }

  private long quotaOf(User user) {
    Long quota = user.getStorageQuotaBytes();
    return quota != null ? quota : 0L;
  }

  private Long systemBackendId() {
    Optional<StorageBackend> backend = backendRepository.findBySystemDefaultTrue();
    if (backend.isEmpty()) {
      log.warn("No system default storage backend row — treating metered usage as zero");
      return null;
    }
    return backend.get().getId();
  }
}
