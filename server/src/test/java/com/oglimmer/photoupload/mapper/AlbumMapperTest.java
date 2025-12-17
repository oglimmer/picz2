/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.mapper;

import static org.junit.jupiter.api.Assertions.*;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.model.AlbumInfo;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mapstruct.factory.Mappers;

class AlbumMapperTest {

  private AlbumMapper mapper;

  @BeforeEach
  void setUp() {
    mapper = Mappers.getMapper(AlbumMapper.class);
  }

  @Test
  void mapsBasicFieldsCorrectly() {
    // Given
    Album album = new Album();
    album.setId(50L);
    album.setName("Summer Vacation");
    album.setDescription("Photos from our trip to the beach");
    album.setDisplayOrder(3);
    album.setShareToken("share-token-abc123");

    Instant createdTime = Instant.parse("2024-06-01T10:00:00Z");
    Instant updatedTime = Instant.parse("2024-06-15T14:30:00Z");
    album.setCreatedAt(createdTime);
    album.setUpdatedAt(updatedTime);

    // When
    AlbumInfo result = mapper.albumToAlbumInfo(album);

    // Then
    assertNotNull(result);
    assertEquals(50L, result.getId());
    assertEquals("Summer Vacation", result.getName());
    assertEquals("Photos from our trip to the beach", result.getDescription());
    assertEquals(3, result.getDisplayOrder());
    assertEquals("share-token-abc123", result.getShareToken());
    assertEquals(createdTime, result.getCreatedAt());
    assertEquals(updatedTime, result.getUpdatedAt());
  }

  @Test
  void computedFieldsAreNotMappedFromEntity() {
    // Given
    Album album = new Album();
    album.setId(1L);
    album.setName("Test Album");

    // When
    AlbumInfo result = mapper.albumToAlbumInfo(album);

    // Then - computed fields should be null (they need to be set by the service layer)
    assertNull(result.getFileCount());
    assertNull(result.getCoverImageFilename());
    assertNull(result.getCoverImageToken());
  }

  @Test
  void handlesNullDescriptionAndShareToken() {
    // Given
    Album album = new Album();
    album.setId(1L);
    album.setName("Minimal Album");
    album.setDescription(null);
    album.setShareToken(null);
    album.setDisplayOrder(0);

    Instant createdTime = Instant.parse("2024-01-01T00:00:00Z");
    album.setCreatedAt(createdTime);
    album.setUpdatedAt(createdTime);

    // When
    AlbumInfo result = mapper.albumToAlbumInfo(album);

    // Then
    assertNotNull(result);
    assertEquals(1L, result.getId());
    assertEquals("Minimal Album", result.getName());
    assertNull(result.getDescription());
    assertNull(result.getShareToken());
  }

  @Test
  void mapsListOfAlbums() {
    // Given
    Album album1 = new Album();
    album1.setId(1L);
    album1.setName("Album One");
    album1.setDisplayOrder(1);
    album1.setCreatedAt(Instant.now());
    album1.setUpdatedAt(Instant.now());

    Album album2 = new Album();
    album2.setId(2L);
    album2.setName("Album Two");
    album2.setDisplayOrder(2);
    album2.setCreatedAt(Instant.now());
    album2.setUpdatedAt(Instant.now());

    List<Album> albums = List.of(album1, album2);

    // When
    List<AlbumInfo> result = mapper.albumsToAlbumInfos(albums);

    // Then
    assertNotNull(result);
    assertEquals(2, result.size());
    assertEquals(1L, result.get(0).getId());
    assertEquals("Album One", result.get(0).getName());
    assertEquals(2L, result.get(1).getId());
    assertEquals("Album Two", result.get(1).getName());
  }

  @Test
  void handlesNullSafely() {
    // When/Then
    assertNull(mapper.albumToAlbumInfo(null));
    assertNull(mapper.albumsToAlbumInfos(null));
  }
}
