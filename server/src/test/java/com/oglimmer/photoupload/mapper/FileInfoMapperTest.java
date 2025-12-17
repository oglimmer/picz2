/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.mapper;

import static org.junit.jupiter.api.Assertions.*;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ImageTag;
import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.model.FileInfo;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mapstruct.factory.Mappers;

class FileInfoMapperTest {

  private FileInfoMapper mapper;

  @BeforeEach
  void setUp() {
    mapper = Mappers.getMapper(FileInfoMapper.class);
  }

  @Test
  void mapsBasicFieldsCorrectly() {
    // Given
    FileMetadata metadata = new FileMetadata();
    metadata.setId(123L);
    metadata.setOriginalName("photo.jpg");
    metadata.setStoredFilename("abc123.jpg");
    metadata.setFileSize(1024L);
    metadata.setMimeType("image/jpeg");
    metadata.setFilePath("/uploads/abc123.jpg");
    metadata.setPublicToken("token123");
    metadata.setRotation(90);
    metadata.setDisplayOrder(5);

    Instant uploadTime = Instant.parse("2024-01-15T10:30:00Z");
    Instant exifTime = Instant.parse("2024-01-10T14:20:00Z");
    metadata.setUploadedAt(uploadTime);
    metadata.setExifDateTimeOriginal(exifTime);

    // When
    FileInfo result = mapper.fileMetadataToFileInfo(metadata);

    // Then
    assertNotNull(result);
    assertEquals(123L, result.getId());
    assertEquals("photo.jpg", result.getOriginalName());
    assertEquals("abc123.jpg", result.getFilename()); // storedFilename -> filename
    assertEquals(1024L, result.getSize()); // fileSize -> size
    assertEquals("image/jpeg", result.getMimetype()); // mimeType -> mimetype
    assertEquals("/uploads/abc123.jpg", result.getPath()); // filePath -> path
    assertEquals("token123", result.getPublicToken());
    assertEquals(90, result.getRotation());
    assertEquals(5, result.getDisplayOrder());
    assertEquals(uploadTime, result.getUploadedAt());
    assertEquals(exifTime, result.getExifDateTimeOriginal());
  }

  @Test
  void mapsTagsFromImageTags() {
    // Given
    FileMetadata metadata = new FileMetadata();
    metadata.setId(1L);
    metadata.setOriginalName("test.jpg");
    metadata.setStoredFilename("test.jpg");
    metadata.setFileSize(100L);
    metadata.setFilePath("/test.jpg");

    List<ImageTag> imageTags = new ArrayList<>();

    Tag tag1 = new Tag();
    tag1.setName("nature");
    ImageTag imageTag1 = new ImageTag();
    imageTag1.setTag(tag1);
    imageTags.add(imageTag1);

    Tag tag2 = new Tag();
    tag2.setName("landscape");
    ImageTag imageTag2 = new ImageTag();
    imageTag2.setTag(tag2);
    imageTags.add(imageTag2);

    metadata.setImageTags(imageTags);

    // When
    FileInfo result = mapper.fileMetadataToFileInfo(metadata);

    // Then
    assertNotNull(result.getTags());
    assertEquals(2, result.getTags().size());
    assertTrue(result.getTags().contains("nature"));
    assertTrue(result.getTags().contains("landscape"));
  }

  @Test
  void doesNotMapTagsWhenImageTagsIsNull() {
    // Given
    FileMetadata metadata = new FileMetadata();
    metadata.setId(1L);
    metadata.setOriginalName("test.jpg");
    metadata.setStoredFilename("test.jpg");
    metadata.setFileSize(100L);
    metadata.setFilePath("/test.jpg");
    metadata.setImageTags(null);

    // When
    FileInfo result = mapper.fileMetadataToFileInfo(metadata);

    // Then
    assertNotNull(result.getTags());
    assertTrue(result.getTags().isEmpty());
  }

  @Test
  void doesNotMapTagsWhenImageTagsIsEmpty() {
    // Given
    FileMetadata metadata = new FileMetadata();
    metadata.setId(1L);
    metadata.setOriginalName("test.jpg");
    metadata.setStoredFilename("test.jpg");
    metadata.setFileSize(100L);
    metadata.setFilePath("/test.jpg");
    metadata.setImageTags(new ArrayList<>());

    // When
    FileInfo result = mapper.fileMetadataToFileInfo(metadata);

    // Then
    assertNotNull(result.getTags());
    assertTrue(result.getTags().isEmpty());
  }

  @Test
  void mapsAlbumInfo() {
    // Given
    Album album = new Album();
    album.setId(42L);
    album.setName("Vacation 2024");

    FileMetadata metadata = new FileMetadata();
    metadata.setId(1L);
    metadata.setOriginalName("test.jpg");
    metadata.setStoredFilename("test.jpg");
    metadata.setFileSize(100L);
    metadata.setFilePath("/test.jpg");
    metadata.setAlbum(album);

    // When
    FileInfo result = mapper.fileMetadataToFileInfo(metadata);

    // Then
    assertEquals(42L, result.getAlbumId());
    assertEquals("Vacation 2024", result.getAlbumName());
  }

  @Test
  void doesNotMapAlbumInfoWhenAlbumIsNull() {
    // Given
    FileMetadata metadata = new FileMetadata();
    metadata.setId(1L);
    metadata.setOriginalName("test.jpg");
    metadata.setStoredFilename("test.jpg");
    metadata.setFileSize(100L);
    metadata.setFilePath("/test.jpg");
    metadata.setAlbum(null);

    // When
    FileInfo result = mapper.fileMetadataToFileInfo(metadata);

    // Then
    assertNull(result.getAlbumId());
    assertNull(result.getAlbumName());
  }

  @Test
  void mapsListOfFileMetadatas() {
    // Given
    FileMetadata metadata1 = new FileMetadata();
    metadata1.setId(1L);
    metadata1.setOriginalName("photo1.jpg");
    metadata1.setStoredFilename("stored1.jpg");
    metadata1.setFileSize(100L);
    metadata1.setMimeType("image/jpeg");
    metadata1.setFilePath("/path1");

    FileMetadata metadata2 = new FileMetadata();
    metadata2.setId(2L);
    metadata2.setOriginalName("photo2.jpg");
    metadata2.setStoredFilename("stored2.jpg");
    metadata2.setFileSize(200L);
    metadata2.setMimeType("image/png");
    metadata2.setFilePath("/path2");

    List<FileMetadata> metadataList = List.of(metadata1, metadata2);

    // When
    List<FileInfo> result = mapper.fileMetadatasToFileInfos(metadataList);

    // Then
    assertNotNull(result);
    assertEquals(2, result.size());
    assertEquals(1L, result.get(0).getId());
    assertEquals("photo1.jpg", result.get(0).getOriginalName());
    assertEquals(2L, result.get(1).getId());
    assertEquals("photo2.jpg", result.get(1).getOriginalName());
  }

  @Test
  void handlesNullSafely() {
    // When/Then
    assertNull(mapper.fileMetadataToFileInfo(null));
    assertNull(mapper.fileMetadatasToFileInfos(null));
  }
}
