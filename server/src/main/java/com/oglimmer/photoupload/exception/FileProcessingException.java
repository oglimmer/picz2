/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.exception;

public class FileProcessingException extends RuntimeException {

  public FileProcessingException(String message) {
    super(message);
  }

  public FileProcessingException(String message, Throwable cause) {
    super(message, cause);
  }
}
