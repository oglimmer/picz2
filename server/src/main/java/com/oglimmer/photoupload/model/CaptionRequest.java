/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Body of {@code PUT /api/files/{id}/caption} (D69). A null or blank {@code caption} clears the
 * asset's caption — there is no separate delete endpoint.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class CaptionRequest {

  private String caption;
}
