/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.model.FileInfo;
import com.oglimmer.photoupload.model.UploadFileResponse;
import com.oglimmer.photoupload.model.UploadMultipleResponse;
import com.oglimmer.photoupload.service.FileStorageService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentMatchers;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockMultipartFile;

@ExtendWith(MockitoExtension.class)
class UploadControllerTest {

  @Mock FileStorageService fileStorageService;

  @InjectMocks UploadController controller;

  private static FileInfo info(long id) {
    FileInfo fi = new FileInfo();
    fi.setId(id);
    fi.setOriginalName("test.jpg");
    fi.setSize(123L);
    fi.setProcessingStatus(ProcessingStatus.QUEUED);
    return fi;
  }

  @Test
  void uploadFileReturnsAcceptedWithProcessingStatus() throws Exception {
    when(fileStorageService.storeFile(
            ArgumentMatchers.any(), ArgumentMatchers.any(), ArgumentMatchers.any()))
        .thenReturn(info(1L));

    MockMultipartFile file =
        new MockMultipartFile("file", "test.jpg", "image/jpeg", new byte[] {1, 2, 3});
    ResponseEntity<UploadFileResponse> resp = controller.uploadFile(file, 5L, "cid");

    assertEquals(HttpStatus.ACCEPTED, resp.getStatusCode());
    UploadFileResponse body = resp.getBody();
    assertNotNull(body);
    assertTrue(body.isSuccess());
    assertEquals(ProcessingStatus.QUEUED, body.getFile().getProcessingStatus());
  }

  @Test
  void uploadMultipleReturnsAccepted() throws Exception {
    when(fileStorageService.storeFile(
            ArgumentMatchers.any(), ArgumentMatchers.any(), ArgumentMatchers.any()))
        .thenReturn(info(1L), info(2L));
    when(fileStorageService.byteCountToDisplaySize(ArgumentMatchers.anyLong())).thenReturn("246 B");

    MockMultipartFile a =
        new MockMultipartFile("files", "a.jpg", "image/jpeg", new byte[] {1, 2, 3});
    MockMultipartFile b =
        new MockMultipartFile("files", "b.jpg", "image/jpeg", new byte[] {4, 5, 6});
    ResponseEntity<UploadMultipleResponse> resp =
        controller.uploadMultipleFiles(new MockMultipartFile[] {a, b}, 5L);

    assertEquals(HttpStatus.ACCEPTED, resp.getStatusCode());
    assertEquals(2, resp.getBody().getCount());
  }
}
