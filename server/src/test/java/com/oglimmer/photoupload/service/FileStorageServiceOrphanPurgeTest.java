/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.mapper.FileInfoMapper;
import com.oglimmer.photoupload.repository.AlbumEnabledTagRepository;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.ImageTagRepository;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.io.IOException;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * The orphan sweep decides what to delete from a set of keys the DB knows about. It used to build
 * that set from {@code file_metadata} alone, so every slideshow narration in the bucket looked like
 * garbage and one run deleted the lot — the rows stayed, pointing at keys that no longer existed.
 * These pin the two things that must never be swept: recording audio and in-flight TUS uploads.
 */
class FileStorageServiceOrphanPurgeTest {

  private FileMetadataRepository metaRepo;
  private SlideshowRecordingRepository recordingRepo;
  private ObjectStorageService storage;
  private FileStorageService svc;

  @BeforeEach
  void setUp(@TempDir Path tempDir) {
    FileStorageProperties props = new FileStorageProperties();
    props.setUploadDir(tempDir.toString());

    metaRepo = mock(FileMetadataRepository.class);
    recordingRepo = mock(SlideshowRecordingRepository.class);
    storage = mock(ObjectStorageService.class);

    svc =
        new FileStorageService(
            props,
            metaRepo,
            mock(TagRepository.class),
            mock(ImageTagRepository.class),
            mock(AlbumEnabledTagRepository.class),
            mock(LocalFileCleanupService.class),
            mock(JdbcTemplate.class),
            mock(AlbumRepository.class),
            recordingRepo,
            mock(FileInfoMapper.class),
            mock(UserContext.class),
            mock(PlatformTransactionManager.class),
            mock(JobEnqueueService.class),
            mock(SystemTagProvisioner.class),
            Optional.of(storage));
  }

  @Test
  void recordingAudioAndItsAacSiblingAreNotOrphans() throws IOException {
    when(metaRepo.findAllStoredPaths()).thenReturn(List.of("originals/photo.jpg"));
    when(recordingRepo.findAllAudioPaths()).thenReturn(List.of("audio/abc.webm"));
    when(recordingRepo.findAllAudioFilenames()).thenReturn(List.of("abc.webm"));
    when(storage.listKeys())
        .thenReturn(List.of("originals/photo.jpg", "audio/abc.webm", "audio/abc.m4a"));

    Map<String, Object> result = svc.purgeOrphanedS3Objects(false);

    assertEquals(0, result.get("orphaned"));
    verify(storage, never()).delete(anyString());
  }

  @Test
  void inFlightTusUploadsAreSkippedRatherThanCountedAsGarbage() {
    when(metaRepo.findAllStoredPaths()).thenReturn(List.of());
    when(recordingRepo.findAllAudioPaths()).thenReturn(List.of());
    when(recordingRepo.findAllAudioFilenames()).thenReturn(List.of());
    when(storage.listKeys()).thenReturn(List.of("tus-uploads/abc", "tus-uploads/abc.info"));

    Map<String, Object> result = svc.purgeOrphanedS3Objects(false);

    assertEquals(2, result.get("skippedInFlight"));
    assertEquals(0, result.get("orphaned"));
    verify(storage, never()).delete(anyString());
  }

  @Test
  void aTrulyUnownedKeyIsStillDeleted() {
    when(metaRepo.findAllStoredPaths()).thenReturn(List.of("originals/kept.jpg"));
    when(recordingRepo.findAllAudioPaths()).thenReturn(List.of());
    when(recordingRepo.findAllAudioFilenames()).thenReturn(List.of());
    when(storage.listKeys()).thenReturn(List.of("originals/kept.jpg", "originals/stray.jpg"));

    Map<String, Object> result = svc.purgeOrphanedS3Objects(false);

    assertEquals(1, result.get("orphaned"));
    assertEquals(1, result.get("deleted"));
    verify(storage).delete("originals/stray.jpg");
  }

  @Test
  void aDryRunDeletesNothing() {
    when(metaRepo.findAllStoredPaths()).thenReturn(List.of());
    when(recordingRepo.findAllAudioPaths()).thenReturn(List.of());
    when(recordingRepo.findAllAudioFilenames()).thenReturn(List.of());
    when(storage.listKeys()).thenReturn(List.of("originals/stray.jpg"));

    Map<String, Object> result = svc.purgeOrphanedS3Objects(true);

    assertEquals(1, result.get("orphaned"));
    assertEquals(0, result.get("deleted"));
    verify(storage, never()).delete(anyString());
  }
}
