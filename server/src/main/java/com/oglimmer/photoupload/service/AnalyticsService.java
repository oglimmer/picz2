/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.AnalyticsEvent;
import com.oglimmer.photoupload.entity.AnalyticsEvent.EventType;
import com.oglimmer.photoupload.entity.SlideshowRecording;
import com.oglimmer.photoupload.entity.SystemTags;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.model.AnalyticsStatsResponse;
import com.oglimmer.photoupload.model.ImageViewStat;
import com.oglimmer.photoupload.model.ImageViewsRequest;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.AnalyticsEventRepository;
import com.oglimmer.photoupload.repository.AnalyticsEventRepository.EventTypeCount;
import com.oglimmer.photoupload.repository.AnalyticsEventRepository.FilterTagCount;
import com.oglimmer.photoupload.repository.ImageViewCountRepository;
import com.oglimmer.photoupload.repository.ImageViewCountRepository.ImageViewTotals;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.security.UserContext;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Slf4j
@RequiredArgsConstructor
public class AnalyticsService {

  /**
   * A batch is what one visitor piled up in about half a minute. Past these caps it is not a person
   * looking at photos, so the rest is dropped rather than counted.
   */
  static final int MAX_ENTRIES_PER_BATCH = 200;

  static final int MAX_COUNT_PER_ENTRY = 500;

  /** How many photos the owner's "most looked-at" list carries. */
  static final int TOP_IMAGES_LIMIT = 50;

  private final AnalyticsEventRepository analyticsEventRepository;
  private final ImageViewCountRepository imageViewCountRepository;
  private final AlbumRepository albumRepository;
  private final SlideshowRecordingRepository slideshowRecordingRepository;
  private final UserContext userContext;

  @Transactional
  public void logPageView(Album album, String filterTag, HttpServletRequest request) {
    logEvent(EventType.PAGE_VIEW, album, filterTag, null, request);
  }

  @Transactional
  public void logFilterChange(Album album, String filterTag, HttpServletRequest request) {
    logEvent(EventType.FILTER_CHANGE, album, filterTag, null, request);
  }

  @Transactional
  public void logAudioPlay(
      Album album, String filterTag, Long recordingId, HttpServletRequest request) {
    logEvent(EventType.AUDIO_PLAY, album, filterTag, recordingId, request);
  }

  /**
   * Adds one batch of full-screen looks (D90). Lenient on purpose: an id that is not a visible
   * photo of this album is skipped, a count is clamped, and nothing here answers with an error —
   * the sender is a beacon nobody waits on.
   */
  @Transactional
  public void logImageViews(Album album, ImageViewsRequest batch, HttpServletRequest request) {
    if (album.isAnalyticsPaused()) {
      log.debug("Analytics paused for album: {}, skipping image views", album.getId());
      return;
    }
    if (batch == null || batch.getViews() == null || batch.getViews().isEmpty()) {
      return;
    }

    // Merge first: a client is allowed to send the same id twice, the upsert wants it once.
    Map<Long, int[]> merged = new LinkedHashMap<>();
    batch.getViews().stream()
        .filter(Objects::nonNull)
        .filter(e -> e.getFileId() != null)
        .limit(MAX_ENTRIES_PER_BATCH)
        .forEach(
            e -> {
              int[] sum = merged.computeIfAbsent(e.getFileId(), id -> new int[2]);
              sum[0] = clamp(sum[0] + clamp(e.getOpens()));
              sum[1] = clamp(sum[1] + clamp(e.getWalkIns()));
            });
    merged.values().removeIf(sum -> sum[0] == 0 && sum[1] == 0);
    if (merged.isEmpty()) {
      return;
    }

    Set<Long> viewable =
        new HashSet<>(
            imageViewCountRepository.findViewableIds(
                album.getId(), merged.keySet(), SystemTags.HIDDEN));

    String visitorId = getVisitorId(request);
    Instant now = Instant.now();
    merged.forEach(
        (fileId, sum) -> {
          if (viewable.contains(fileId)) {
            imageViewCountRepository.addViews(
                album.getId(), fileId, visitorId, sum[0], sum[1], now);
          }
        });
    log.debug(
        "Logged image views for {} photo(s) in album: {} (visitor: {})",
        viewable.size(),
        album.getId(),
        visitorId);
  }

