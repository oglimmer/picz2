/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Body of {@code PUT /api/settings/new-asset-tag} (D70).
 *
 * <p>{@code confirmed} is not decoration. Moving to {@code all} means every future photo is on the
 * public share link the moment it finishes processing, with no review, so the clients make the user
 * acknowledge that in a dialog and send the acknowledgement with the change. A client that forgets
 * the dialog gets a 400 rather than silently opening the album up.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class NewAssetTagRequest {

  private String tagName;
  private boolean confirmed;
}
