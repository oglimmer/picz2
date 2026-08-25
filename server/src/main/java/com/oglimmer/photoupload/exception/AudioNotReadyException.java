/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.exception;

/**
 * The rendition the client asked for is not on storage yet.
 *
 * <p>Raised only for {@code format=m4a}: an iOS client cannot play the Opus/WebM master, and making
 * the AAC sibling takes about a minute on the Pi, so the request is answered immediately with a 503
 * and a {@code Retry-After} instead of holding the connection open until {@code AVPlayer} gives up.
 * A {@code TRANSCODE_AUDIO_AAC} job has been queued by the time this is thrown, unless {@link
 * #isFailed()} — then the transcode already dead-lettered and retrying will not help.
 */
public class AudioNotReadyException extends RuntimeException {

  private final boolean failed;

  public AudioNotReadyException(String message, boolean failed) {
    super(message);
    this.failed = failed;
  }

  public boolean isFailed() {
    return failed;
  }
}
