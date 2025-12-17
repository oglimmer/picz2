/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.util.List;
import lombok.Data;

@Data
public class RecordingRequest {

  private String filterTag;
  private String language;
  private Long durationMs;
  private List<RecordingImageData> images;

  @Data
  public static class RecordingImageData {

    private Long fileId;
    private Long startTimeMs;
    private Long durationMs;
  }
}
