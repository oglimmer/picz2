/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.util.List;
import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class SyncChecksumsResponse {

  private boolean success;
  private List<String> checksums;
  private int count;
}
