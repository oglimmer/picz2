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

  /**
   * Optional last image of the group. Null on create means "run until the next group starts".
   * Ignored on update — the end is moved through the dedicated end endpoint so a client that does
   * not know about ends cannot wipe one by sending a body without it.
   */
  private Long endFileId;

  private String label;
  private String text;
}
