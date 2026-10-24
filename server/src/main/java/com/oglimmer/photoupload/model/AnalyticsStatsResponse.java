/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.util.List;
import java.util.Map;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AnalyticsStatsResponse {

  private boolean success;
  private boolean analyticsPaused;
  private Long totalEvents;
  private Long uniqueVisitors;
  private Long pageViews;
  private Long filterChanges;
  private Long audioPlays;
  private Map<String, Long> filterTagCounts;

  // Full-screen looks on the public share page (D90).

  /** Photos opened from the grid or the map. */
  private long imageOpens;

  /** Photos reached with next/previous while already full screen. */
  private long imageWalkIns;

  /** Distinct photos looked at full screen at least once. */
  private long imagesViewed;

  /** Photos a visitor could look at: pictures and videos that are not hidden. */
  private long imagesInAlbum;

  /** The most looked-at photos, busiest first, at most 50. */
  private List<ImageViewStat> topImages;
}
