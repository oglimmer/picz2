/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/** Answer to {@code GET/PUT /api/settings/new-asset-tag} (D70). */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class NewAssetTagResponse {

  private boolean success;

  /** {@code hidden} or {@code all} — the tag every newly registered asset of this user gets. */
  private String tagName;
}
