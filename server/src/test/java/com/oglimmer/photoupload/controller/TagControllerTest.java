/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.model.TagInfo;
import com.oglimmer.photoupload.model.TagRequest;
import com.oglimmer.photoupload.model.TagResponse;
import com.oglimmer.photoupload.model.TagsListResponse;
import com.oglimmer.photoupload.service.TagService;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class TagControllerTest {

  @Mock TagService tagService;
  @InjectMocks TagController controller;

  @Test
  void getAllTagsReturnsList() {
    TagInfo t = new TagInfo(1L, "x", null);
    when(tagService.getAllTags()).thenReturn(List.of(t));
    ResponseEntity<TagsListResponse> resp =
        (ResponseEntity<TagsListResponse>) (ResponseEntity<?>) controller.getAllTags();
    assertEquals(200, resp.getStatusCode().value());
    TagsListResponse body = resp.getBody();
    assertTrue(body.isSuccess());
    assertEquals(1, body.getTags().size());
  }

  @Test
  void createTagRejectsBlank() {
    assertThrows(ValidationException.class, () -> controller.createTag(new TagRequest(" ")));
  }

  @Test
  void createTagSuccess() {
    TagInfo t = new TagInfo(1L, "ok", null);
    when(tagService.createTag("ok")).thenReturn(t);
    ResponseEntity<TagResponse> resp =
        (ResponseEntity<TagResponse>)
            (ResponseEntity<?>) controller.createTag(new TagRequest("ok"));
    assertEquals(200, resp.getStatusCode().value());
    TagResponse body = resp.getBody();
    assertTrue(body.isSuccess());
    assertNotNull(body.getTag());
  }

  @Test
  void updateTagPropagatesServiceError() {
    when(tagService.updateTag(1L, "a")).thenThrow(new IllegalArgumentException("boom"));
    assertThrows(
        IllegalArgumentException.class, () -> controller.updateTag(1L, new TagRequest("a")));
  }
}
