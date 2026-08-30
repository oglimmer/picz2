/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.exception;

/**
 * The user has no room left on the instance's own storage. Distinct from {@code
 * ValidationException} because the client's correct reaction is different: nothing about the
 * request was wrong, and retrying it unchanged will keep failing until the user frees space or
 * registers their own S3.
 *
 * <p>Mapped to 507 Insufficient Storage — the server can't store it, rather than the request being
 * too large (413), which is the separate per-file limit.
 */
public class StorageQuotaExceededException extends RuntimeException {

  private final long usedBytes;
  private final long quotaBytes;
  private final long requestedBytes;

  public StorageQuotaExceededException(long usedBytes, long quotaBytes, long requestedBytes) {
    super(
        "Storage full: "
            + format(usedBytes)
            + " of "
            + format(quotaBytes)
            + " used, and this upload needs another "
            + format(requestedBytes)
            + ". Delete something, or add your own storage in settings.");
    this.usedBytes = usedBytes;
    this.quotaBytes = quotaBytes;
    this.requestedBytes = requestedBytes;
  }

  public long getUsedBytes() {
    return usedBytes;
  }

  public long getQuotaBytes() {
    return quotaBytes;
  }

  public long getRequestedBytes() {
    return requestedBytes;
  }

  /** Sizes in a message a person reads, not a number they have to divide by 1024 themselves. */
  private static String format(long bytes) {
    if (bytes < 1024) {
      return bytes + " B";
    }
    String[] units = {"KB", "MB", "GB", "TB"};
    double value = bytes / 1024.0;
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return String.format(value >= 10 ? "%.0f %s" : "%.1f %s", value, units[unit]);
  }
}
