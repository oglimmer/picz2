/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class HeicConversionServiceTest {

  /**
   * On a host that doesn't have a real HEIC encoder available, both paths fail gracefully and the
   * service returns false rather than throwing. This is the only behavior we can verify without a
   * real HEIC fixture; thumbnail correctness is covered by manual + integration tests.
   */
  @Test
  void returnsFalseWhenNeitherToolCanProduceOutput(@TempDir Path tempDir) throws IOException {
    Path src = tempDir.resolve("not-really.heic");
    Files.writeString(src, "definitely not a heic file", StandardCharsets.UTF_8);
    Path dst = tempDir.resolve("out.jpg");

    boolean ok = new HeicConversionService().convertHeicToJpeg(src, dst);

    // Either the tool isn't installed (IOException → false) or it rejects the bogus input
    // (non-zero exit → false). Both end at "service returned false, no output file".
    assertThat(ok).isFalse();
    assertThat(dst).doesNotExist();
  }

  /**
   * If a real {@code heif-convert} is installed, exercise it end-to-end with a 1×1 JPEG dressed up
   * as HEIC just to confirm the primary path runs (it will reject the input, leaving the fallback
   * to also reject — both fail, service returns false). The point of this test is the lack of
   * exception, not a successful conversion.
   */
  @Test
  void primaryPathRunsWhenHeifConvertExists(@TempDir Path tempDir) throws IOException {
    assumeTrue(isOnPath("heif-convert"), "heif-convert not installed on this host");

    Path src = tempDir.resolve("not-really.heic");
    Files.writeString(src, "x", StandardCharsets.UTF_8);
    Path dst = tempDir.resolve("out.jpg");

    boolean ok = new HeicConversionService().convertHeicToJpeg(src, dst);

    assertThat(ok).isFalse();
    assertThat(dst).doesNotExist();
  }

  private static boolean isOnPath(String binary) {
    String path = System.getenv("PATH");
    if (path == null) {
      return false;
    }
    for (String dir : path.split(java.io.File.pathSeparator)) {
      if (new java.io.File(dir, binary).canExecute()) {
        return true;
      }
    }
    return false;
  }
}
