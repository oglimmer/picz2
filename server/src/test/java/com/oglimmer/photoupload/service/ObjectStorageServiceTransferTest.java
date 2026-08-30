/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.entity.StorageBackend;
import com.oglimmer.photoupload.exception.StorageException;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.StorageBackendRepository;
import com.oglimmer.photoupload.storage.BackendStorage;
import com.oglimmer.photoupload.storage.StorageClientFactory;
import java.io.ByteArrayInputStream;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.http.AbortableInputStream;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;

/**
 * Per-album storage turns one bucket into many. These pin the two decisions that follow from that:
 * a move within one backend must stay a server-side COPY (no JVM bytes), and a move across two must
 * not silently become one (S3 cannot copy between endpoints).
 */
@ExtendWith(MockitoExtension.class)
class ObjectStorageServiceTransferTest {

  @Mock StorageClientFactory factory;
  @Mock StorageBackendRepository backendRepository;
  @Mock AlbumRepository albumRepository;

  @InjectMocks ObjectStorageService service;

  @Mock BackendStorage source;
  @Mock BackendStorage destination;

  @Test
  void sameBackendUsesServerSideCopy() {
    when(source.getBackendId()).thenReturn(1L);
    when(destination.getBackendId()).thenReturn(1L);

    service.transfer(source, "tus-uploads/abc", destination, "originals/x.jpg", "image/jpeg");

    verify(source).copy("tus-uploads/abc", "originals/x.jpg", "image/jpeg");
    verify(source, never()).openStream(anyString());
    verify(destination, never()).putStream(anyString(), any(), anyLong(), anyString());
  }

  @Test
  void differentBackendsStreamTheBytesThrough() {
    when(source.getBackendId()).thenReturn(1L);
    when(destination.getBackendId()).thenReturn(7L);
    byte[] payload = "hello".getBytes();
    when(source.openStream("tus-uploads/abc")).thenReturn(responseStream(payload));

    service.transfer(source, "tus-uploads/abc", destination, "originals/x.jpg", "image/jpeg");

    // No COPY: the destination is a different endpoint and S3 cannot reach across.
    verify(source, never()).copy(anyString(), anyString(), anyString());
    verify(destination)
        .putStream(eq("originals/x.jpg"), any(), eq((long) payload.length), eq("image/jpeg"));
  }

  @Test
  void anAlbumWithNoBackendRowIsAnErrorRatherThanADefault() {
    when(albumRepository.findStorageBackendByAlbumId(42L)).thenReturn(Optional.empty());

    // Falling back to the instance's storage here would write a user's photo to the operator's
    // bucket, where its owner cannot reach it and the operator pays for it.
    assertThrows(StorageException.class, () -> service.forAlbumId(42L));
  }

  @Test
  void theBackendForAnAlbumIsLookedUpOnceAndThenReused() {
    StorageBackend backend = new StorageBackend();
    backend.setId(3L);
    when(albumRepository.findStorageBackendByAlbumId(9L)).thenReturn(Optional.of(backend));

    assertEquals(backend, service.backendForAlbum(9L));
    assertEquals(backend, service.backendForAlbum(9L));

    // A gallery scroll must not add one SELECT per thumbnail.
    verify(albumRepository).findStorageBackendByAlbumId(9L);
  }

  private static ResponseInputStream<GetObjectResponse> responseStream(byte[] payload) {
    return new ResponseInputStream<>(
        GetObjectResponse.builder()
            .contentLength((long) payload.length)
            .contentType("image/jpeg")
            .build(),
        AbortableInputStream.create(new ByteArrayInputStream(payload)));
  }
}
