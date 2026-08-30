/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.exception;

import com.oglimmer.photoupload.model.ErrorResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.apache.catalina.connector.ClientAbortException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.async.AsyncRequestNotUsableException;
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

  @ExceptionHandler(ResourceGoneException.class)
  public ResponseEntity<ErrorResponse> handleResourceGoneException(
      ResourceGoneException ex, HttpServletRequest request) {
    log.info("Resource gone: {}", ex.getMessage());

    ErrorResponse error =
        ErrorResponse.of(HttpStatus.GONE.value(), "Gone", ex.getMessage(), request.getRequestURI());

    return ResponseEntity.status(HttpStatus.GONE).body(error);
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

  /**
   * 507 rather than 400: the request was well-formed and the file was fine, the account simply has
   * no room. Retrying it unchanged cannot succeed, so a client must show the message rather than
   * back off and try again — which is exactly what it would do for a 5xx it did not recognise.
   */
  @ExceptionHandler(StorageQuotaExceededException.class)
  public ResponseEntity<ErrorResponse> handleStorageQuotaExceeded(
      StorageQuotaExceededException ex, HttpServletRequest request) {
    log.warn("Storage quota exceeded: {}", ex.getMessage());

    ErrorResponse error =
        ErrorResponse.of(
            HttpStatus.INSUFFICIENT_STORAGE.value(),
            "Insufficient Storage",
            ex.getMessage(),
            request.getRequestURI());

    return ResponseEntity.status(HttpStatus.INSUFFICIENT_STORAGE).body(error);
  }

  @ExceptionHandler(MinioUnavailableException.class)
  public ResponseEntity<ErrorResponse> handleMinioUnavailable(
      MinioUnavailableException ex, HttpServletRequest request) {
    // Logged at WARN, not ERROR — circuit-open is an expected, transient outage signal, not a bug.
    log.warn("MinIO unavailable for {}: {}", request.getRequestURI(), ex.getMessage());

    ErrorResponse error =
        ErrorResponse.of(
            HttpStatus.SERVICE_UNAVAILABLE.value(),
            "Service Unavailable",
            "Object storage is temporarily unreachable. Please retry shortly.",
            request.getRequestURI());

    return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
        .header("Retry-After", "30")
        .body(error);
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

  @ExceptionHandler({AsyncRequestNotUsableException.class, ClientAbortException.class})
  public void handleClientDisconnect(Exception ex, HttpServletRequest request) {
    log.debug(
        "Client disconnected during response to {}: {}", request.getRequestURI(), ex.getMessage());
  }

  /**
   * The requested rendition is still being produced. 503 rather than 404 or 500: the resource will
   * exist shortly, and {@code Retry-After} tells the client how long to wait before asking again.
   */
  @ExceptionHandler(AudioNotReadyException.class)
  public ResponseEntity<ErrorResponse> handleAudioNotReady(
      AudioNotReadyException ex, HttpServletRequest request) {
    ErrorResponse error =
        ErrorResponse.of(
            HttpStatus.SERVICE_UNAVAILABLE.value(),
            ex.isFailed() ? "Audio Unavailable" : "Audio Not Ready",
            ex.getMessage(),
            request.getRequestURI());

    ResponseEntity.BodyBuilder builder = ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE);
    if (!ex.isFailed()) {
      builder.header(HttpHeaders.RETRY_AFTER, "5");
    }
    return builder.body(error);
  }

  @ExceptionHandler(Exception.class)
  public ResponseEntity<ErrorResponse> handleGenericException(
      Exception ex, HttpServletRequest request, HttpServletResponse response) {
    log.error("Unexpected error occurred", ex);

    // Once bytes are on the wire the status and Content-Type are already fixed, and writing an
    // ErrorResponse into e.g. a committed audio/mp4 response throws again from inside Tomcat's
    // recycled header state — which is how one aborted media stream used to poison the next
    // request on the same connection. Nothing can be reported at this point; log it and stop.
    if (response.isCommitted()) {
      log.debug("Response to {} already committed — no error body sent", request.getRequestURI());
      return null;
    }

    ErrorResponse error =
        ErrorResponse.of(
            HttpStatus.INTERNAL_SERVER_ERROR.value(),
            "Internal Server Error",
            "An unexpected error occurred. Please try again later.",
            request.getRequestURI());

    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(error);
  }
}
