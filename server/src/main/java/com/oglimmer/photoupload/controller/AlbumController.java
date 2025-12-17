/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.model.AlbumInfo;
import com.oglimmer.photoupload.model.AlbumRequest;
import com.oglimmer.photoupload.model.AlbumResponse;
import com.oglimmer.photoupload.model.AlbumsListResponse;
import com.oglimmer.photoupload.model.AnalyticsStatsResponse;
import com.oglimmer.photoupload.model.FileInfo;
import com.oglimmer.photoupload.model.FilesResponse;
import com.oglimmer.photoupload.model.MessageResponse;
import com.oglimmer.photoupload.model.ReorderRequest;
import com.oglimmer.photoupload.model.ReorderResponse;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.service.AlbumService;
import com.oglimmer.photoupload.service.AnalyticsService;
import com.oglimmer.photoupload.service.FileStorageService;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/albums")
@Slf4j
@RequiredArgsConstructor
public class AlbumController {

  private final AlbumService albumService;
  private final FileStorageService fileStorageService;
  private final AnalyticsService analyticsService;
  private final AlbumRepository albumRepository;

  @PostMapping
  public ResponseEntity<AlbumResponse> createAlbum(@RequestBody AlbumRequest albumRequest) {
    if (albumRequest.getName() == null || albumRequest.getName().trim().isEmpty()) {
      throw new ValidationException("Album name is required");
    }

    AlbumInfo album =
        albumService.createAlbum(albumRequest.getName(), albumRequest.getDescription());

    AlbumResponse response = AlbumResponse.builder().success(true).album(album).build();

    return ResponseEntity.ok(response);
  }

  @GetMapping
  public ResponseEntity<AlbumsListResponse> listAlbums() {
    List<AlbumInfo> albums = albumService.listAlbums();

    AlbumsListResponse response = AlbumsListResponse.builder().success(true).albums(albums).build();

    return ResponseEntity.ok(response);
  }

  @GetMapping("/{id}")
  public ResponseEntity<AlbumResponse> getAlbum(@PathVariable Long id) {
    AlbumInfo album = albumService.getAlbum(id);

    AlbumResponse response = AlbumResponse.builder().success(true).album(album).build();

    return ResponseEntity.ok(response);
  }

  @GetMapping("/{id}/files")
  public ResponseEntity<FilesResponse> getAlbumFiles(@PathVariable Long id) {
    List<FileInfo> files = fileStorageService.listFilesByAlbum(id);

    FilesResponse response =
        FilesResponse.builder().success(true).files(files).count(files.size()).build();

    return ResponseEntity.ok(response);
  }

  @GetMapping("/public/{token}")
  public ResponseEntity<AlbumResponse> getPublicAlbum(@PathVariable String token) {
    AlbumInfo album = albumService.getAlbumByShareToken(token);

    AlbumResponse response = AlbumResponse.builder().success(true).album(album).build();

    return ResponseEntity.ok(response);
  }

  @GetMapping("/public/{token}/files")
  public ResponseEntity<FilesResponse> getPublicAlbumFiles(@PathVariable String token) {
    List<FileInfo> files = fileStorageService.listFilesByAlbumByShareToken(token);

    long totalSize = files.stream().mapToLong(FileInfo::getSize).sum();

    FilesResponse response =
        FilesResponse.builder()
            .success(true)
            .files(files)
            .count(files.size())
            .totalSize(totalSize)
            .build();

    return ResponseEntity.ok(response);
  }

  @PostMapping("/public/{token}/analytics/page-view")
  public ResponseEntity<MessageResponse> logPublicPageView(
      @PathVariable String token,
      @RequestParam(required = false) String tag,
      HttpServletRequest request) {
    Album albumEntity =
        albumRepository
            .findByShareToken(token)
            .orElseThrow(() -> new RuntimeException("Album not found"));
    analyticsService.logPageView(albumEntity, tag, request);

    MessageResponse response =
        MessageResponse.builder().success(true).message("Analytics logged").build();

    return ResponseEntity.ok(response);
  }

  @PostMapping("/public/{token}/analytics/filter-change")
  public ResponseEntity<MessageResponse> logPublicFilterChange(
      @PathVariable String token, @RequestParam String tag, HttpServletRequest request) {
    Album albumEntity =
        albumRepository
            .findByShareToken(token)
            .orElseThrow(() -> new RuntimeException("Album not found"));
    analyticsService.logFilterChange(albumEntity, tag, request);

    MessageResponse response =
        MessageResponse.builder().success(true).message("Analytics logged").build();

    return ResponseEntity.ok(response);
  }

  @PostMapping("/public/{token}/analytics/audio-play")
  public ResponseEntity<MessageResponse> logPublicAudioPlay(
      @PathVariable String token,
      @RequestParam Long recordingId,
      @RequestParam(required = false) String tag,
      HttpServletRequest request) {
    Album albumEntity =
        albumRepository
            .findByShareToken(token)
            .orElseThrow(() -> new RuntimeException("Album not found"));
    analyticsService.logAudioPlay(albumEntity, tag, recordingId, request);

    MessageResponse response =
        MessageResponse.builder().success(true).message("Analytics logged").build();

    return ResponseEntity.ok(response);
  }

  @GetMapping("/{id}/analytics")
  public ResponseEntity<AnalyticsStatsResponse> getAlbumAnalytics(@PathVariable Long id) {
    AnalyticsStatsResponse stats = analyticsService.getStatisticsForAlbum(id);
    return ResponseEntity.ok(stats);
  }

  @PutMapping("/{id}")
  public ResponseEntity<AlbumResponse> updateAlbum(
      @PathVariable Long id, @RequestBody AlbumRequest albumRequest) {
    AlbumInfo album =
        albumService.updateAlbum(id, albumRequest.getName(), albumRequest.getDescription());

    AlbumResponse response = AlbumResponse.builder().success(true).album(album).build();

    return ResponseEntity.ok(response);
  }

  @DeleteMapping("/{id}")
  public ResponseEntity<MessageResponse> deleteAlbum(@PathVariable Long id) {
    albumService.deleteAlbum(id);

    MessageResponse response =
        MessageResponse.builder().success(true).message("Album deleted successfully").build();

    return ResponseEntity.ok(response);
  }

  @PutMapping("/reorder")
  public ResponseEntity<MessageResponse> reorderAlbums(@RequestBody ReorderRequest reorderRequest) {
    if (reorderRequest.getFileIds() == null || reorderRequest.getFileIds().isEmpty()) {
      throw new ValidationException("Album IDs are required");
    }

    albumService.reorderAlbums(reorderRequest.getFileIds());

    MessageResponse response =
        MessageResponse.builder().success(true).message("Albums reordered successfully").build();

    return ResponseEntity.ok(response);
  }

  // Removed: Images cannot move between albums

  @PostMapping("/{id}/reorder-by-filename")
  public ResponseEntity<ReorderResponse> reorderByFilename(@PathVariable Long id) {
    int updatedCount = albumService.reorderFilesByFilename(id);

    ReorderResponse response =
        ReorderResponse.builder()
            .success(true)
            .message("Files reordered by filename numbers")
            .updatedCount(updatedCount)
            .build();

    return ResponseEntity.ok(response);
  }

  @PostMapping("/{id}/reorder-by-exif")
  public ResponseEntity<ReorderResponse> reorderByExif(@PathVariable Long id) {
    int updatedCount = albumService.reorderFilesByExifDate(id);

    ReorderResponse response =
        ReorderResponse.builder()
            .success(true)
            .message("Files reordered by EXIF date")
            .updatedCount(updatedCount)
            .build();

    return ResponseEntity.ok(response);
  }
}
