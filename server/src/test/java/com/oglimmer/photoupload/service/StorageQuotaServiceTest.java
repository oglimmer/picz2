/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.entity.StorageBackend;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.StorageQuotaExceededException;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.repository.StorageBackendRepository;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * The per-user cap on the instance's own storage.
 *
 * <p>Two rules carry the feature: only the system backend is metered (a user's own bucket is theirs
 * to fill), and every kind of object we keep for them counts — originals, derivatives and narration
 * — because retention deletes originals after a week and a quota that counted only those would
 * measure almost nothing on an old account.
 */
@ExtendWith(MockitoExtension.class)
class StorageQuotaServiceTest {

  private static final Long SYSTEM_BACKEND_ID = 1L;
  private static final Long USER_BACKEND_ID = 7L;
  private static final long MB = 1024L * 1024L;

  @Mock FileMetadataRepository metadataRepository;
  @Mock SlideshowRecordingRepository recordingRepository;
  @Mock StorageBackendRepository backendRepository;
  @Mock AlbumRepository albumRepository;
  @Mock ObjectStorageService objectStorage;

  private StorageQuotaService service;

  private User user;

  @BeforeEach
  void setUp() {
    user = new User();
    user.setId(42L);
    user.setEmail("owner@example.com");
    user.setStorageQuotaBytes(100 * MB);

    service =
        new StorageQuotaService(
            metadataRepository,
            recordingRepository,
            backendRepository,
            albumRepository,
            Optional.of(objectStorage));

    lenient()
        .when(backendRepository.findBySystemDefaultTrue())
        .thenReturn(Optional.of(backend(SYSTEM_BACKEND_ID, true)));
  }

  private static StorageBackend backend(Long id, boolean systemDefault) {
    StorageBackend backend = new StorageBackend();
    backend.setId(id);
    backend.setSystemDefault(systemDefault);
    return backend;
  }

  private void usage(long originals, long derivatives, long audio) {
    lenient()
        .when(metadataRepository.sumOriginalBytes(42L, SYSTEM_BACKEND_ID))
        .thenReturn(originals);
    lenient()
        .when(metadataRepository.sumDerivativeBytes(42L, SYSTEM_BACKEND_ID))
        .thenReturn(derivatives);
    lenient().when(recordingRepository.sumAudioBytes(42L, SYSTEM_BACKEND_ID)).thenReturn(audio);
  }

  private void albumOn(Long albumId, Long backendId, boolean systemDefault) {
    lenient()
        .when(albumRepository.findStorageBackendByAlbumId(albumId))
        .thenReturn(Optional.of(backend(backendId, systemDefault)));
  }

  @Test
  void usageSumsOriginalsDerivativesAndNarration() {
    usage(10 * MB, 3 * MB, 1 * MB);

    StorageQuotaService.Usage result = service.usageFor(user);

    // Derivatives are the reason this is not just SUM(file_size): retention deletes the original
    // after a week, and its thumbnails stay on the disk for good.
    assertEquals(14 * MB, result.usedBytes());
    assertEquals(100 * MB, result.quotaBytes());
    assertEquals(86 * MB, result.remainingBytes());
    assertTrue(!result.isFull());
  }

  @Test
  void anUploadThatFitsIsAllowed() {
    albumOn(5L, SYSTEM_BACKEND_ID, true);
    usage(50 * MB, 0, 0);

    assertDoesNotThrow(() -> service.requireRoomFor(user, 5L, 10 * MB));
  }

  @Test
  void anUploadThatWouldOverflowIsRefused() {
    albumOn(5L, SYSTEM_BACKEND_ID, true);
    usage(95 * MB, 0, 0);

    StorageQuotaExceededException e =
        assertThrows(
            StorageQuotaExceededException.class, () -> service.requireRoomFor(user, 5L, 10 * MB));

    assertEquals(95 * MB, e.getUsedBytes());
    assertEquals(100 * MB, e.getQuotaBytes());
    assertEquals(10 * MB, e.getRequestedBytes());
    // The message is shown to a person, so it must be in units they read.
    assertTrue(e.getMessage().contains("95 MB"), e.getMessage());
    assertTrue(e.getMessage().contains("100 MB"), e.getMessage());
  }

  @Test
  void exactlyFillingTheQuotaIsAllowed() {
    albumOn(5L, SYSTEM_BACKEND_ID, true);
    usage(90 * MB, 0, 0);

    assertDoesNotThrow(() -> service.requireRoomFor(user, 5L, 10 * MB));
  }

  @Test
  void anAlbumOnTheUsersOwnStorageIsNotMetered() {
    albumOn(9L, USER_BACKEND_ID, false);

    // Their bucket, their bill. A cap here would be us rationing someone else's disk — and note
    // no usage stubs are needed, because the check must not even ask.
    assertDoesNotThrow(() -> service.requireRoomFor(user, 9L, 500 * MB));
  }

  /**
   * An album we cannot resolve counts as metered. Guessing "unmetered" would turn a bad album id
   * into a way past the limit.
   */
  @Test
  void anUnknownAlbumIsTreatedAsMetered() {
    when(albumRepository.findStorageBackendByAlbumId(404L)).thenReturn(Optional.empty());
    usage(99 * MB, 0, 0);

    assertThrows(
        StorageQuotaExceededException.class, () -> service.requireRoomFor(user, 404L, 10 * MB));
  }

  /** No album id means the user's configured target album, which is the one about to receive it. */
  @Test
  void aNullAlbumIdFallsBackToTheUsersDefaultAlbum() {
    user.setDefaultAlbumId(9L);
    albumOn(9L, USER_BACKEND_ID, false);

    assertDoesNotThrow(() -> service.requireRoomFor(user, null, 500 * MB));
  }

  /** Sync paused, no target album: metered, so a full account cannot sneak past on a null. */
  @Test
  void noAlbumAnywhereIsTreatedAsMetered() {
    usage(99 * MB, 0, 0);

    assertThrows(
        StorageQuotaExceededException.class, () -> service.requireRoomFor(user, null, 10 * MB));
  }

  /** A quota of zero is a usable way to freeze an account: nothing more may be stored. */
  @Test
  void aZeroQuotaRefusesEverything() {
    user.setStorageQuotaBytes(0L);
    albumOn(5L, SYSTEM_BACKEND_ID, true);
    usage(0, 0, 0);

    assertThrows(StorageQuotaExceededException.class, () -> service.requireRoomFor(user, 5L, 1L));
  }
}
