/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Configuration
@ConfigurationProperties(prefix = "file.upload")
@Data
public class FileStorageProperties {

  public enum Thumbnailer {
    VIPS,
    MAGICK
  }

  private String uploadDir = "uploads";
  private long maxFileSize = 500 * 1024 * 1024; // 500MB
  private int maxFilesPerRequest = 100;
  private int maxConcurrentProcessing = 2; // Maximum concurrent file processing operations
  private int processingQueueCapacity = 50; // Backlog before new uploads get 503
  private boolean duplicateDetectionEnabled = true;
  // Image thumbnail backend. vips = vipsthumbnail (low-memory shrink-on-load),
  // magick = ImageMagick convert (legacy path, kept as a flip-back).
  private Thumbnailer thumbnailer = Thumbnailer.VIPS;
}
