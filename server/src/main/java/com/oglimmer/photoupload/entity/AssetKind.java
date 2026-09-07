/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.entity;

/**
 * What an album entry actually is (D86). Not a column: it is derived from {@code
 * file_metadata.mime_type}, so there is one stored truth and no way for a second one to drift.
 *
 * <p>{@link #TEXT_CARD} is a chapter heading the owner writes into the album's order — a headline
 * plus optional body text, drawn by the clients over a blurred copy of the photo that follows it.
 * It owns no bytes: no original, no derivatives, size 0.
 *
 * <p>The mime type is what keeps a card out of everything that only makes sense for pixels. Every
 * sweep and gate in the codebase narrows on {@code image/%} or {@code video/%} — thumbnails,
 * transcode, EXIF and GPS extraction, the album cover picker, {@code requireRewritableImage} — so a
 * type outside both families is skipped by all of them without a single new condition.
 */
public enum AssetKind {
  PHOTO,
  TEXT_CARD;

  /**
   * The mime type stored on a text card's row. Private to this project — the {@code x-} prefix says
   * so — and never served to a browser, because a card has no bytes to serve.
   */
  public static final String TEXT_CARD_MIME_TYPE = "application/x-picz-text-card";

  /** Classify a row by its stored mime type. Anything that is not a card is a photo or a video. */
  public static AssetKind ofMimeType(String mimeType) {
    return TEXT_CARD_MIME_TYPE.equals(mimeType) ? TEXT_CARD : PHOTO;
  }
}
