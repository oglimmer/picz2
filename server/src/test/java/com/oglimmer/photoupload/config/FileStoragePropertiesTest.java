/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

class FileStoragePropertiesTest {

  @Test
  void defaultsAreAsExpected() {
    FileStorageProperties p = new FileStorageProperties();
    assertEquals("uploads", p.getUploadDir());
    assertEquals(500L * 1024 * 1024, p.getMaxFileSize());
    assertEquals(100, p.getMaxFilesPerRequest());
  }

  @Test
  void settersApplyValues() {
    FileStorageProperties p = new FileStorageProperties();
    p.setUploadDir("/tmp/u");
    p.setMaxFileSize(1234);
    p.setMaxFilesPerRequest(5);
    assertEquals("/tmp/u", p.getUploadDir());
    assertEquals(1234, p.getMaxFileSize());
    assertEquals(5, p.getMaxFilesPerRequest());
  }
}
