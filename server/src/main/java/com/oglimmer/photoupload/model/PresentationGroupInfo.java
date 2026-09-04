/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.time.Instant;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class PresentationGroupInfo {

  private Long id;
  private Long albumId;

  /** Tag name — the client filters on the same value it puts in the presentation tag dropdown. */
  private String tag;

  private Long startFileId;

  /** Last image in the group, or null for "runs until the next group starts". */
  private Long endFileId;

  private String label;
  private String text;
  private Instant createdAt;
  private Instant updatedAt;
}
