/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.time.Instant;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class AlbumInfo {

  private Long id;
  private String name;
  private String description;
  private Instant createdAt;
  private Instant updatedAt;
  private Integer displayOrder;
  private Integer fileCount;
  private String coverImageFilename; // Filename of cover image (first photo in album)
  private String coverImageToken; // Public token of cover image
  private String shareToken; // Public share token for accessing album
}
