/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Where a group stops. Its own request body — and its own endpoint — on purpose: folding it into
 * {@code PresentationGroupRequest} would mean an older client that PUTs a group without the field
 * silently clears the end marker.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class PresentationGroupEndRequest {

  /** Last image that still belongs to the group. Null clears the end and reopens the group. */
  private Long endFileId;
}
