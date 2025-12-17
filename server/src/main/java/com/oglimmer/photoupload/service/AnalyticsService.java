/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.AnalyticsEvent;
import com.oglimmer.photoupload.entity.AnalyticsEvent.EventType;
import com.oglimmer.photoupload.entity.SlideshowRecording;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.model.AnalyticsStatsResponse;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.AnalyticsEventRepository;
import com.oglimmer.photoupload.repository.AnalyticsEventRepository.EventTypeCount;
import com.oglimmer.photoupload.repository.AnalyticsEventRepository.FilterTagCount;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.security.UserContext;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Slf4j
@RequiredArgsConstructor
public class AnalyticsService {

  private final AnalyticsEventRepository analyticsEventRepository;
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

  @Transactional
  private void logEvent(
      EventType eventType,
      Album album,
      String filterTag,
      Long recordingId,
      HttpServletRequest request) {

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

    return AnalyticsStatsResponse.builder()
        .success(true)
        .totalEvents(totalEvents)
        .uniqueVisitors(uniqueVisitors)
        .pageViews(eventTypeMap.getOrDefault("PAGE_VIEW", 0L))
        .filterChanges(eventTypeMap.getOrDefault("FILTER_CHANGE", 0L))
        .audioPlays(eventTypeMap.getOrDefault("AUDIO_PLAY", 0L))
        .filterTagCounts(filterTagMap)
        .build();
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
