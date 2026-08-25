/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.entity.JobStatus;
import com.oglimmer.photoupload.entity.JobType;
import com.oglimmer.photoupload.entity.SlideshowRecording;
import com.oglimmer.photoupload.exception.AudioNotReadyException;
import com.oglimmer.photoupload.mapper.RecordingInfoMapper;
import com.oglimmer.photoupload.model.RecordingAudioInfo;
import com.oglimmer.photoupload.model.RecordingAudioStatus;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.ProcessingJobRepository;
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

/**
 * The api pod must never transcode inside a request. These pin the contract that replaced it: ask
 * {@link RecordingAudioService} whether the AAC sibling is there, and if it is not, queue the work
 * once and tell the client to come back.
 */
@ExtendWith(MockitoExtension.class)
class SlideshowRecordingAudioReadinessTest {

  private static final String TOKEN = "public-token";

  @Mock SlideshowRecordingRepository recRepo;
  @Mock AlbumRepository albumRepo;
  @Mock FileMetadataRepository fileRepo;
  @Mock FileStorageProperties props;
  @Mock AudioReencodingService audioReencodingService;
  @Mock UserContext userContext;
  @Mock RecordingInfoMapper recordingInfoMapper;
  @Mock RecordingAudioService recordingAudioService;
  @Mock JobEnqueueService jobEnqueueService;
  @Mock ProcessingJobRepository jobRepo;

  @InjectMocks SlideshowRecordingService service;

  private SlideshowRecording recording;

  @BeforeEach
  void setUp() {
    recording = new SlideshowRecording();
    recording.setId(7L);
    recording.setAudioFilename("abc.webm");
    recording.setAudioPath("audio/abc.webm");
    when(recRepo.findByPublicToken(TOKEN)).thenReturn(Optional.of(recording));
  }

  @Test
  void readySiblingIsServedWithoutQueueingAnything() {
    when(recordingAudioService.isAacReady(recording)).thenReturn(true);
    when(recordingAudioService.aacLocation(recording))
        .thenReturn(new RecordingAudioInfo("abc.m4a", null, "audio/abc.m4a"));

    RecordingAudioInfo info = service.getRecordingAudioInfoByPublicToken(TOKEN, "m4a");

    assertTrue(info.getStorageKey().endsWith(".m4a"));
    verify(jobEnqueueService, never()).enqueueForRecording(any(), any());
  }

  @Test
  void missingSiblingQueuesTheTranscodeAndRefusesToServe() {
    when(recordingAudioService.isAacReady(recording)).thenReturn(false);
    when(jobRepo.existsByRecordingIdAndJobTypeAndStatusIn(
            eq(7L), eq(JobType.TRANSCODE_AUDIO_AAC), any()))
        .thenReturn(false);

    AudioNotReadyException thrown =
        assertThrows(
            AudioNotReadyException.class,
            () -> service.getRecordingAudioInfoByPublicToken(TOKEN, "m4a"));

    assertFalse(thrown.isFailed());
    verify(jobEnqueueService).enqueueForRecording(7L, JobType.TRANSCODE_AUDIO_AAC);
  }

  @Test
  void aQueuedTranscodeIsNotQueuedAgainByThePollingClient() {
    when(recordingAudioService.isAacReady(recording)).thenReturn(false);
    when(jobRepo.existsByRecordingIdAndJobTypeAndStatusIn(
            7L, JobType.TRANSCODE_AUDIO_AAC, List.of(JobStatus.DEAD_LETTER)))
        .thenReturn(false);
    when(jobRepo.existsByRecordingIdAndJobTypeAndStatusIn(
            7L, JobType.TRANSCODE_AUDIO_AAC, List.of(JobStatus.QUEUED, JobStatus.PROCESSING)))
        .thenReturn(true);

    RecordingAudioStatus first = service.audioStatusByPublicToken(TOKEN);
    RecordingAudioStatus second = service.audioStatusByPublicToken(TOKEN);

    assertFalse(first.isReady());
    assertFalse(second.isReady());
    assertFalse(second.isFailed());
    verify(jobEnqueueService, never()).enqueueForRecording(any(), any());
  }

  @Test
  void aDeadLetteredTranscodeReportsFailedSoTheClientStopsWaiting() {
    when(recordingAudioService.isAacReady(recording)).thenReturn(false);
    when(jobRepo.existsByRecordingIdAndJobTypeAndStatusIn(
            7L, JobType.TRANSCODE_AUDIO_AAC, List.of(JobStatus.DEAD_LETTER)))
        .thenReturn(true);

    RecordingAudioStatus status = service.audioStatusByPublicToken(TOKEN);

    assertFalse(status.isReady());
    assertTrue(status.isFailed());
    verify(jobEnqueueService, never()).enqueueForRecording(any(), any());
  }

  @Test
  void theFirstPollQueuesExactlyOneJob() {
    when(recordingAudioService.isAacReady(recording)).thenReturn(false);
    when(jobRepo.existsByRecordingIdAndJobTypeAndStatusIn(
            eq(7L), eq(JobType.TRANSCODE_AUDIO_AAC), any()))
        .thenReturn(false);

    service.audioStatusByPublicToken(TOKEN);

    verify(jobEnqueueService, times(1)).enqueueForRecording(7L, JobType.TRANSCODE_AUDIO_AAC);
  }
}
