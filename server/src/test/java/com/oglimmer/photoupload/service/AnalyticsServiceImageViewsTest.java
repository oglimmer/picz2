/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.SystemTags;
import com.oglimmer.photoupload.model.ImageViewsRequest;
import com.oglimmer.photoupload.model.ImageViewsRequest.Entry;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.AnalyticsEventRepository;
import com.oglimmer.photoupload.repository.ImageViewCountRepository;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.security.UserContext;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.stream.IntStream;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

/** The beacon side of the per-photo counters (D90): what is counted and what is dropped. */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class AnalyticsServiceImageViewsTest {

  @Mock AnalyticsEventRepository analyticsEventRepository;
  @Mock ImageViewCountRepository imageViewCountRepository;
  @Mock AlbumRepository albumRepository;
  @Mock SlideshowRecordingRepository slideshowRecordingRepository;
  @Mock UserContext userContext;
  @Mock HttpServletRequest request;

  @InjectMocks AnalyticsService service;

  private Album album;

  @BeforeEach
  void setUp() {
    album = new Album();
    album.setId(7L);
    when(request.getCookies()).thenReturn(new Cookie[] {new Cookie("visitor_id", "v-1")});
  }

  private static ImageViewsRequest batch(Entry... entries) {
    return new ImageViewsRequest(List.of(entries));
  }

  private void viewable(Long... ids) {
    when(imageViewCountRepository.findViewableIds(eq(7L), anyCollection(), eq(SystemTags.HIDDEN)))
        .thenReturn(List.of(ids));
  }

  @Test
  void eachViewablePhotoIsAddedForTheVisitor() {
    viewable(1L, 2L);

    service.logImageViews(album, batch(new Entry(1L, 1, 3), new Entry(2L, 0, 1)), request);

    verify(imageViewCountRepository).addViews(eq(7L), eq(1L), eq("v-1"), eq(1), eq(3), any());
    verify(imageViewCountRepository).addViews(eq(7L), eq(2L), eq("v-1"), eq(0), eq(1), any());
  }

  /** A made-up id, a hidden photo, a text card or a photo from another album: never counted. */
  @Test
  void anIdThatIsNotAViewablePhotoIsDropped() {
    viewable(1L);

    service.logImageViews(album, batch(new Entry(1L, 1, 0), new Entry(99L, 1, 0)), request);

    verify(imageViewCountRepository).addViews(eq(7L), eq(1L), anyString(), eq(1), eq(0), any());
    verify(imageViewCountRepository, never())
        .addViews(anyLong(), eq(99L), anyString(), anyInt(), anyInt(), any(Instant.class));
  }

  @Test
  void theSameIdTwiceIsMergedIntoOneUpsert() {
    viewable(1L);

    service.logImageViews(album, batch(new Entry(1L, 1, 2), new Entry(1L, 1, 3)), request);

    verify(imageViewCountRepository).addViews(eq(7L), eq(1L), anyString(), eq(2), eq(5), any());
  }

  @Test
  void countsAreClampedAndNegativesReadAsZero() {
    viewable(1L);

    service.logImageViews(album, batch(new Entry(1L, 1_000_000, -5)), request);

    verify(imageViewCountRepository)
        .addViews(
            eq(7L), eq(1L), anyString(), eq(AnalyticsService.MAX_COUNT_PER_ENTRY), eq(0), any());
  }

  @Test
  void aBatchIsCutAtTheEntryCap() {
    List<Entry> entries = new ArrayList<>();
    IntStream.rangeClosed(1, AnalyticsService.MAX_ENTRIES_PER_BATCH + 50)
        .forEach(i -> entries.add(new Entry((long) i, 1, 0)));
    when(imageViewCountRepository.findViewableIds(eq(7L), anyCollection(), anyString()))
        .thenAnswer(inv -> new ArrayList<Long>(inv.getArgument(1)));

    service.logImageViews(album, new ImageViewsRequest(entries), request);

    @SuppressWarnings("unchecked")
    ArgumentCaptor<java.util.Collection<Long>> asked =
        ArgumentCaptor.forClass(java.util.Collection.class);
    verify(imageViewCountRepository).findViewableIds(eq(7L), asked.capture(), anyString());
    org.assertj.core.api.Assertions.assertThat(Set.copyOf(asked.getValue()))
        .hasSize(AnalyticsService.MAX_ENTRIES_PER_BATCH);
  }

  @Test
  void entriesWithNothingInThemAreNotLookedUp() {
    service.logImageViews(album, batch(new Entry(1L, 0, 0)), request);

    verifyNoInteractions(imageViewCountRepository);
  }

  @Test
  void aPausedAlbumCountsNothing() {
    album.setAnalyticsPaused(true);

    service.logImageViews(album, batch(new Entry(1L, 1, 1)), request);

    verifyNoInteractions(imageViewCountRepository);
  }

  @Test
  void anEmptyOrMissingBatchIsIgnored() {
    service.logImageViews(album, null, request);
    service.logImageViews(album, new ImageViewsRequest(null), request);
    service.logImageViews(album, new ImageViewsRequest(List.of()), request);

    verifyNoInteractions(imageViewCountRepository);
  }
}
