/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.entity.JobStatus;
import com.oglimmer.photoupload.entity.ProcessingJob;
import com.oglimmer.photoupload.repository.ProcessingJobRepository;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

class JobLeaseServiceTest {

  private ProcessingJobRepository repository;
  private JobLeaseService service;

  @BeforeEach
  void setUp() {
    repository = mock(ProcessingJobRepository.class);
    service = new JobLeaseService(repository);
  }

  @Test
  void leaseNextReturnsNullWhenQueueEmpty() {
    when(repository.findNextLeaseableId()).thenReturn(Optional.empty());

    ProcessingJob result = service.leaseNext("worker-1", 900);

    assertThat(result).isNull();
    verify(repository, never()).acquireLease(any(), anyString(), anyInt());
  }

  @Test
  void leaseNextAcquiresAndReturnsJob() {
    ProcessingJob leased = new ProcessingJob();
    leased.setId(42L);
    leased.setAssetId(7L);
    leased.setStatus(JobStatus.PROCESSING);
    leased.setAttempts(1);

    when(repository.findNextLeaseableId()).thenReturn(Optional.of(42L));
    when(repository.acquireLease(eq(42L), eq("worker-1"), eq(900))).thenReturn(1);
    when(repository.findById(42L)).thenReturn(Optional.of(leased));

    ProcessingJob result = service.leaseNext("worker-1", 900);

    assertThat(result).isNotNull();
    assertThat(result.getId()).isEqualTo(42L);
    verify(repository, times(1)).acquireLease(42L, "worker-1", 900);
  }

  @Test
  void leaseNextReturnsNullWhenAcquireUpdatesZeroRows() {
    // Defensive: row vanished between SELECT and UPDATE. Should treat as "nothing to do".
    when(repository.findNextLeaseableId()).thenReturn(Optional.of(42L));
    when(repository.acquireLease(eq(42L), anyString(), anyInt())).thenReturn(0);

    ProcessingJob result = service.leaseNext("worker-1", 900);

    assertThat(result).isNull();
  }

  @Test
  void markDoneClearsLease() {
    ProcessingJob job = newJob(1L, JobStatus.PROCESSING, 1, 3);
    job.setLeasedBy("worker-1");
    when(repository.findById(1L)).thenReturn(Optional.of(job));

    service.markDone(1L);

    ArgumentCaptor<ProcessingJob> captor = ArgumentCaptor.forClass(ProcessingJob.class);
    verify(repository).save(captor.capture());
    ProcessingJob saved = captor.getValue();
    assertThat(saved.getStatus()).isEqualTo(JobStatus.DONE);
    assertThat(saved.getLeasedBy()).isNull();
    assertThat(saved.getLeasedUntil()).isNull();
    assertThat(saved.getFinishedAt()).isNotNull();
    assertThat(saved.getLastError()).isNull();
  }

  @Test
  void markFailedBeforeMaxAttemptsStaysFailed() {
    ProcessingJob job = newJob(1L, JobStatus.PROCESSING, 1, 3);
    when(repository.findById(1L)).thenReturn(Optional.of(job));

    service.markFailedOrDeadLetter(1L, "transient blip");

    ArgumentCaptor<ProcessingJob> captor = ArgumentCaptor.forClass(ProcessingJob.class);
    verify(repository).save(captor.capture());
    assertThat(captor.getValue().getStatus()).isEqualTo(JobStatus.FAILED);
    assertThat(captor.getValue().getLastError()).isEqualTo("transient blip");
  }

  @Test
  void markFailedAtMaxAttemptsTransitionsToDeadLetter() {
    ProcessingJob job = newJob(1L, JobStatus.PROCESSING, 3, 3);
    when(repository.findById(1L)).thenReturn(Optional.of(job));

    service.markFailedOrDeadLetter(1L, "ffmpeg exit 137");

    ArgumentCaptor<ProcessingJob> captor = ArgumentCaptor.forClass(ProcessingJob.class);
    verify(repository).save(captor.capture());
    assertThat(captor.getValue().getStatus()).isEqualTo(JobStatus.DEAD_LETTER);
  }

  @Test
  void markFailedTruncatesLongError() {
    ProcessingJob job = newJob(1L, JobStatus.PROCESSING, 1, 3);
    when(repository.findById(1L)).thenReturn(Optional.of(job));

    String huge = "x".repeat(8000);
    service.markFailedOrDeadLetter(1L, huge);

    ArgumentCaptor<ProcessingJob> captor = ArgumentCaptor.forClass(ProcessingJob.class);
    verify(repository).save(captor.capture());
    assertThat(captor.getValue().getLastError()).hasSize(4000);
  }

  private ProcessingJob newJob(Long id, JobStatus status, int attempts, int maxAttempts) {
    ProcessingJob j = new ProcessingJob();
    j.setId(id);
    j.setAssetId(99L);
    j.setStatus(status);
    j.setAttempts(attempts);
    j.setMaxAttempts(maxAttempts);
    return j;
  }
}
