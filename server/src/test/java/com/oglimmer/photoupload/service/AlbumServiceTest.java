/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.DuplicateResourceException;
import com.oglimmer.photoupload.model.AlbumInfo;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class AlbumServiceTest {

  @Mock AlbumRepository albumRepository;
  @Mock FileMetadataRepository fileMetadataRepository;
  @Mock FileStorageService fileStorageService;
  @Mock UserContext userContext;

  @InjectMocks AlbumService service;

  private User testUser;

  @BeforeEach
  void setUp() {
    testUser = new User();
    testUser.setId(1L);
    testUser.setEmail("test@example.com");
    when(userContext.getCurrentUser()).thenReturn(testUser);
  }

  @Test
  void createAlbumGeneratesTokenAndOrder() {
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
  }

  @Test
  void createAlbumDuplicateThrows() {
    when(albumRepository.findByUserAndName(testUser, "Dup")).thenReturn(Optional.of(new Album()));
    assertThrows(DuplicateResourceException.class, () -> service.createAlbum("Dup", null));
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
}
