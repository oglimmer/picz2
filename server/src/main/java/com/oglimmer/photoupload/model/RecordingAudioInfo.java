/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/** Where the audio for a recording lives: an object key in the album's storage backend. */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class RecordingAudioInfo {

  private String audioFilename;
  private String storageKey;

  /** Album the recording belongs to — decides which storage backend holds {@link #storageKey}. */
  private Long albumId;
}
