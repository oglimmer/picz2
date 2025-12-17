/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

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
  private Long totalEvents;
  private Long uniqueVisitors;
  private Long pageViews;
  private Long filterChanges;
  private Long audioPlays;
  private Map<String, Long> filterTagCounts;
}
