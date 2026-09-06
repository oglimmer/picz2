/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.entity.StorageBackend;
import com.oglimmer.photoupload.mapper.FileInfoMapper;
import com.oglimmer.photoupload.repository.AlbumEnabledTagRepository;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.ImageTagRepository;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.repository.StorageBackendRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import com.oglimmer.photoupload.storage.BackendStorage;
import com.oglimmer.photoupload.config.JobsProperties;
import java.io.IOException;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.mockito.Mockito;

/**
 * The orphan sweep decides what to delete from a set of keys the DB knows about. It used to build
 * that set from {@code file_metadata} alone, so every slideshow narration in the bucket looked like
 * garbage and one run deleted the lot — the rows stayed, pointing at keys that no longer existed.
 * These pin the two things that must never be swept: recording audio and in-flight TUS uploads.
 */
class FileStorageServiceOrphanPurgeTest {

  private static final Long BACKEND_ID = 1L;

  private FileMetadataRepository metaRepo;
  private SlideshowRecordingRepository recordingRepo;
  private StorageBackendRepository backendRepo;
  private ObjectStorageService storage;

  /** The bucket handle for the one backend these tests sweep. */
  private BackendStorage bucket;

  private FileStorageService svc;

  @BeforeEach
  void setUp(@TempDir Path tempDir) {
    FileStorageProperties props = new FileStorageProperties();
    props.setUploadDir(tempDir.toString());

    metaRepo = mock(FileMetadataRepository.class);
    recordingRepo = mock(SlideshowRecordingRepository.class);
    backendRepo = mock(StorageBackendRepository.class);
    storage = mock(ObjectStorageService.class);
    bucket = mock(BackendStorage.class);

    StorageBackend backend = new StorageBackend();
    backend.setId(BACKEND_ID);
    backend.setName("Default storage");
    backend.setSystemDefault(true);
    when(backendRepo.findAll()).thenReturn(List.of(backend));
    when(storage.forBackend(backend)).thenReturn(bucket);

    svc =
        new FileStorageService(
            props,
            metaRepo,
            mock(TagRepository.class),
            mock(ImageTagRepository.class),
            mock(AlbumEnabledTagRepository.class),
            mock(JdbcTemplate.class),
            mock(AlbumRepository.class),
            recordingRepo,
            backendRepo,
            mock(FileInfoMapper.class),
            mock(UserContext.class),
            mock(PlatformTransactionManager.class),
            mock(JobEnqueueService.class),
            mock(SystemTagProvisioner.class),
            mock(StorageQuotaService.class),
            storage,
            Mockito.mock(JobQueueDepthService.class),
            new JobsProperties());
  }

  @Test
  void recordingAudioAndItsAacSiblingAreNotOrphans() throws IOException {
    when(metaRepo.findStoredPathsByStorageBackend(BACKEND_ID))
        .thenReturn(List.of("originals/photo.jpg"));
    when(recordingRepo.findAudioPathsByStorageBackend(BACKEND_ID))
        .thenReturn(List.of("audio/abc.webm"));
    when(recordingRepo.findAudioFilenamesByStorageBackend(BACKEND_ID))
        .thenReturn(List.of("abc.webm"));
    when(bucket.listKeys())
        .thenReturn(List.of("originals/photo.jpg", "audio/abc.webm", "audio/abc.m4a"));

    Map<String, Object> result = svc.purgeOrphanedS3Objects(false);

    assertEquals(0, result.get("orphaned"));
    verify(bucket, never()).delete(anyString());
  }

  @Test
  void inFlightTusUploadsAreSkippedRatherThanCountedAsGarbage() {
    when(metaRepo.findStoredPathsByStorageBackend(BACKEND_ID)).thenReturn(List.of());
    when(recordingRepo.findAudioPathsByStorageBackend(BACKEND_ID)).thenReturn(List.of());
    when(recordingRepo.findAudioFilenamesByStorageBackend(BACKEND_ID)).thenReturn(List.of());
    when(bucket.listKeys()).thenReturn(List.of("tus-uploads/abc", "tus-uploads/abc.info"));

    Map<String, Object> result = svc.purgeOrphanedS3Objects(false);

    assertEquals(2, result.get("skippedInFlight"));
    assertEquals(0, result.get("orphaned"));
    verify(bucket, never()).delete(anyString());
  }

  @Test
  void aTrulyUnownedKeyIsStillDeleted() {
    when(metaRepo.findStoredPathsByStorageBackend(BACKEND_ID))
        .thenReturn(List.of("originals/kept.jpg"));
    when(recordingRepo.findAudioPathsByStorageBackend(BACKEND_ID)).thenReturn(List.of());
    when(recordingRepo.findAudioFilenamesByStorageBackend(BACKEND_ID)).thenReturn(List.of());
    when(bucket.listKeys()).thenReturn(List.of("originals/kept.jpg", "originals/stray.jpg"));

    Map<String, Object> result = svc.purgeOrphanedS3Objects(false);

    assertEquals(1, result.get("orphaned"));
    assertEquals(1, result.get("deleted"));
    verify(bucket).delete("originals/stray.jpg");
  }

  @Test
  void aDryRunDeletesNothing() {
    when(metaRepo.findStoredPathsByStorageBackend(BACKEND_ID)).thenReturn(List.of());
    when(recordingRepo.findAudioPathsByStorageBackend(BACKEND_ID)).thenReturn(List.of());
    when(recordingRepo.findAudioFilenamesByStorageBackend(BACKEND_ID)).thenReturn(List.of());
    when(bucket.listKeys()).thenReturn(List.of("originals/stray.jpg"));

    Map<String, Object> result = svc.purgeOrphanedS3Objects(true);

    assertEquals(1, result.get("orphaned"));
    assertEquals(0, result.get("deleted"));
    verify(bucket, never()).delete(anyString());
  }
}
