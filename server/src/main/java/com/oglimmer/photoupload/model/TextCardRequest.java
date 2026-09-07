/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Body of {@code POST /api/files/text-cards} and {@code PUT /api/files/{id}/text-card} (D86).
 *
 * <p>One shape for both because a card has nothing else to it: {@code headline} is required and
 * {@code bodyText} is optional, on create and on edit alike. {@code albumId} is read on create only
 * — a card cannot be moved between albums any more than a photo can.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class TextCardRequest {

  private Long albumId;

  private String headline;

  /** Null or blank clears the body, the same way a blank caption clears a caption. */
  private String bodyText;
}
