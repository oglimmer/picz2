/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.time.LocalDateTime;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ErrorResponse {

  private LocalDateTime timestamp;
  private int status;
  private String error;
  private String message;
  private String path;

  public static ErrorResponse of(int status, String error, String message, String path) {
    return ErrorResponse.builder()
        .timestamp(LocalDateTime.now())
        .status(status)
        .error(error)
        .message(message)
        .path(path)
        .build();
  }
}
