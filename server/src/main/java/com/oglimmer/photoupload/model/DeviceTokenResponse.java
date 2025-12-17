/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.time.Instant;
import lombok.Data;

@Data
public class DeviceTokenResponse {
  private Long id;
  private String deviceToken;
  private String email;
  private Boolean isActive;
  private Instant createdAt;
}
