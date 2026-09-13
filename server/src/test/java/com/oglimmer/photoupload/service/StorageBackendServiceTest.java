/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.entity.StorageBackend;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.model.StorageBackendResponse;
import com.oglimmer.photoupload.repository.StorageBackendRepository;
import com.oglimmer.photoupload.security.SecretCipher;
import com.oglimmer.photoupload.security.UserContext;
import com.oglimmer.photoupload.storage.StorageClientFactory;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * The storage list's album count. The system default is shared by every user, so the number shown
 * against it has to be the caller's own albums — a user with one album used to see the whole
 * instance's total.
 */
@ExtendWith(MockitoExtension.class)
class StorageBackendServiceTest {

  private static final Long SYSTEM_BACKEND_ID = 1L;
  private static final Long USER_BACKEND_ID = 7L;

  @Mock StorageBackendRepository repository;
  @Mock UserContext userContext;
  @Mock SecretCipher secretCipher;
  @Mock StorageQuotaService storageQuotaService;
  @Mock StorageClientFactory clientFactory;
  @Mock ObjectStorageService objectStorage;

  private StorageBackendService service;
  private User user;

  @BeforeEach
  void setUp() {
    user = new User();
    user.setId(42L);
    user.setEmail("owner@example.com");
    when(userContext.getCurrentUser()).thenReturn(user);

    service =
        new StorageBackendService(
            repository,
            userContext,
            secretCipher,
            storageQuotaService,
            clientFactory,
            objectStorage);
  }

  private static StorageBackend backend(Long id, boolean systemDefault) {
    StorageBackend backend = new StorageBackend();
    backend.setId(id);
    backend.setSystemDefault(systemDefault);
    backend.setName(systemDefault ? "This site" : "Home server");
    return backend;
  }

  @Test
  void theSiteStorageCountsOnlyTheCallersAlbums() {
    when(repository.findSelectableForUser(42L))
        .thenReturn(List.of(backend(SYSTEM_BACKEND_ID, true)));
    when(repository.countAlbumsOfUserUsing(SYSTEM_BACKEND_ID, 42L)).thenReturn(1L);

    List<StorageBackendResponse> list = service.listSelectable();

    assertEquals(1L, list.get(0).getAlbumCount());
    // The unscoped count is the instance total on the system default; it must not reach a user.
    verify(repository, never()).countAlbumsUsing(anyLong());
  }

  @Test
  void aUsersOwnStorageIsCountedTheSameWay() {
    when(repository.findSelectableForUser(42L))
        .thenReturn(List.of(backend(SYSTEM_BACKEND_ID, true), backend(USER_BACKEND_ID, false)));
    when(repository.countAlbumsOfUserUsing(SYSTEM_BACKEND_ID, 42L)).thenReturn(1L);
    when(repository.countAlbumsOfUserUsing(USER_BACKEND_ID, 42L)).thenReturn(3L);

    List<StorageBackendResponse> list = service.listSelectable();

    assertEquals(1L, list.get(0).getAlbumCount());
    assertEquals(3L, list.get(1).getAlbumCount());
  }
}
