/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Whether a recording's audio can be played right now in the requested format.
 *
 * <p>Polled by iOS before it hands the URL to {@code AVPlayer}: {@code ready} means the AAC sibling
 * is on storage, {@code failed} means the transcode dead-lettered and waiting longer is pointless.
 * Neither flag set means "being made, ask again shortly".
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class RecordingAudioStatus {

  private boolean success;
  private boolean ready;
  private boolean failed;
}
