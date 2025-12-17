/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class FileInfo {

  private Long id;
  private String originalName;
  private String filename;
  private String publicToken;
  private long size;
  private String mimetype;
  private String path;
  private Instant uploadedAt;
  private Instant exifDateTimeOriginal;
  private Integer rotation;
  private Integer displayOrder;
  private List<String> tags = new ArrayList<>();
  private Long albumId;
  private String albumName;
}
