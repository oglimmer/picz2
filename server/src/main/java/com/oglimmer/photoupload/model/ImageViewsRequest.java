/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.util.List;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * One batch of full-screen looks from the public share page (D90). The browser counts locally and
 * sends what piled up since the last batch, so one request carries many looks.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class ImageViewsRequest {

  private List<Entry> views;

  @Data
  @NoArgsConstructor
  @AllArgsConstructor
  public static class Entry {
    private Long fileId;
    private int opens;
    private int walkIns;
  }
}
