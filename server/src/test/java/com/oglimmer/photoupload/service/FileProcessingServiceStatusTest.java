/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import java.io.IOException;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionStatus;

class FileProcessingServiceStatusTest {

  private FileStorageProperties properties;
  private FileMetadataRepository repository;
  private ThumbnailService thumbnailService;
  private PlatformTransactionManager txManager;
  private FileProcessingService service;

  /** Snapshot of (status, attempts, error, completedAt) recorded at each save() call. */
  private record Snapshot(
      ProcessingStatus status, Integer attempts, String error, Instant completedAt) {}

  private final List<Snapshot> saves = new ArrayList<>();

  @BeforeEach
  void setUp(@TempDir Path tempDir) {
    saves.clear();
    properties = new FileStorageProperties();
    properties.setUploadDir(tempDir.toString());
    repository = mock(FileMetadataRepository.class);
    thumbnailService = mock(ThumbnailService.class);
    txManager = mock(PlatformTransactionManager.class);
    when(txManager.getTransaction(any())).thenReturn(mock(TransactionStatus.class));
    when(repository.save(any(FileMetadata.class)))
        .thenAnswer(
            inv -> {
              FileMetadata fm = inv.getArgument(0);
              saves.add(
                  new Snapshot(
                      fm.getProcessingStatus(),
                      fm.getProcessingAttempts(),
                      fm.getProcessingError(),
                      fm.getProcessingCompletedAt()));
              return fm;
            });
    service = new FileProcessingService(properties, repository, thumbnailService, txManager);
  }

  private FileMetadata seedMetadata() {
    FileMetadata md = new FileMetadata();
    md.setId(11L);
    md.setOriginalName("photo.jpg");
    md.setStoredFilename("photo-stored.jpg");
    md.setMimeType("image/jpeg");
    md.setFilePath("photo-stored.jpg");
    md.setProcessingStatus(ProcessingStatus.INGESTED);
    md.setProcessingAttempts(0);
    return md;
  }

  @Test
  void successfulProcessingTransitionsToDoneAndIncrementsAttempts() {
    FileMetadata md = seedMetadata();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.isImageFile("image/jpeg")).thenReturn(true);
    when(thumbnailService.generateAllThumbnails(any(), any())).thenReturn(new Path[3]);

    service.processFile(11L);

    assertThat(saves).hasSize(2);
    Snapshot first = saves.get(0);
    assertThat(first.status()).isEqualTo(ProcessingStatus.PROCESSING);
    assertThat(first.attempts()).isEqualTo(1);
    assertThat(first.error()).isNull();

    Snapshot last = saves.get(1);
    assertThat(last.status()).isEqualTo(ProcessingStatus.DONE);
    assertThat(last.completedAt()).isNotNull();
    assertThat(last.error()).isNull();
  }

  @Test
  void failureTransitionsToFailedWithErrorMessage() {
    FileMetadata md = seedMetadata();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.isImageFile("image/jpeg")).thenReturn(true);
    when(thumbnailService.generateAllThumbnails(any(), any()))
        .thenThrow(new RuntimeException("boom"));

    service.processFile(11L);

    assertThat(saves).hasSize(2);
    assertThat(saves.get(0).status()).isEqualTo(ProcessingStatus.PROCESSING);
    Snapshot last = saves.get(1);
    assertThat(last.status()).isEqualTo(ProcessingStatus.FAILED);
    assertThat(last.error()).contains("boom");
    assertThat(last.completedAt()).isNotNull();
  }

  @Test
  void ioErrorIsRecordedAsFailed() {
    FileMetadata md = seedMetadata();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.isImageFile("image/jpeg")).thenReturn(true);
    when(thumbnailService.generateAllThumbnails(any(), any()))
        .thenThrow(new RuntimeException(new IOException("disk full")));

    service.processFile(11L);

    assertThat(saves).hasSize(2);
    Snapshot last = saves.get(1);
    assertThat(last.status()).isEqualTo(ProcessingStatus.FAILED);
    assertThat(last.error()).contains("disk full");
  }

  @Test
  void missingMetadataIsLoggedAndSkipped() {
    when(repository.findById(99L)).thenReturn(Optional.empty());

    service.processFile(99L);

    verify(repository, times(0)).save(any());
    assertThat(saves).isEmpty();
  }
}
