/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.GpsSource;
import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.entity.StorageBackend;
import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.DuplicateResourceException;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.model.AlbumInfo;
import com.oglimmer.photoupload.repository.AlbumEnabledTagRepository;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.ImageTagRepository;
import com.oglimmer.photoupload.repository.StorageBackendRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class AlbumServiceTest {

  @Mock AlbumRepository albumRepository;
  @Mock FileMetadataRepository fileMetadataRepository;
  @Mock TagRepository tagRepository;
  @Mock ImageTagRepository imageTagRepository;
  @Mock AlbumEnabledTagRepository albumEnabledTagRepository;
  @Mock StorageBackendRepository storageBackendRepository;
  @Mock FileStorageService fileStorageService;
  @Mock UserContext userContext;
  @Mock SystemTagProvisioner systemTagProvisioner;

  @InjectMocks AlbumService service;

  private User testUser;

  @BeforeEach
  void setUp() {
    testUser = new User();
    testUser.setId(1L);
    testUser.setEmail("test@example.com");
    // lenient: the share-token tests exercise the anonymous path, which never asks who is logged
    // in, and strict stubbing would fail them for not using this.
    lenient().when(userContext.getCurrentUser()).thenReturn(testUser);
  }

  @Test
  void createAlbumGeneratesTokenAndOrder() {
    // No backend id in the request means the instance's own storage — the row V44 seeds.
    when(storageBackendRepository.findBySystemDefaultTrue())
        .thenReturn(Optional.of(systemBackend()));
    when(albumRepository.findByUserAndName(testUser, "Summer")).thenReturn(Optional.empty());
    when(albumRepository.findMaxDisplayOrderByUser(testUser)).thenReturn(3);
    when(fileMetadataRepository.findByAlbumIdAndUserIdOrderByDisplayOrderAsc(anyLong(), eq(1L)))
        .thenReturn(List.of());
    when(albumRepository.save(any(Album.class)))
        .thenAnswer(
            inv -> {
              Album a = inv.getArgument(0);
              a.setId(10L);
              return a;
            });

    AlbumInfo info = service.createAlbum("Summer", "desc");
    assertEquals(10L, info.getId());
    assertEquals("Summer", info.getName());
    assertNotNull(info.getShareToken());
    assertTrue(info.getShareToken().length() >= 48); // token length depends on generator
    assertEquals(4, info.getDisplayOrder());
    // The token exists from the start, but the album is not public until the owner says so.
    assertEquals(Boolean.FALSE, info.getPublished());
    assertNull(info.getPublishedAt());
  }

  @Test
  void publishingStampsTheDateOnceAndOpensTheShareLink() {
    Album album = new Album();
    album.setId(10L);
    album.setUser(testUser);
    album.setName("Summer");
    when(albumRepository.findByUserAndId(testUser, 10L)).thenReturn(Optional.of(album));
    when(fileMetadataRepository.findByAlbumIdAndUserIdOrderByDisplayOrderAsc(10L, 1L))
        .thenReturn(List.of());

    AlbumInfo published = service.setPublished(10L, true);
    assertEquals(Boolean.TRUE, published.getPublished());
    Instant firstPublishedAt = published.getPublishedAt();
    assertNotNull(firstPublishedAt);

    // Unpublishing closes the link but keeps the date: it records the first publication, and the
    // "new albums" notifier keys off it. Re-announcing on every republish would spam subscribers.
    AlbumInfo hidden = service.setPublished(10L, false);
    assertEquals(Boolean.FALSE, hidden.getPublished());
    assertEquals(firstPublishedAt, hidden.getPublishedAt());

    AlbumInfo again = service.setPublished(10L, true);
    assertEquals(firstPublishedAt, again.getPublishedAt());
  }

  @Test
  void unpublishedAlbumIsNotFoundByShareToken() {
    // The repository query itself filters on published, so an unpublished album and a made-up
    // token are the same empty Optional — and must be the same 404 to the visitor.
    when(albumRepository.findByShareTokenAndPublishedTrue("tok")).thenReturn(Optional.empty());

    assertThrows(ResourceNotFoundException.class, () -> service.getAlbumByShareToken("tok"));
  }

  @Test
  void duplicatingAPublicAlbumProducesAPrivateCopy() {
    Album source = new Album();
    source.setId(10L);
    source.setUser(testUser);
    source.setName("Summer");
    source.setPublished(true);
    source.setPublishedAt(Instant.now());

    when(albumRepository.findByUserAndId(testUser, 10L)).thenReturn(Optional.of(source));
    when(albumRepository.findByUserAndName(eq(testUser), anyString())).thenReturn(Optional.empty());
    when(albumRepository.findMaxDisplayOrderByUser(testUser)).thenReturn(0);
    when(albumEnabledTagRepository.findByAlbumId(10L)).thenReturn(List.of());
    when(fileMetadataRepository.findByAlbumIdAndUserIdOrderByDisplayOrderAsc(anyLong(), eq(1L)))
        .thenReturn(List.of());
    when(systemTagProvisioner.ensureTag(eq(testUser), anyString())).thenReturn(99L);
    when(tagRepository.getReferenceById(99L)).thenReturn(new Tag());

    ArgumentCaptor<Album> saved = ArgumentCaptor.forClass(Album.class);
    when(albumRepository.save(saved.capture()))
        .thenAnswer(
            inv -> {
              Album a = inv.getArgument(0);
              a.setId(11L);
              return a;
            });

    AlbumInfo copy = service.duplicateAlbum(10L);

    assertEquals(Boolean.FALSE, copy.getPublished());
    assertNull(copy.getPublishedAt());
  }

  @Test
  void createAlbumDuplicateThrows() {
    when(albumRepository.findByUserAndName(testUser, "Dup")).thenReturn(Optional.of(new Album()));
    assertThrows(DuplicateResourceException.class, () -> service.createAlbum("Dup", null));
  }

  /**
   * A duplicate shares the original's bytes but re-derives nothing, so every value that was read
   * out of those bytes once has to be carried over: coordinates and capture offset can only be
   * recovered by re-reading the original, and the processing state has to say DONE because no job
   * is ever enqueued for a copy.
   */
  @Test
  void duplicateAlbumCarriesCaptureMetadataAndProcessingState() {
    Album source = new Album();
    source.setId(1L);
    source.setName("Toronto");
    source.setUser(testUser);
    when(albumRepository.findByUserAndId(testUser, 1L)).thenReturn(Optional.of(source));
    when(albumRepository.findByUserAndName(eq(testUser), anyString())).thenReturn(Optional.empty());
    when(albumRepository.save(any(Album.class))).thenAnswer(inv -> inv.getArgument(0));
    when(albumEnabledTagRepository.findByAlbumId(1L)).thenReturn(List.of());
    // no_tag is provisioned in its own transaction now and resolved by id, not re-queried.
    when(systemTagProvisioner.ensureTag(eq(testUser), anyString())).thenReturn(11L);
    when(tagRepository.getReferenceById(11L)).thenReturn(new Tag());

    FileMetadata original = new FileMetadata();
    original.setId(7L);
    original.setOriginalName("cn-tower.jpg");
    original.setGpsLatitude(43.6426);
    original.setGpsLongitude(-79.3871);
    original.setGpsSource(GpsSource.EXIF_GPS);
    original.setCaptureUtcOffsetSeconds(-4 * 3600);
    original.setProcessingStatus(ProcessingStatus.DONE);
    original.setProcessingCompletedAt(Instant.parse("2026-08-17T23:23:11Z"));
    when(fileMetadataRepository.findByAlbumIdAndUserIdOrderByDisplayOrderAsc(1L, 1L))
        .thenReturn(new ArrayList<>(List.of(original)));
    when(fileMetadataRepository.save(any(FileMetadata.class)))
        .thenAnswer(inv -> inv.getArgument(0));

    service.duplicateAlbum(1L);

    ArgumentCaptor<FileMetadata> saved = ArgumentCaptor.forClass(FileMetadata.class);
    verify(fileMetadataRepository).save(saved.capture());
    FileMetadata copy = saved.getValue();
    assertEquals(43.6426, copy.getGpsLatitude());
    assertEquals(-79.3871, copy.getGpsLongitude());
    assertEquals(GpsSource.EXIF_GPS, copy.getGpsSource());
    assertEquals(-4 * 3600, copy.getCaptureUtcOffsetSeconds());
    assertEquals(ProcessingStatus.DONE, copy.getProcessingStatus());
    assertEquals(original.getProcessingCompletedAt(), copy.getProcessingCompletedAt());
  }

  @Test
  void reorderFilesByFilenameSortsAndSaves() {
    Album album = new Album();
    album.setId(1L);
    album.setName("A");
    album.setUser(testUser);
    when(albumRepository.findByUserAndId(testUser, 1L)).thenReturn(Optional.of(album));

    FileMetadata f1 = new FileMetadata();
    f1.setId(1L);
    f1.setOriginalName("img_20.jpg");
    FileMetadata f2 = new FileMetadata();
    f2.setId(2L);
    f2.setOriginalName("img_3.jpg");
    FileMetadata f3 = new FileMetadata();
    f3.setId(3L);
    f3.setOriginalName("zzz.jpg");
    List<FileMetadata> list = new ArrayList<>(List.of(f1, f2, f3));
    when(fileMetadataRepository.findByAlbumIdAndUserIdOrderByDisplayOrderAsc(1L, 1L))
        .thenReturn(list);

    int updated = service.reorderFilesByFilename(1L);
    assertEquals(3, updated);

    // After sorting: f2 (3), f1 (20), f3 (no number)
    assertEquals(0, f2.getDisplayOrder());
    assertEquals(1, f1.getDisplayOrder());
    assertEquals(2, f3.getDisplayOrder());

    verify(fileMetadataRepository).saveAll(list);
  }

  private static StorageBackend systemBackend() {
    StorageBackend backend = new StorageBackend();
    backend.setId(1L);
    backend.setName("Default storage");
    backend.setSystemDefault(true);
    return backend;
  }
}
