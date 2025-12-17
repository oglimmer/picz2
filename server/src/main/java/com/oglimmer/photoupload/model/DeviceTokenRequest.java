/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class DeviceTokenRequest {
  @NotBlank private String deviceToken;

  @Email @NotBlank private String email;

  private String appVersion;
  private String deviceModel;
  private String osVersion;
}
