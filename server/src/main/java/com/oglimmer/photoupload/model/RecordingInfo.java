/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.time.Instant;
import java.util.List;
import lombok.Data;

@Data
public class RecordingInfo {

  private Long id;
  private Long albumId;
  private String filterTag;
  private String language;
  private String audioFilename;
  private String publicToken;
  private Long durationMs;
  private Instant createdAt;
  private List<RecordingImageInfo> images;

  @Data
  public static class RecordingImageInfo {

    private Long fileId;
    private Long startTimeMs;
    private Long durationMs;
    private Integer sequenceOrder;
  }
}
