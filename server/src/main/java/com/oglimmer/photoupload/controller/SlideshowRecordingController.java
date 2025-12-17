/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

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
import com.oglimmer.photoupload.service.SlideshowRecordingService;
import com.oglimmer.photoupload.util.RangeRequestHandler;
import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.Resource;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api")
@Slf4j
@RequiredArgsConstructor
public class SlideshowRecordingController {

  private final SlideshowRecordingService slideshowRecordingService;
  private final ObjectMapper objectMapper;
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
  public ResponseEntity<Resource> getRecordingAudio(
      @PathVariable Long id, @RequestHeader(value = "Range", required = false) String rangeHeader) {
    try {
      // Get recording audio info
      RecordingAudioInfo audioInfo = slideshowRecordingService.getRecordingAudioInfo(id);

      // Determine content type from filename extension
      String contentType = "audio/webm";
      if (audioInfo.getAudioFilename().endsWith(".ogg")) {
        contentType = "audio/ogg";
      } else if (audioInfo.getAudioFilename().endsWith(".mp3")) {
        contentType = "audio/mpeg";
      }

      // Serve file with range request support
      return RangeRequestHandler.serveFileWithRangeSupport(
          audioInfo.getAudioPath(), rangeHeader, contentType, audioInfo.getAudioFilename());
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
  public ResponseEntity<Resource> getRecordingAudioByPublicToken(
      @PathVariable String publicToken,
      @RequestHeader(value = "Range", required = false) String rangeHeader,
      HttpServletRequest request) {
    try {
      // Get recording audio info by public token
      RecordingAudioInfo audioInfo =
          slideshowRecordingService.getRecordingAudioInfoByPublicToken(publicToken);

      // Determine content type from filename extension
      String contentType = "audio/webm";
      if (audioInfo.getAudioFilename().endsWith(".ogg")) {
        contentType = "audio/ogg";
      } else if (audioInfo.getAudioFilename().endsWith(".mp3")) {
        contentType = "audio/mpeg";
      }

      // Serve file with range request support
      return RangeRequestHandler.serveFileWithRangeSupport(
          audioInfo.getAudioPath(), rangeHeader, contentType, audioInfo.getAudioFilename());
    } catch (Exception e) {
      log.error("Error serving recording audio by public token", e);
      throw new RuntimeException("Error serving recording audio: " + e.getMessage(), e);
    }
  }
}
