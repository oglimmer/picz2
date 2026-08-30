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
import com.oglimmer.photoupload.repository.StorageBackendRepository;
import com.oglimmer.photoupload.storage.BackendStorage;
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
 * Phase 5 follow-up — covers the TUS-uploads cleanup pass added to {@link RetentionService}. The
 * originals sweep ({@code run()}) is exercised separately in production; this test only spans the
 * second pass introduced after the R1 deploy revealed tusd 2.x has no in-process expiry.
 */
@ExtendWith(MockitoExtension.class)
class RetentionServiceTusCleanupTest {

  @Mock FileMetadataRepository metadataRepository;
  @Mock StorageBackendRepository storageBackendRepository;
  @Mock ObjectStorageService objectStorage;

  /**
   * The staging bucket handle. tus-uploads/ only ever exists on the instance's own storage, so this
   * pass asks the router for the system default and never touches a user's backend.
   */
  @Mock BackendStorage staging;

  @Mock RetentionProperties properties;
  @Mock PlatformTransactionManager transactionManager;

  @InjectMocks RetentionService service;

  @BeforeEach
  void setUp() {
    when(properties.getTusUploadDays()).thenReturn(7);
  }

  @Test
  void emptyPrefixIsNoOp() {
    when(properties.getMaxRowsPerRun()).thenReturn(5000);
    when(properties.isDryRun()).thenReturn(false);
    when(objectStorage.forSystemDefault()).thenReturn(staging);
    when(staging.listKeysOlderThan(eq("tus-uploads/"), any(Instant.class))).thenReturn(List.of());

    RetentionService.Result result = service.runTusCleanup();

    assertEquals(0, result.eligible());
    assertEquals(0, result.purged());
    assertEquals(0, result.failed());
    verify(staging, never()).delete(any());
  }

  @Test
  void deletesEachStaleKey() {
    when(properties.getMaxRowsPerRun()).thenReturn(5000);
    when(properties.isDryRun()).thenReturn(false);
    when(objectStorage.forSystemDefault()).thenReturn(staging);
    when(staging.listKeysOlderThan(eq("tus-uploads/"), any(Instant.class)))
        .thenReturn(List.of("tus-uploads/abc", "tus-uploads/abc.info", "tus-uploads/def"));

    RetentionService.Result result = service.runTusCleanup();

    assertEquals(3, result.eligible());
    assertEquals(3, result.purged());
    assertEquals(0, result.failed());
    verify(staging, times(1)).delete("tus-uploads/abc");
    verify(staging, times(1)).delete("tus-uploads/abc.info");
    verify(staging, times(1)).delete("tus-uploads/def");
  }

  @Test
  void dryRunSkipsDelete() {
    when(properties.getMaxRowsPerRun()).thenReturn(5000);
    when(properties.isDryRun()).thenReturn(true);
    when(objectStorage.forSystemDefault()).thenReturn(staging);
    when(staging.listKeysOlderThan(eq("tus-uploads/"), any(Instant.class)))
        .thenReturn(List.of("tus-uploads/abc", "tus-uploads/def"));

    RetentionService.Result result = service.runTusCleanup();

    assertEquals(2, result.eligible());
    assertEquals(0, result.purged());
    assertTrue(result.dryRun());
    verify(staging, never()).delete(any());
  }

  @Test
  void respectsMaxRowsCap() {
    when(properties.getMaxRowsPerRun()).thenReturn(2);
    when(properties.isDryRun()).thenReturn(false);
    List<String> tenKeys = IntStream.range(0, 10).mapToObj(i -> "tus-uploads/key" + i).toList();
    when(objectStorage.forSystemDefault()).thenReturn(staging);
    when(staging.listKeysOlderThan(eq("tus-uploads/"), any(Instant.class))).thenReturn(tenKeys);

    RetentionService.Result result = service.runTusCleanup();

    // Eligibility reflects the truncated set, not the full list — the truncation is the work
    // unit per run; remaining keys flow through on the next nightly firing.
    assertEquals(2, result.eligible());
    assertEquals(2, result.purged());
    verify(staging, times(2)).delete(any());
  }

  @Test
  void deleteFailureCountsAsFailed() {
    when(properties.getMaxRowsPerRun()).thenReturn(5000);
    when(properties.isDryRun()).thenReturn(false);
    when(objectStorage.forSystemDefault()).thenReturn(staging);
    when(staging.listKeysOlderThan(eq("tus-uploads/"), any(Instant.class)))
        .thenReturn(List.of("tus-uploads/ok", "tus-uploads/dead"));
    // Single answer stub: throws only for the "dead" key. Mixing a literal-arg doThrow with
    // an unstubbed-arg call confuses Mockito's strict-stubbing tracking.
    doAnswer(
            inv -> {
              if ("tus-uploads/dead".equals(inv.getArgument(0))) {
                throw new RuntimeException("S3 down");
              }
              return null;
            })
        .when(staging)
        .delete(anyString());

    RetentionService.Result result = service.runTusCleanup();

    assertEquals(2, result.eligible());
    assertEquals(1, result.purged());
    assertEquals(1, result.failed());
  }

  @Test
  void zeroDaysRefusesToRun() {
    when(properties.getTusUploadDays()).thenReturn(0);
    when(properties.isDryRun()).thenReturn(false);

    RetentionService.Result result = service.runTusCleanup();

    assertEquals(0, result.eligible());
    verifyNoInteractions(objectStorage);
  }
}