  private static int clamp(int count) {
    return Math.max(0, Math.min(MAX_COUNT_PER_ENTRY, count));
  }

  private void logEvent(
      EventType eventType,
      Album album,
      String filterTag,
      Long recordingId,
      HttpServletRequest request) {

    if (album.isAnalyticsPaused()) {
      log.debug("Analytics paused for album: {}, skipping event: {}", album.getId(), eventType);
      return;
    }

    // Get or generate visitor ID from cookie
    String visitorId = getVisitorId(request);

    // Create analytics event
    AnalyticsEvent event = new AnalyticsEvent();
    event.setEventType(eventType);
    event.setAlbum(album);
    event.setFilterTag(filterTag);
    event.setVisitorId(visitorId);
    event.setUserAgent(request.getHeader("User-Agent"));
    event.setIpAddress(getClientIpAddress(request));
    event.setCreatedAt(Instant.now());

    // Set recording if provided
    if (recordingId != null) {
      SlideshowRecording recording =
          slideshowRecordingRepository
              .findById(recordingId)
              .orElseThrow(
                  () -> new ResourceNotFoundException("Recording", "id", recordingId.toString()));
      event.setRecording(recording);
    }

    analyticsEventRepository.save(event);
    log.debug(
        "Logged analytics event: {} for album: {} (visitor: {})",
        eventType,
        album.getId(),
        visitorId);
  }

  private String getVisitorId(HttpServletRequest request) {
    // Try to get visitor ID from cookie (if user gave consent)
    if (request.getCookies() != null) {
      for (var cookie : request.getCookies()) {
        if ("visitor_id".equals(cookie.getName())) {
          String cookieValue = cookie.getValue();
          log.debug("Using visitor_id from cookie: {}", cookieValue);
          return cookieValue;
        }
      }
    }

    // Fallback: generate from IP + User-Agent hash
    // This is used when user declined cookies or before consent was given
    // Less accurate for tracking but respects privacy preferences
    String ip = getClientIpAddress(request);
    String userAgent = request.getHeader("User-Agent");
    if (userAgent == null) {
      userAgent = "unknown";
    }

    // Use Math.abs to ensure positive hash, then convert to hex for shorter ID
    int hash = Math.abs((ip + userAgent).hashCode());
    String fallbackId = "fallback-" + Integer.toHexString(hash);
    log.debug("No cookie found, using fallback visitor_id: {}", fallbackId);

    return fallbackId;
  }

  @Transactional(readOnly = true)
  public AnalyticsStatsResponse getStatisticsForAlbum(Long albumId) {
    // Ensure user has access to this album
    Album album =
        albumRepository
            .findByUserAndId(userContext.getCurrentUser(), albumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId.toString()));

    // Get event type counts
    List<EventTypeCount> eventTypeCounts =
        analyticsEventRepository.countEventsByTypeForAlbum(album);
    Map<String, Long> eventTypeMap = new HashMap<>();
    for (EventTypeCount etc : eventTypeCounts) {
      eventTypeMap.put(etc.getEventType(), etc.getCount());
    }

    // Get filter tag counts
    List<FilterTagCount> filterTagCounts =
        analyticsEventRepository.countEventsByFilterTagForAlbum(album);
    Map<String, Long> filterTagMap = new HashMap<>();
    for (FilterTagCount ftc : filterTagCounts) {
      filterTagMap.put(ftc.getFilterTag(), ftc.getCount());
    }

    // Get unique visitors count
    Long uniqueVisitors = analyticsEventRepository.countUniqueVisitorsByAlbum(album);

    // Calculate total events
    Long totalEvents = eventTypeMap.values().stream().mapToLong(Long::longValue).sum();

