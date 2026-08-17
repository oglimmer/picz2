/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class PresentationGroupRequest {

  /** Tag name the group belongs to. Ignored on update — a group never changes tag. */
  private String tag;

  /** Image the group starts at. Ignored on update — use delete + create to move a group. */
  private Long startFileId;

  private String label;
  private String text;
}
