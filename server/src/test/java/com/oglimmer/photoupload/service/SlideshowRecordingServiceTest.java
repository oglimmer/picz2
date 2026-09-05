/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.SlideshowRecording;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.mapper.RecordingInfoMapper;
import com.oglimmer.photoupload.model.RecordingInfo;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class SlideshowRecordingServiceTest {

  @Mock SlideshowRecordingRepository recRepo;
  @Mock AlbumRepository albumRepo;
  @Mock FileMetadataRepository fileRepo;
  @Mock FileStorageProperties props;
  @Mock AudioReencodingService audioReencodingService;
  @Mock UserContext userContext;
  @Mock RecordingInfoMapper recordingInfoMapper;
  @Mock ObjectStorageService objectStorage;

  @InjectMocks SlideshowRecordingService service;

  private User testUser;

  @BeforeEach
  void setUp() {
    testUser = new User();
    testUser.setId(1L);
    testUser.setEmail("test@example.com");
    lenient().when(userContext.getCurrentUser()).thenReturn(testUser);
  }

  @Test
  void getRecordingsByAlbumAndTagFilters() {
    Album album = new Album();
    album.setId(1L);
    album.setUser(testUser);
    when(albumRepo.findByUserAndId(testUser, 1L)).thenReturn(Optional.of(album));

    SlideshowRecording r1 = new SlideshowRecording();
    r1.setAlbum(album);
    r1.setFilterTag("x");
    SlideshowRecording r2 = new SlideshowRecording();
    r2.setAlbum(album);
    r2.setFilterTag("y");
    when(recRepo.findByAlbumIdAndUserIdOrderByCreatedAtDesc(1L, 1L)).thenReturn(List.of(r1, r2));

    // Mock mapper - simulate converting to RecordingInfo
    RecordingInfo info1 = new RecordingInfo();
    info1.setFilterTag("x");
    info1.setAlbumId(1L);
    when(recordingInfoMapper.recordingToRecordingInfo(r1)).thenReturn(info1);

    var list = service.getRecordingsByAlbumAndTag(1L, "x");
    assertEquals(1, list.size());
    assertEquals("x", list.get(0).getFilterTag());
  }

  @Test
  void getRecordingAudioInfoByPublicTokenReturnsTheObjectKey() {
    SlideshowRecording r = new SlideshowRecording();
    r.setId(1L);
    // The album is what says which storage backend holds the audio, so the row needs one.
    Album album = new Album();
    album.setId(1L);
    r.setAlbum(album);
    r.setAudioPath("audio/a.webm");
    r.setAudioFilename("a.webm");
    r.setPublicToken("tok");
    when(recRepo.findByPublicToken("tok")).thenReturn(Optional.of(r));

    var audioInfo = service.getRecordingAudioInfoByPublicToken("tok", null);
    assertNotNull(audioInfo);
    assertEquals("a.webm", audioInfo.getAudioFilename());
    assertEquals("audio/a.webm", audioInfo.getStorageKey());
    assertEquals(1L, audioInfo.getAlbumId());
  }
}
