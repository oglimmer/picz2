/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.model.MessageResponse;
import com.oglimmer.photoupload.model.TagInfo;
import com.oglimmer.photoupload.model.TagRequest;
import com.oglimmer.photoupload.model.TagResponse;
import com.oglimmer.photoupload.model.TagsListResponse;
import com.oglimmer.photoupload.service.TagService;
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
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/tags")
@Slf4j
@RequiredArgsConstructor
public class TagController {

  private final TagService tagService;

  @GetMapping
  public ResponseEntity<TagsListResponse> getAllTags() {
    List<TagInfo> tags = tagService.getAllTags();

    TagsListResponse response = TagsListResponse.builder().success(true).tags(tags).build();

    return ResponseEntity.ok(response);
  }

  @PostMapping
  public ResponseEntity<TagResponse> createTag(@RequestBody TagRequest tagRequest) {
    if (tagRequest.getTagName() == null || tagRequest.getTagName().trim().isEmpty()) {
      throw new ValidationException("Tag name is required");
    }

    TagInfo tag = tagService.createTag(tagRequest.getTagName().trim());

    TagResponse response =
        TagResponse.builder().success(true).message("Tag created successfully").tag(tag).build();

    return ResponseEntity.ok(response);
  }

  @PutMapping("/{id}")
  public ResponseEntity<TagResponse> updateTag(
      @PathVariable Long id, @RequestBody TagRequest tagRequest) {
    if (tagRequest.getTagName() == null || tagRequest.getTagName().trim().isEmpty()) {
      throw new ValidationException("Tag name is required");
    }

    TagInfo tag = tagService.updateTag(id, tagRequest.getTagName().trim());

    TagResponse response =
        TagResponse.builder().success(true).message("Tag updated successfully").tag(tag).build();

    return ResponseEntity.ok(response);
  }

  @DeleteMapping("/{id}")
  public ResponseEntity<MessageResponse> deleteTag(@PathVariable Long id) {
    tagService.deleteTag(id);

    MessageResponse response =
        MessageResponse.builder().success(true).message("Tag deleted successfully").build();

    return ResponseEntity.ok(response);
  }
}
