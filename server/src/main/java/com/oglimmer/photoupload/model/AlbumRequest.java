/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class AlbumRequest {

  private String name;
  private String description;

  /**
   * Which storage backend the album's bytes go to. Null means the system default. Honoured only on
   * create: an update carrying a different id is rejected, because moving an album means copying
   * every object and there is no correct answer for a presigned URL while that is half done.
   */
  private Long storageBackendId;
}
