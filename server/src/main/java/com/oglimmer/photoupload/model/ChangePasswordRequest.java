/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.Data;

@Data
public class ChangePasswordRequest {
  private String currentPassword;
  private String newPassword;
}
