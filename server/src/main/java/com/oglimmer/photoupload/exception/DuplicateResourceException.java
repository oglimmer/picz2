/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.exception;

public class DuplicateResourceException extends RuntimeException {

  public DuplicateResourceException(String message) {
    super(message);
  }

  public DuplicateResourceException(String resource, String field, Object value) {
    super(String.format("%s already exists with %s: '%s'", resource, field, value));
  }
}
