/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import org.springframework.context.annotation.Profile;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.model.MessageResponse;
import com.oglimmer.photoupload.model.RecordingAudioInfo;
import com.oglimmer.photoupload.model.RecordingInfo;
import com.oglimmer.photoupload.model.RecordingRequest;
import com.oglimmer.photoupload.model.RecordingResponse;
import com.oglimmer.photoupload.model.RecordingsListResponse;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.service.AnalyticsService;
import com.oglimmer.photoupload.service.ObjectStorageService;
import com.oglimmer.photoupload.service.SlideshowRecordingService;
import com.oglimmer.photoupload.util.RangeRequestHandler;
import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.io.OutputStream;
import java.util.List;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

@Profile(Profiles.API)
@RestController
@RequestMapping("/api")
@Slf4j
@RequiredArgsConstructor
public class SlideshowRecordingController {

  private final SlideshowRecordingService slideshowRecordingService;
  private final ObjectMapper objectMapper;
  // Optional: present iff storage.s3.enabled=true. Used to mint short-lived presigned URLs for
  // S3-backed recordings — the client follows the 302 directly to MinIO, which handles HTTP
  // Range natively, so the API pod stays out of the audio data path.
  private final Optional<ObjectStorageService> objectStorage;
  private final AnalyticsService analyticsService;
  private final SlideshowRecordingRepository slideshowRecordingRepository;

  @PostMapping("/albums/{albumId}/recordings")
  public ResponseEntity<RecordingResponse> uploadRecording(
      @PathVariable Long albumId,
      @RequestParam("audio") MultipartFile audioFile,
      @RequestParam("data") String dataJson) {
    try {
      // Parse the JSON data
      RecordingRequest request = objectMapper.readValue(dataJson, RecordingRequest.class);

      // Validate audio file
      if (audioFile.isEmpty()) {
        throw new ValidationException("Audio file is required");
      }

      // Save recording
      RecordingInfo recordingInfo =
          slideshowRecordingService.saveRecording(albumId, audioFile, request);

      RecordingResponse response =
          RecordingResponse.builder()
              .success(true)
              .message("Recording saved successfully")
              .recording(recordingInfo)
              .build();

      return ResponseEntity.ok(response);
    } catch (IOException e) {
      log.error("Error parsing recording data", e);
      throw new ValidationException("Invalid recording data: " + e.getMessage());
    }
  }

  @GetMapping("/albums/{albumId}/recordings")
  public ResponseEntity<RecordingsListResponse> listAlbumRecordings(
      @PathVariable Long albumId,
      @RequestParam(required = false) String filterTag,
      @RequestParam(required = false) String token) {
    List<RecordingInfo> recordings;

    // Check if this is a public access request (using share token)
    if (token != null && !token.isEmpty()) {
      // Public access via share token
      recordings = slideshowRecordingService.getRecordingsByShareToken(token, filterTag);
    } else if (filterTag != null && !filterTag.isEmpty()) {
      // Authenticated access with filter tag
      recordings = slideshowRecordingService.getRecordingsByAlbumAndTag(albumId, filterTag);
    } else {
      // Authenticated access, all recordings for album
      recordings = slideshowRecordingService.getAlbumRecordings(albumId);
    }

    RecordingsListResponse response =
        RecordingsListResponse.builder()
            .success(true)
            .count(recordings.size())
            .recordings(recordings)
            .build();

    return ResponseEntity.ok(response);
  }

  @GetMapping("/recordings/{id}")
  public ResponseEntity<RecordingResponse> getRecording(@PathVariable Long id) {
    RecordingInfo recording = slideshowRecordingService.getRecording(id);

    RecordingResponse response =
        RecordingResponse.builder().success(true).recording(recording).build();

    return ResponseEntity.ok(response);
  }

  @GetMapping("/recordings/{id}/audio")
  public ResponseEntity<StreamingResponseBody> getRecordingAudio(
      @PathVariable Long id, @RequestHeader(value = "Range", required = false) String rangeHeader) {
    try {
      RecordingAudioInfo audioInfo = slideshowRecordingService.getRecordingAudioInfo(id);
      if (audioInfo.getStorageKey() != null) {
        return serveAudioFromS3(audioInfo, rangeHeader);
      }
      return RangeRequestHandler.serveFileWithRangeSupport(
          audioInfo.getAudioPath(), rangeHeader, contentTypeFor(audioInfo), audioInfo.getAudioFilename());
    } catch (Exception e) {
      log.error("Error serving recording audio", e);
      throw new RuntimeException("Error serving recording audio: " + e.getMessage(), e);
    }
  }

