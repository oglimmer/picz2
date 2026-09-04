/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.model.MessageResponse;
import com.oglimmer.photoupload.model.PresentationGroupEndRequest;
import com.oglimmer.photoupload.model.PresentationGroupInfo;
import com.oglimmer.photoupload.model.PresentationGroupRequest;
import com.oglimmer.photoupload.model.PresentationGroupResponse;
import com.oglimmer.photoupload.model.PresentationGroupsListResponse;
import com.oglimmer.photoupload.service.PresentationGroupService;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Presentation image groups. The public listing sits under {@code /api/albums/public/**}, which
 * {@code SecurityConfig} already permits for GET — the literal {@code public} segment outranks the
 * {@code {albumId}} template, same as the existing album/file endpoints.
 */
@Profile(Profiles.API)
@RestController
@RequestMapping("/api")
@Slf4j
@RequiredArgsConstructor
public class PresentationGroupController {

  private final PresentationGroupService presentationGroupService;

  @GetMapping("/albums/{albumId}/presentation-groups")
  public ResponseEntity<PresentationGroupsListResponse> listAlbumGroups(
      @PathVariable Long albumId) {
    List<PresentationGroupInfo> groups = presentationGroupService.getAlbumGroups(albumId);

    return ResponseEntity.ok(
        PresentationGroupsListResponse.builder()
            .success(true)
            .count(groups.size())
            .groups(groups)
            .build());
  }

  @GetMapping("/albums/public/{token}/presentation-groups")
  public ResponseEntity<PresentationGroupsListResponse> listPublicAlbumGroups(
      @PathVariable String token) {
    List<PresentationGroupInfo> groups = presentationGroupService.getGroupsByShareToken(token);

    return ResponseEntity.ok(
        PresentationGroupsListResponse.builder()
            .success(true)
            .count(groups.size())
            .groups(groups)
            .build());
  }

  @PostMapping("/albums/{albumId}/presentation-groups")
  public ResponseEntity<PresentationGroupResponse> createGroup(
      @PathVariable Long albumId, @RequestBody PresentationGroupRequest request) {
    PresentationGroupInfo group = presentationGroupService.createGroup(albumId, request);

    return ResponseEntity.ok(
        PresentationGroupResponse.builder()
            .success(true)
            .message("Group created successfully")
            .group(group)
            .build());
  }

  @PutMapping("/presentation-groups/{id}")
  public ResponseEntity<PresentationGroupResponse> updateGroup(
      @PathVariable Long id, @RequestBody PresentationGroupRequest request) {
    PresentationGroupInfo group = presentationGroupService.updateGroup(id, request);

    return ResponseEntity.ok(
        PresentationGroupResponse.builder()
            .success(true)
            .message("Group updated successfully")
            .group(group)
            .build());
  }

  /**
   * Moves or clears the image a group stops at. Separate from the update above so a client that
   * knows nothing about ends cannot clear one by PUTting a group body without the field.
   */
  @PutMapping("/presentation-groups/{id}/end")
  public ResponseEntity<PresentationGroupResponse> setGroupEnd(
      @PathVariable Long id, @RequestBody PresentationGroupEndRequest request) {
    PresentationGroupInfo group =
        presentationGroupService.setGroupEnd(id, request == null ? null : request.getEndFileId());

    return ResponseEntity.ok(
        PresentationGroupResponse.builder()
            .success(true)
            .message("Group end updated successfully")
            .group(group)
            .build());
  }

  @DeleteMapping("/presentation-groups/{id}")
  public ResponseEntity<MessageResponse> deleteGroup(@PathVariable Long id) {
    presentationGroupService.deleteGroup(id);

    return ResponseEntity.ok(
        MessageResponse.builder().success(true).message("Group deleted successfully").build());
  }
}
