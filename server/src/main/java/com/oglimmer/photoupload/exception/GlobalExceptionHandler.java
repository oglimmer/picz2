/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.exception;

import com.oglimmer.photoupload.model.ErrorResponse;
import jakarta.servlet.http.HttpServletRequest;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.multipart.MaxUploadSizeExceededException;

@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

  @ExceptionHandler(ResourceNotFoundException.class)
  public ResponseEntity<ErrorResponse> handleResourceNotFoundException(
      ResourceNotFoundException ex, HttpServletRequest request) {
    log.error("Resource not found: {}", ex.getMessage());

    ErrorResponse error =
        ErrorResponse.of(
            HttpStatus.NOT_FOUND.value(), "Not Found", ex.getMessage(), request.getRequestURI());

    return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error);
  }

  @ExceptionHandler(ValidationException.class)
  public ResponseEntity<ErrorResponse> handleValidationException(
      ValidationException ex, HttpServletRequest request) {
    log.error("Validation error: {}", ex.getMessage());

    ErrorResponse error =
        ErrorResponse.of(
            HttpStatus.BAD_REQUEST.value(),
            "Bad Request",
            ex.getMessage(),
            request.getRequestURI());

    return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(error);
  }

  @ExceptionHandler(DuplicateResourceException.class)
  public ResponseEntity<ErrorResponse> handleDuplicateResourceException(
      DuplicateResourceException ex, HttpServletRequest request) {
    log.error("Duplicate resource: {}", ex.getMessage());

    ErrorResponse error =
        ErrorResponse.of(
            HttpStatus.CONFLICT.value(), "Conflict", ex.getMessage(), request.getRequestURI());

    return ResponseEntity.status(HttpStatus.CONFLICT).body(error);
  }

  @ExceptionHandler(StorageException.class)
  public ResponseEntity<ErrorResponse> handleStorageException(
      StorageException ex, HttpServletRequest request) {
    log.error("Storage error: {}", ex.getMessage(), ex);

    ErrorResponse error =
        ErrorResponse.of(
            HttpStatus.INTERNAL_SERVER_ERROR.value(),
            "Storage Error",
            ex.getMessage(),
            request.getRequestURI());

    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(error);
  }

  @ExceptionHandler(FileProcessingException.class)
  public ResponseEntity<ErrorResponse> handleFileProcessingException(
      FileProcessingException ex, HttpServletRequest request) {
    log.error("File processing error: {}", ex.getMessage(), ex);

    ErrorResponse error =
        ErrorResponse.of(
            HttpStatus.INTERNAL_SERVER_ERROR.value(),
            "File Processing Error",
            ex.getMessage(),
            request.getRequestURI());

    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(error);
  }

  @ExceptionHandler(MaxUploadSizeExceededException.class)
  public ResponseEntity<ErrorResponse> handleMaxUploadSizeExceededException(
      MaxUploadSizeExceededException ex, HttpServletRequest request) {
    log.error("File size too large: {}", ex.getMessage());

    ErrorResponse error =
        ErrorResponse.of(
            HttpStatus.BAD_REQUEST.value(),
            "Bad Request",
            "File size too large. Maximum size is 500MB.",
            request.getRequestURI());

    return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(error);
  }

  @ExceptionHandler(IllegalArgumentException.class)
  public ResponseEntity<ErrorResponse> handleIllegalArgumentException(
      IllegalArgumentException ex, HttpServletRequest request) {
    log.error("Illegal argument: {}", ex.getMessage());

    ErrorResponse error =
        ErrorResponse.of(
            HttpStatus.BAD_REQUEST.value(),
            "Bad Request",
            ex.getMessage(),
            request.getRequestURI());

    return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(error);
  }

  @ExceptionHandler(Exception.class)
  public ResponseEntity<ErrorResponse> handleGenericException(
      Exception ex, HttpServletRequest request) {
    log.error("Unexpected error occurred", ex);

    ErrorResponse error =
        ErrorResponse.of(
            HttpStatus.INTERNAL_SERVER_ERROR.value(),
            "Internal Server Error",
            "An unexpected error occurred. Please try again later.",
            request.getRequestURI());

    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(error);
  }
}