    // Full-screen looks per photo (D90). Not part of totalEvents: these are counters, not events.
    ImageViewTotals imageTotals = imageViewCountRepository.findTotals(album.getId());
    List<ImageViewStat> topImages =
        imageViewCountRepository.findTopImages(album.getId(), TOP_IMAGES_LIMIT).stream()
            .map(
                row ->
                    ImageViewStat.builder()
                        .fileId(row.getFileId())
                        .publicToken(row.getPublicToken())
                        .originalName(row.getOriginalName())
                        .mimeType(row.getMimeType())
                        .opens(orZero(row.getOpens()))
                        .walkIns(orZero(row.getWalkIns()))
                        .viewers(orZero(row.getViewers()))
                        .build())
            .toList();

    return AnalyticsStatsResponse.builder()
        .success(true)
        .analyticsPaused(album.isAnalyticsPaused())
        .totalEvents(totalEvents)
        .uniqueVisitors(uniqueVisitors)
        .pageViews(eventTypeMap.getOrDefault("PAGE_VIEW", 0L))
        .filterChanges(eventTypeMap.getOrDefault("FILTER_CHANGE", 0L))
        .audioPlays(eventTypeMap.getOrDefault("AUDIO_PLAY", 0L))
        .filterTagCounts(filterTagMap)
        .imageOpens(imageTotals == null ? 0 : orZero(imageTotals.getOpens()))
        .imageWalkIns(imageTotals == null ? 0 : orZero(imageTotals.getWalkIns()))
        .imagesViewed(imageTotals == null ? 0 : orZero(imageTotals.getImagesViewed()))
        .imagesInAlbum(imageViewCountRepository.countViewable(album.getId(), SystemTags.HIDDEN))
        .topImages(topImages)
        .build();
  }

  private static long orZero(Long value) {
    return value == null ? 0 : value;
  }

  @Transactional
  public void resetAnalyticsForAlbum(Long albumId) {
    Album album =
        albumRepository
            .findByUserAndId(userContext.getCurrentUser(), albumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId.toString()));
    analyticsEventRepository.deleteByAlbum(album);
    imageViewCountRepository.deleteByAlbumId(album.getId());
    log.info("Reset analytics for album: {}", albumId);
  }

  @Transactional
  public boolean setAnalyticsPaused(Long albumId, boolean paused) {
    Album album =
        albumRepository
            .findByUserAndId(userContext.getCurrentUser(), albumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId.toString()));
    album.setAnalyticsPaused(paused);
    log.info("Analytics {} for album: {}", paused ? "paused" : "resumed", albumId);
    return paused;
  }

  private String getClientIpAddress(HttpServletRequest request) {
    // Debug logging: Log all headers for troubleshooting reverse proxy setup
    if (log.isTraceEnabled()) {
      log.trace("=== Request Headers (for IP detection) ===");
      var headerNames = request.getHeaderNames();
      while (headerNames.hasMoreElements()) {
        String headerName = headerNames.nextElement();
        String headerValue = request.getHeader(headerName);
        log.trace("  {}: {}", headerName, headerValue);
      }
      log.trace("  Remote Address: {}", request.getRemoteAddr());
      log.trace("  Remote Host: {}", request.getRemoteHost());
      log.trace("  Remote Port: {}", request.getRemotePort());
      log.trace("==========================================");
    }

    String xForwardedFor = request.getHeader("X-Forwarded-For");
    if (xForwardedFor != null && !xForwardedFor.isEmpty()) {
      // X-Forwarded-For can contain multiple IPs, take the first one (client IP)
      String clientIp = xForwardedFor.split(",")[0].trim();
      log.debug("Using X-Forwarded-For header for IP: {}", clientIp);
      return clientIp;
    }

    String xRealIp = request.getHeader("X-Real-IP");
    if (xRealIp != null && !xRealIp.isEmpty()) {
      log.debug("Using X-Real-IP header for IP: {}", xRealIp);
      return xRealIp;
    }

    String remoteAddr = request.getRemoteAddr();
    log.debug("Using RemoteAddr for IP: {}", remoteAddr);
    return remoteAddr;
  }
}
