/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.nio.file.Path;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Where the audio for a recording lives. Exactly one of {@link #audioPath} (legacy local file) or
 * {@link #storageKey} (S3 object key) is set; the controller picks the serve strategy based on
 * which is non-null.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class RecordingAudioInfo {

  private String audioFilename;
  private Path audioPath;
  private String storageKey;
}
