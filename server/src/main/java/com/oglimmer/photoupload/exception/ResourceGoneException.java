/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.exception;

/**
 * 410 Gone — the requested representation existed but has been intentionally removed and will not
 * come back. Used by file-serve when a caller asks for {@code ?size=original} on an asset whose
 * original was purged by the retention CronJob (Phase 6 / Gap 4-finish). Distinct from
 * {@link ResourceNotFoundException} (404) so well-behaved clients can stop retrying.
 */
public class ResourceGoneException extends RuntimeException {

  public ResourceGoneException(String message) {
    super(message);
  }
}
