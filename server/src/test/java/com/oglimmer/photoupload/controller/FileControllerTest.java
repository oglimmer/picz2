/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.oglimmer.photoupload.model.FileInfo;
import com.oglimmer.photoupload.model.FilesResponse;
import com.oglimmer.photoupload.model.MessageResponse;
import com.oglimmer.photoupload.service.FileStorageService;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class FileControllerTest {

  @Mock FileStorageService storageService;

  @InjectMocks FileController controller;

  private static FileInfo fileWithTags(long id, String name, List<String> tags) {
    FileInfo fi = new FileInfo();
    fi.setId(id);
    fi.setOriginalName(name);
    fi.setTags(tags);
    fi.setSize(10L);
    return fi;
  }

  @Test
  void listFilesFiltersByTag() {
    when(storageService.listFilesByAlbum(1L))
        .thenReturn(
            List.of(fileWithTags(1, "a", List.of("x", "y")), fileWithTags(2, "b", List.of("y"))));

    ResponseEntity<FilesResponse> resp =
        (ResponseEntity<FilesResponse>) (ResponseEntity<?>) controller.listFiles(1L, "x");
    assertEquals(200, resp.getStatusCode().value());
    FilesResponse body = resp.getBody();
    assertTrue(body.isSuccess());
    assertEquals(1, body.getFiles().size());
    assertEquals(1, body.getCount());
  }

  @Test
  void previewEndpointsDelegateAndAnswerTheRightCodes() {
    assertEquals(202, controller.requestEnhancePreview(42L).getStatusCode().value());
    verify(storageService).enqueueEnhancePreview(42L);

    assertEquals(204, controller.discardEnhancePreview(42L).getStatusCode().value());
    verify(storageService).discardEnhancePreview(42L);
  }

  @Test
  void enhanceQueuesTheJobAndAnswers202() {
    ResponseEntity<MessageResponse> resp = controller.enhanceImage(42L);

    verify(storageService).enhanceImage(42L);
    assertEquals(202, resp.getStatusCode().value());
    assertTrue(resp.getBody().isSuccess());
  }
}
