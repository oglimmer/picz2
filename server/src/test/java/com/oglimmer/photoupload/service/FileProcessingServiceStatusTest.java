/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.model.CaptureDate;
import com.oglimmer.photoupload.model.GpsCoordinates;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.storage.BackendStorage;
import java.io.IOException;
import java.nio.file.Files;
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
  private CaptureDateExtractor captureDateExtractor;
  private GpsExtractor gpsExtractor;
  private PlatformTransactionManager txManager;
  private BackendStorage bucket;
  private FileProcessingService service;

  /** Snapshot of (status, attempts, error, completedAt) recorded at each save() call. */
  private record Snapshot(
      ProcessingStatus status, Integer attempts, String error, Instant completedAt) {}

  private final List<Snapshot> saves = new ArrayList<>();

  private Path uploadDir;

  @BeforeEach
  void setUp(@TempDir Path tempDir) {
    saves.clear();
    uploadDir = tempDir;
    properties = new FileStorageProperties();
    properties.setUploadDir(tempDir.toString());
    repository = mock(FileMetadataRepository.class);
    thumbnailService = mock(ThumbnailService.class);
    captureDateExtractor = mock(CaptureDateExtractor.class);
    when(captureDateExtractor.extract(any(), any())).thenReturn(CaptureDate.none());
    gpsExtractor = mock(GpsExtractor.class);
    when(gpsExtractor.extract(any(), any())).thenReturn(GpsCoordinates.none());
    txManager = mock(PlatformTransactionManager.class);
    when(txManager.getTransaction(any())).thenReturn(mock(TransactionStatus.class));
    // The album's backend: the GET of the original is a no-op here (the thumbnailer is mocked and
    // never reads it) and every PUT is swallowed.
    ObjectStorageService objectStorage = mock(ObjectStorageService.class);
    bucket = mock(BackendStorage.class);
    when(objectStorage.forFile(any())).thenReturn(bucket);
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
    service =
        new FileProcessingService(
            properties,
            repository,
            thumbnailService,
            captureDateExtractor,
            gpsExtractor,
            txManager,
            objectStorage);
  }

  private FileMetadata seedMetadata() {
    FileMetadata md = new FileMetadata();
    md.setId(11L);
    md.setOriginalName("photo.jpg");
    md.setStoredFilename("photo-stored.jpg");
    md.setMimeType("image/jpeg");
    md.setFilePath("originals/photo-stored.jpg");
    md.setProcessingStatus(ProcessingStatus.QUEUED);
    md.setProcessingAttempts(0);
    return md;
  }

  @Test
  void successfulProcessingTransitionsToDoneAndIncrementsAttempts() throws IOException {
    FileMetadata md = seedMetadata();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.generateAllThumbnails(any(), any())).thenReturn(generatedThumbnails());

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
    // Every derivative went to its deterministic key in the album's backend.
    verify(bucket).putFile(eq("derivatives/11/thumb.jpg"), any(), eq("image/jpeg"));
    verify(bucket).putFile(eq("derivatives/11/medium.jpg"), any(), eq("image/jpeg"));
    verify(bucket).putFile(eq("derivatives/11/large.jpg"), any(), eq("image/jpeg"));
  }

  /**
   * What a successful {@code generateAllThumbnails} returns: one path per size. An array of three
   * nulls is its "every size failed" signal, and {@code processFile} throws on it rather than
   * marking an asset DONE with no derivatives — so a run stubbed that way is a *failed* run.
   */
  private Path[] generatedThumbnails() throws IOException {
    Path[] paths = {
      uploadDir.resolve("photo-stored-thumb.jpg"),
      uploadDir.resolve("photo-stored-medium.jpg"),
      uploadDir.resolve("photo-stored-large.jpg"),
    };
    // storeDerivative sizes each file before the PUT, so they have to exist.
    for (Path path : paths) {
      Files.writeString(path, "jpeg-bytes");
    }
    return paths;
  }

  @Test
  void failureTransitionsToFailedWithErrorMessage() {
    FileMetadata md = seedMetadata();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
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

  /**
   * The two in-place rewrites share one flow (D81). Rotate is the one that changes geometry, so it
   * is the control: enhance must leave rotation and dimensions exactly where they were.
   */
  private FileMetadata seedDoneImage() {
    FileMetadata md = seedMetadata();
    md.setProcessingStatus(ProcessingStatus.QUEUED);
    md.setRotation(90);
    md.setWidth(4000);
    md.setHeight(3000);
    md.setPublicToken("old-token");
    return md;
  }

  @Test
  void enhanceRewritesTheOriginalAndKeepsGeometry() throws IOException {
    FileMetadata md = seedDoneImage();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.enhanceImage(any())).thenReturn(true);
    when(thumbnailService.generateAllThumbnails(any(), any())).thenReturn(generatedThumbnails());

    service.enhanceAndReprocess(11L);

    assertThat(saves).hasSize(2);
    assertThat(saves.get(1).status()).isEqualTo(ProcessingStatus.DONE);
    verify(thumbnailService).enhanceImage(any());
    verify(bucket).getToFile(eq("originals/photo-stored.jpg"), any());
    verify(bucket).putFile(eq("originals/photo-stored.jpg"), any(), eq("image/jpeg"));
    verify(bucket).putFile(eq("derivatives/11/large.jpg"), any(), eq("image/jpeg"));
    assertThat(md.getRotation()).isEqualTo(90);
    assertThat(md.getWidth()).isEqualTo(4000);
    assertThat(md.getHeight()).isEqualTo(3000);
    assertThat(md.getPublicToken()).isNotEqualTo("old-token");
  }

  @Test
  void rotateStillSwapsDimensionsAndAdvancesRotation() throws IOException {
    FileMetadata md = seedDoneImage();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.rotateImageLeft(any())).thenReturn(true);
    when(thumbnailService.generateAllThumbnails(any(), any())).thenReturn(generatedThumbnails());

    service.rotateAndReprocess(11L);

    assertThat(saves.get(1).status()).isEqualTo(ProcessingStatus.DONE);
    assertThat(md.getRotation()).isEqualTo(180);
    assertThat(md.getWidth()).isEqualTo(3000);
    assertThat(md.getHeight()).isEqualTo(4000);
  }

  @Test
  void enhanceToolFailureIsRecordedAndTouchesNoStorage() {
    FileMetadata md = seedDoneImage();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.enhanceImage(any())).thenReturn(false);

    service.enhanceAndReprocess(11L);

    assertThat(saves.get(1).status()).isEqualTo(ProcessingStatus.FAILED);
    assertThat(saves.get(1).error()).contains("enhance failed");
    verify(bucket, times(0)).putFile(any(), any(), any());
    assertThat(md.getRotation()).isEqualTo(90);
  }

  @Test
  void previewWritesOneKeyAndMovesNothingElse() {
    FileMetadata md = seedDoneImage();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.generateLargeCopy(any(), any()))
        .thenAnswer(
            inv -> {
              Files.writeString(inv.getArgument(1), "jpeg-bytes");
              return true;
            });
    when(thumbnailService.enhanceImage(any())).thenReturn(true);

    service.buildEnhancePreview(11L);

    assertThat(saves.get(1).status()).isEqualTo(ProcessingStatus.DONE);
    verify(bucket).getToFile(eq("originals/photo-stored.jpg"), any());
    verify(bucket).putFile(eq("derivatives/11/enhance-preview.jpg"), any(), eq("image/jpeg"));
    verify(bucket, times(1)).putFile(any(), any(), any());
    verify(thumbnailService, times(0)).generateAllThumbnails(any(), any());
    assertThat(md.getPublicToken()).isEqualTo("old-token");
    assertThat(md.getRotation()).isEqualTo(90);
  }

  @Test
  void previewFailureIsRecordedAndWritesNothing() {
    FileMetadata md = seedDoneImage();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.generateLargeCopy(any(), any())).thenReturn(false);

    service.buildEnhancePreview(11L);

    assertThat(saves.get(1).status()).isEqualTo(ProcessingStatus.FAILED);
    assertThat(saves.get(1).error()).contains("large copy");
    verify(bucket, times(0)).putFile(any(), any(), any());
  }

  @Test
  void acceptedEnhanceDropsThePreview() throws IOException {
    FileMetadata md = seedDoneImage();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.enhanceImage(any())).thenReturn(true);
    when(thumbnailService.generateAllThumbnails(any(), any())).thenReturn(generatedThumbnails());

    service.enhanceAndReprocess(11L);

    verify(bucket).delete("derivatives/11/enhance-preview.jpg");
  }

  /**
   * D83. The mark is what keeps a second bulk enhance off this asset, so it has to be written by
   * the job that did the work — not by the api when it enqueued one, which would claim an enhance
   * that a dead-lettered job never performed.
   */
  @Test
  void enhanceStampsEnhancedAt() throws IOException {
    FileMetadata md = seedDoneImage();
    assertThat(md.getEnhancedAt()).isNull();
    Instant before = Instant.now();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.enhanceImage(any())).thenReturn(true);
    when(thumbnailService.generateAllThumbnails(any(), any())).thenReturn(generatedThumbnails());

    service.enhanceAndReprocess(11L);

    assertThat(saves.get(1).status()).isEqualTo(ProcessingStatus.DONE);
    assertThat(md.getEnhancedAt()).isNotNull().isAfterOrEqualTo(before);
  }

  /** A tool failure leaves the asset exactly as enhanceable as it was — no mark, no skip. */
  @Test
  void failedEnhanceLeavesEnhancedAtUnset() {
    FileMetadata md = seedDoneImage();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.enhanceImage(any())).thenReturn(false);

    service.enhanceAndReprocess(11L);

    assertThat(md.getEnhancedAt()).isNull();
  }

  /** Rotate shares the rewrite flow but is not an enhance, so it must not claim to be one. */
  @Test
  void rotateDoesNotStampEnhancedAt() throws IOException {
    FileMetadata md = seedDoneImage();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.rotateImageLeft(any())).thenReturn(true);
    when(thumbnailService.generateAllThumbnails(any(), any())).thenReturn(generatedThumbnails());

    service.rotateAndReprocess(11L);

    assertThat(md.getEnhancedAt()).isNull();
  }

  /** The preview (D82) writes one key and nothing on the row — accepting is what marks it. */
  @Test
  void enhancePreviewDoesNotStampEnhancedAt() throws IOException {
    FileMetadata md = seedDoneImage();
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.enhanceImage(any())).thenReturn(true);

    service.buildEnhancePreview(11L);

    assertThat(md.getEnhancedAt()).isNull();
  }

  @Test
  void enhanceDoesNotResurrectAPurgedOriginal() throws IOException {
    FileMetadata md = seedDoneImage();
    md.setFilePath(null);
    md.setLargePath("derivatives/11/large.jpg");
    when(repository.findById(11L)).thenReturn(Optional.of(md));
    when(thumbnailService.enhanceImage(any())).thenReturn(true);
    when(thumbnailService.generateAllThumbnails(any(), any())).thenReturn(generatedThumbnails());

    service.enhanceAndReprocess(11L);

    assertThat(saves.get(1).status()).isEqualTo(ProcessingStatus.DONE);
    verify(bucket).getToFile(eq("derivatives/11/large.jpg"), any());
    verify(bucket, times(0)).putFile(eq("originals/photo-stored.jpg"), any(), any());
    assertThat(md.getFilePath()).isNull();
  }
}
