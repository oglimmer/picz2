/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.mapper;

import static org.junit.jupiter.api.Assertions.*;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.SlideshowRecording;
import com.oglimmer.photoupload.entity.SlideshowRecordingImage;
import com.oglimmer.photoupload.model.RecordingInfo;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mapstruct.factory.Mappers;

class RecordingInfoMapperTest {

  private RecordingInfoMapper mapper;

  @BeforeEach
  void setUp() {
    mapper = Mappers.getMapper(RecordingInfoMapper.class);
  }

  @Test
  void mapsBasicFieldsCorrectly() {
    // Given
    SlideshowRecording recording = new SlideshowRecording();
    recording.setId(100L);
    recording.setFilterTag("nature");
    recording.setLanguage("en-US");
    recording.setAudioFilename("audio.mp3");
    recording.setPublicToken("public123");
    recording.setDurationMs(5000L);

    Instant createdTime = Instant.parse("2024-02-20T15:30:00Z");
    recording.setCreatedAt(createdTime);
    recording.setImages(new ArrayList<>());

    // When
    RecordingInfo result = mapper.recordingToRecordingInfo(recording);

    // Then
    assertNotNull(result);
    assertEquals(100L, result.getId());
    assertEquals("nature", result.getFilterTag());
    assertEquals("en-US", result.getLanguage());
    assertEquals("audio.mp3", result.getAudioFilename());
    assertEquals("public123", result.getPublicToken());
    assertEquals(5000L, result.getDurationMs());
    assertEquals(createdTime, result.getCreatedAt());
  }

  @Test
  void mapsRecordingImagesCorrectly() {
    // Given
    SlideshowRecording recording = new SlideshowRecording();
    recording.setId(1L);
    recording.setFilterTag("test");
    recording.setLanguage("en");
    recording.setAudioFilename("audio.mp3");
    recording.setDurationMs(1000L);

    List<SlideshowRecordingImage> images = new ArrayList<>();

    FileMetadata file1 = new FileMetadata();
    file1.setId(10L);
    SlideshowRecordingImage img1 = new SlideshowRecordingImage();
    img1.setFile(file1);
    img1.setStartTimeMs(0L);
    img1.setDurationMs(500L);
    img1.setSequenceOrder(1);
    images.add(img1);

    FileMetadata file2 = new FileMetadata();
    file2.setId(20L);
    SlideshowRecordingImage img2 = new SlideshowRecordingImage();
    img2.setFile(file2);
    img2.setStartTimeMs(500L);
    img2.setDurationMs(500L);
    img2.setSequenceOrder(2);
    images.add(img2);

    recording.setImages(images);

    // When
    RecordingInfo result = mapper.recordingToRecordingInfo(recording);

    // Then
    assertNotNull(result.getImages());
    assertEquals(2, result.getImages().size());

    RecordingInfo.RecordingImageInfo imageInfo1 = result.getImages().get(0);
    assertEquals(10L, imageInfo1.getFileId());
    assertEquals(0L, imageInfo1.getStartTimeMs());
    assertEquals(500L, imageInfo1.getDurationMs());
    assertEquals(1, imageInfo1.getSequenceOrder());

    RecordingInfo.RecordingImageInfo imageInfo2 = result.getImages().get(1);
    assertEquals(20L, imageInfo2.getFileId());
    assertEquals(500L, imageInfo2.getStartTimeMs());
    assertEquals(500L, imageInfo2.getDurationMs());
    assertEquals(2, imageInfo2.getSequenceOrder());
  }

  @Test
  void handlesEmptyImagesList() {
    // Given
    SlideshowRecording recording = new SlideshowRecording();
    recording.setId(1L);
    recording.setFilterTag("test");
    recording.setLanguage("en");
    recording.setAudioFilename("audio.mp3");
    recording.setDurationMs(1000L);
    recording.setImages(new ArrayList<>());

    // When
    RecordingInfo result = mapper.recordingToRecordingInfo(recording);

    // Then
    assertNotNull(result.getImages());
    assertTrue(result.getImages().isEmpty());
  }

  @Test
  void mapsAlbumId() {
    // Given
    Album album = new Album();
    album.setId(99L);
    album.setName("Test Album");

    SlideshowRecording recording = new SlideshowRecording();
    recording.setId(1L);
    recording.setFilterTag("test");
    recording.setLanguage("en");
    recording.setAudioFilename("audio.mp3");
    recording.setDurationMs(1000L);
    recording.setAlbum(album);
    recording.setImages(new ArrayList<>());

    // When
    RecordingInfo result = mapper.recordingToRecordingInfo(recording);

    // Then
    assertEquals(99L, result.getAlbumId());
  }

  @Test
  void doesNotMapAlbumIdWhenAlbumIsNull() {
    // Given
    SlideshowRecording recording = new SlideshowRecording();
    recording.setId(1L);
    recording.setFilterTag("test");
    recording.setLanguage("en");
    recording.setAudioFilename("audio.mp3");
    recording.setDurationMs(1000L);
    recording.setAlbum(null);
    recording.setImages(new ArrayList<>());

    // When
    RecordingInfo result = mapper.recordingToRecordingInfo(recording);

    // Then
    assertNull(result.getAlbumId());
  }

  @Test
  void mapsListOfRecordings() {
    // Given
    SlideshowRecording recording1 = new SlideshowRecording();
    recording1.setId(1L);
    recording1.setFilterTag("tag1");
    recording1.setLanguage("en");
    recording1.setAudioFilename("audio1.mp3");
    recording1.setDurationMs(1000L);
    recording1.setImages(new ArrayList<>());

    SlideshowRecording recording2 = new SlideshowRecording();
    recording2.setId(2L);
    recording2.setFilterTag("tag2");
    recording2.setLanguage("de");
    recording2.setAudioFilename("audio2.mp3");
    recording2.setDurationMs(2000L);
    recording2.setImages(new ArrayList<>());

    List<SlideshowRecording> recordings = List.of(recording1, recording2);

    // When
    List<RecordingInfo> result = mapper.recordingsToRecordingInfos(recordings);

    // Then
    assertNotNull(result);
    assertEquals(2, result.size());
    assertEquals(1L, result.get(0).getId());
    assertEquals("tag1", result.get(0).getFilterTag());
    assertEquals(2L, result.get(1).getId());
    assertEquals("tag2", result.get(1).getFilterTag());
  }

  @Test
  void handlesNullSafely() {
    // When/Then
    assertNull(mapper.recordingToRecordingInfo(null));
    assertNull(mapper.recordingsToRecordingInfos(null));
  }
}
