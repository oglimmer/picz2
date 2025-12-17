/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class AlbumSubscriptionResponse {

  private Long id;
  private String email;
  private Boolean notifyAlbumUpdates;
  private Boolean notifyNewAlbums;
  private Boolean confirmed;
  private String message;

  public AlbumSubscriptionResponse(String message) {
    this.message = message;
  }
}
