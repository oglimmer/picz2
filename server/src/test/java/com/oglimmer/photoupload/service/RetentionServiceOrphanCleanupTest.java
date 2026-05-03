/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.RetentionProperties;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import java.time.Instant;
import java.util.List;
import java.util.stream.IntStream;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * Phase 5 follow-up — covers the orphan-detection pass added to {@link RetentionService}. Mirrors
 * the shape of {@link RetentionServiceTusCleanupTest}; the originals-purge sweep ({@code run()})
 * is exercised separately in production.
 */
@ExtendWith(MockitoExtension.class)
class RetentionServiceOrphanCleanupTest {

  @Mock FileMetadataRepository metadataRepository;
  @Mock ObjectStorageService objectStorage;
  @Mock RetentionProperties properties;
  @Mock PlatformTransactionManager transactionManager;

  @InjectMocks RetentionService service;

  @BeforeEach
  void setUp() {
    when(properties.getOrphanGraceHours()).thenReturn(24);
  }

  @Test
  void emptyListIsNoOp() {
    when(properties.getMaxRowsPerRun()).thenReturn(5000);
    when(properties.isDryRun()).thenReturn(false);
    when(metadataRepository.findAllOriginalsKeys()).thenReturn(List.of());
    when(objectStorage.listKeysOlderThan(eq("originals/"), any(Instant.class)))
        .thenReturn(List.of());

    RetentionService.Result result = service.runOriginalsOrphanCleanup();

    assertEquals(0, result.eligible());
    assertEquals(0, result.purged());
    assertEquals(0, result.failed());
    verify(objectStorage, never()).delete(any());
  }

  @Test
  void liveKeysAreNotDeleted() {
    when(properties.getMaxRowsPerRun()).thenReturn(5000);
    when(properties.isDryRun()).thenReturn(false);
    when(metadataRepository.findAllOriginalsKeys())
        .thenReturn(List.of("originals/keep-me.jpg", "originals/also-live.heic"));
    when(objectStorage.listKeysOlderThan(eq("originals/"), any(Instant.class)))
        .thenReturn(List.of("originals/keep-me.jpg", "originals/also-live.heic"));

    RetentionService.Result result = service.runOriginalsOrphanCleanup();

    assertEquals(0, result.eligible());
    verify(objectStorage, never()).delete(any());
  }

  @Test
  void deletesOnlyKeysWithNoLiveRow() {
    when(properties.getMaxRowsPerRun()).thenReturn(5000);
    when(properties.isDryRun()).thenReturn(false);
    when(metadataRepository.findAllOriginalsKeys())
        .thenReturn(List.of("originals/live-1.jpg", "originals/live-2.jpg"));
    when(objectStorage.listKeysOlderThan(eq("originals/"), any(Instant.class)))
        .thenReturn(
            List.of(
                "originals/live-1.jpg",
                "originals/orphan-a.jpg",
                "originals/live-2.jpg",
                "originals/orphan-b.heic"));

    RetentionService.Result result = service.runOriginalsOrphanCleanup();

    assertEquals(2, result.eligible());
    assertEquals(2, result.purged());
    assertEquals(0, result.failed());
    verify(objectStorage, times(1)).delete("originals/orphan-a.jpg");
    verify(objectStorage, times(1)).delete("originals/orphan-b.heic");
    verify(objectStorage, never()).delete("originals/live-1.jpg");
    verify(objectStorage, never()).delete("originals/live-2.jpg");
  }

  @Test
  void dryRunSkipsDelete() {
    when(properties.getMaxRowsPerRun()).thenReturn(5000);
    when(properties.isDryRun()).thenReturn(true);
    when(metadataRepository.findAllOriginalsKeys()).thenReturn(List.of());
    when(objectStorage.listKeysOlderThan(eq("originals/"), any(Instant.class)))
        .thenReturn(List.of("originals/orphan-a.jpg", "originals/orphan-b.jpg"));

    RetentionService.Result result = service.runOriginalsOrphanCleanup();

    assertEquals(2, result.eligible());
    assertEquals(0, result.purged());
    assertTrue(result.dryRun());
    verify(objectStorage, never()).delete(any());
  }

  @Test
  void respectsMaxRowsCap() {
    when(properties.getMaxRowsPerRun()).thenReturn(2);
    when(properties.isDryRun()).thenReturn(false);
    when(metadataRepository.findAllOriginalsKeys()).thenReturn(List.of());
    List<String> tenKeys =
        IntStream.range(0, 10).mapToObj(i -> "originals/orphan-" + i + ".jpg").toList();
    when(objectStorage.listKeysOlderThan(eq("originals/"), any(Instant.class))).thenReturn(tenKeys);

    RetentionService.Result result = service.runOriginalsOrphanCleanup();

    // Same semantics as the TUS sweep — eligibility reflects the truncated set; remaining
    // orphans flow through on the next nightly firing.
    assertEquals(2, result.eligible());
    assertEquals(2, result.purged());
    verify(objectStorage, times(2)).delete(any());
  }

  @Test
  void deleteFailureCountsAsFailed() {
    when(properties.getMaxRowsPerRun()).thenReturn(5000);
    when(properties.isDryRun()).thenReturn(false);
    when(metadataRepository.findAllOriginalsKeys()).thenReturn(List.of());
    when(objectStorage.listKeysOlderThan(eq("originals/"), any(Instant.class)))
        .thenReturn(List.of("originals/ok.jpg", "originals/dead.jpg"));
    doAnswer(
            inv -> {
              if ("originals/dead.jpg".equals(inv.getArgument(0))) {
                throw new RuntimeException("S3 down");
              }
              return null;
            })
        .when(objectStorage)
        .delete(anyString());

    RetentionService.Result result = service.runOriginalsOrphanCleanup();

    assertEquals(2, result.eligible());
    assertEquals(1, result.purged());
    assertEquals(1, result.failed());
  }

  @Test
  void zeroGraceHoursRefusesToRun() {
    when(properties.getOrphanGraceHours()).thenReturn(0);
    when(properties.isDryRun()).thenReturn(false);

    RetentionService.Result result = service.runOriginalsOrphanCleanup();

    assertEquals(0, result.eligible());
    verifyNoInteractions(objectStorage);
    verifyNoInteractions(metadataRepository);
  }
}
