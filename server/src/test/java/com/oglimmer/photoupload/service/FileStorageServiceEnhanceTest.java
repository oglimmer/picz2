/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.JobType;
import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.ResourceGoneException;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.exception.ValidationException;
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
import java.nio.file.Path;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.Mockito;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionStatus;

/**
 * The api side of the one-tap enhance (D81): the same gate as rotate, then a reset-and-enqueue of
 * an {@code ENHANCE} job. The pixels are the worker's business.
 */
class FileStorageServiceEnhanceTest {

  private static final long USER_ID = 7L;
  private static final long OWN_FILE = 100L;
  private static final long FOREIGN_FILE = 200L;

  private FileMetadataRepository metaRepo;
  private JobEnqueueService jobs;
  private BackendStorage bucket;
  private FileStorageService svc;

  @BeforeEach
  void setUp(@TempDir Path tempDir) {
    FileStorageProperties props = new FileStorageProperties();
    props.setUploadDir(tempDir.toString());

    metaRepo = Mockito.mock(FileMetadataRepository.class);
    jobs = Mockito.mock(JobEnqueueService.class);
    bucket = Mockito.mock(BackendStorage.class);
    ObjectStorageService storage = Mockito.mock(ObjectStorageService.class);
    when(storage.forFile(any())).thenReturn(bucket);
    UserContext userContext = Mockito.mock(UserContext.class);
    PlatformTransactionManager txManager = Mockito.mock(PlatformTransactionManager.class);
    when(txManager.getTransaction(any())).thenReturn(Mockito.mock(TransactionStatus.class));

    User user = new User();
    user.setId(USER_ID);
    user.setEmail("owner@example.com");
    when(userContext.getCurrentUser()).thenReturn(user);

    svc =
        new FileStorageService(
            props,
            metaRepo,
            Mockito.mock(TagRepository.class),
            Mockito.mock(ImageTagRepository.class),
            Mockito.mock(AlbumEnabledTagRepository.class),
            Mockito.mock(JdbcTemplate.class),
            Mockito.mock(AlbumRepository.class),
            Mockito.mock(SlideshowRecordingRepository.class),
            Mockito.mock(StorageBackendRepository.class),
            Mockito.mock(FileInfoMapper.class),
            userContext,
            txManager,
            jobs,
            Mockito.mock(SystemTagProvisioner.class),
            Mockito.mock(StorageQuotaService.class),
            storage);
  }

  private FileMetadata ownImage() {
    FileMetadata md = new FileMetadata();
    md.setId(OWN_FILE);
    md.setOriginalName("sunset.jpg");
    md.setStoredFilename("sunset-stored.jpg");
    md.setMimeType("image/jpeg");
    md.setFilePath("originals/sunset-stored.jpg");
    md.setProcessingStatus(ProcessingStatus.DONE);
    md.setProcessingAttempts(3);
    md.setProcessingError("old noise");
    when(metaRepo.findByIdAndUserId(OWN_FILE, USER_ID)).thenReturn(Optional.of(md));
    when(metaRepo.findById(OWN_FILE)).thenReturn(Optional.of(md));
    return md;
  }

  @Test
  void enhanceResetsTheRowAndEnqueuesAnEnhanceJob() {
    FileMetadata md = ownImage();

    svc.enhanceImage(OWN_FILE);

    verify(jobs).enqueue(OWN_FILE, JobType.ENHANCE);
    verify(metaRepo).save(md);
    assertThat(md.getProcessingStatus()).isEqualTo(ProcessingStatus.QUEUED);
    assertThat(md.getProcessingAttempts()).isZero();
    assertThat(md.getProcessingError()).isNull();
  }

  @Test
  void previewUsesTheSameGateAndItsOwnJobType() {
    FileMetadata md = ownImage();

    svc.enqueueEnhancePreview(OWN_FILE);

    verify(jobs).enqueue(OWN_FILE, JobType.ENHANCE_PREVIEW);
    assertThat(md.getProcessingStatus()).isEqualTo(ProcessingStatus.QUEUED);
    md.setMimeType("video/mp4");
    assertThrows(ValidationException.class, () -> svc.enqueueEnhancePreview(OWN_FILE));
  }

  @Test
  void previewIs404UntilTheWorkerHasWrittenIt() {
    ownImage();
    when(bucket.exists("derivatives/100/enhance-preview.jpg")).thenReturn(false);

    assertThrows(ResourceNotFoundException.class, () -> svc.openEnhancePreview(OWN_FILE));

    when(bucket.exists("derivatives/100/enhance-preview.jpg")).thenReturn(true);
    svc.openEnhancePreview(OWN_FILE);
    verify(bucket).openStream("derivatives/100/enhance-preview.jpg");
  }

  @Test
  void previewIsNeverAnotherUsers() {
    when(metaRepo.findByIdAndUserId(FOREIGN_FILE, USER_ID)).thenReturn(Optional.empty());

    assertThrows(ResourceNotFoundException.class, () -> svc.openEnhancePreview(FOREIGN_FILE));
    assertThrows(ResourceNotFoundException.class, () -> svc.discardEnhancePreview(FOREIGN_FILE));
    assertThrows(ResourceNotFoundException.class, () -> svc.enqueueEnhancePreview(FOREIGN_FILE));

    verify(bucket, never()).delete(any());
    verify(jobs, never()).enqueue(any(), any());
  }

  @Test
  void discardDeletesTheKeyAndNothingElse() {
    FileMetadata md = ownImage();

    svc.discardEnhancePreview(OWN_FILE);

    verify(bucket).delete("derivatives/100/enhance-preview.jpg");
    verify(jobs, never()).enqueue(any(), any());
    assertThat(md.getProcessingStatus()).isEqualTo(ProcessingStatus.DONE);
  }

  @Test
  void enhanceRefusesAnotherUsersFile() {
    when(metaRepo.findByIdAndUserId(FOREIGN_FILE, USER_ID)).thenReturn(Optional.empty());

    assertThrows(ResourceNotFoundException.class, () -> svc.enhanceImage(FOREIGN_FILE));

    verify(jobs, never()).enqueue(any(), any());
    verify(metaRepo, never()).save(any());
  }

  @Test
  void enhanceRefusesVideos() {
    FileMetadata md = ownImage();
    md.setMimeType("video/mp4");

    ValidationException ex =
        assertThrows(ValidationException.class, () -> svc.enhanceImage(OWN_FILE));

    assertThat(ex.getMessage()).contains("enhanced");
    verify(jobs, never()).enqueue(any(), any());
  }

  @Test
  void enhanceFallsBackToADerivativeWhenTheOriginalWasPurged() {
    FileMetadata md = ownImage();
    md.setFilePath(null);
    md.setLargePath("derivatives/100/large.jpg");

    svc.enhanceImage(OWN_FILE);

    verify(jobs).enqueue(OWN_FILE, JobType.ENHANCE);
  }

  @Test
  void enhanceIsGoneWhenNothingIsLeftToReadFrom() {
    FileMetadata md = ownImage();
    md.setFilePath(null);

    assertThrows(ResourceGoneException.class, () -> svc.enhanceImage(OWN_FILE));

    verify(jobs, never()).enqueue(any(), any());
  }
}