  @DeleteMapping("/recordings/{id}")
  public ResponseEntity<MessageResponse> deleteRecording(@PathVariable Long id) {
    try {
      slideshowRecordingService.deleteRecording(id);
    } catch (IOException e) {
      log.error("Error deleting recording", e);
      throw new RuntimeException("Error deleting recording: " + e.getMessage(), e);
    }

    MessageResponse response =
        MessageResponse.builder().success(true).message("Recording deleted successfully").build();

    return ResponseEntity.ok(response);
  }

  // Public access endpoints using public_token
  @GetMapping("/r/{publicToken}")
  public ResponseEntity<RecordingResponse> getRecordingByPublicToken(
      @PathVariable String publicToken) {
    RecordingInfo recording = slideshowRecordingService.getRecordingByPublicToken(publicToken);

    RecordingResponse response =
        RecordingResponse.builder().success(true).recording(recording).build();

    return ResponseEntity.ok(response);
  }

  @GetMapping("/r/{publicToken}/audio")
  public ResponseEntity<StreamingResponseBody> getRecordingAudioByPublicToken(
      @PathVariable String publicToken,
      @RequestHeader(value = "Range", required = false) String rangeHeader,
      HttpServletRequest request) {
    try {
      RecordingAudioInfo audioInfo =
          slideshowRecordingService.getRecordingAudioInfoByPublicToken(publicToken);
      if (audioInfo.getStorageKey() != null) {
        return serveAudioFromS3(audioInfo, rangeHeader);
      }
      return RangeRequestHandler.serveFileWithRangeSupport(
          audioInfo.getAudioPath(), rangeHeader, contentTypeFor(audioInfo), audioInfo.getAudioFilename());
    } catch (Exception e) {
      log.error("Error serving recording audio by public token", e);
      throw new RuntimeException("Error serving recording audio: " + e.getMessage(), e);
    }
  }

  /**
   * Stream an S3-backed recording back to the client with HTTP Range support. The Range header
   * is forwarded to MinIO so it does the slicing — the JVM only proxies bytes. We can't 302 to
   * a presigned URL because MinIO has no public ingress; the API pod must mediate.
   */
  private ResponseEntity<StreamingResponseBody> serveAudioFromS3(
      RecordingAudioInfo audioInfo, String rangeHeader) {
    if (objectStorage.isEmpty()) {
      throw new IllegalStateException(
          "Recording is S3-backed but ObjectStorageService is disabled — "
              + "check storage.s3.enabled");
    }
    ResponseInputStream<GetObjectResponse> stream =
        objectStorage.get().openStream(audioInfo.getStorageKey(), rangeHeader);
    GetObjectResponse meta = stream.response();
    boolean partial = meta.contentRange() != null;

    StreamingResponseBody body =
        (OutputStream out) -> {
          try (ResponseInputStream<GetObjectResponse> s = stream) {
            byte[] buf = new byte[64 * 1024];
            int n;
            while ((n = s.read(buf)) > 0) {
              out.write(buf, 0, n);
            }
          }
        };

    ResponseEntity.BodyBuilder builder =
        ResponseEntity.status(partial ? HttpStatus.PARTIAL_CONTENT : HttpStatus.OK)
            .contentType(MediaType.parseMediaType(contentTypeFor(audioInfo)))
            .header(HttpHeaders.ACCEPT_RANGES, "bytes")
            .header(
                HttpHeaders.CONTENT_DISPOSITION,
                "inline; filename=\"" + audioInfo.getAudioFilename() + "\"");
    if (meta.contentLength() != null) {
      builder.contentLength(meta.contentLength());
    }
    if (partial) {
      builder.header(HttpHeaders.CONTENT_RANGE, meta.contentRange());
    }
    return builder.body(body);
  }

  private String contentTypeFor(RecordingAudioInfo audioInfo) {
    String name = audioInfo.getAudioFilename();
    if (name != null && name.endsWith(".ogg")) {
      return "audio/ogg";
    }
    if (name != null && name.endsWith(".mp3")) {
      return "audio/mpeg";
    }
    return "audio/webm";
  }
}
