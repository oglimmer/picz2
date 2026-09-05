/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.model.StorageUsageResponse;
import com.oglimmer.photoupload.security.UserContext;
import com.oglimmer.photoupload.service.StorageQuotaService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

/**
 * The "storage full" banner's one question: is it full right now? The rule is the quota service's
 * ({@code used >= quota}), and this checks the controller passes it through unchanged — a client
 * that re-derived it from the two numbers could drift from what the upload path actually enforces.
 */
@ExtendWith(MockitoExtension.class)
class StorageUsageControllerTest {

  private static final long MB = 1024L * 1024L;

  @Mock StorageQuotaService quotaService;
  @Mock UserContext userContext;
  @InjectMocks StorageUsageController controller;

  private final User user = new User();

  @BeforeEach
  void setUp() {
    user.setId(42L);
    when(userContext.getCurrentUser()).thenReturn(user);
  }

  @Test
  void reportsRoomLeftWhenUnderQuota() {
    when(quotaService.usageFor(user)).thenReturn(new StorageQuotaService.Usage(30 * MB, 100 * MB));

    ResponseEntity<StorageUsageResponse> resp = controller.current();

    assertEquals(200, resp.getStatusCode().value());
    StorageUsageResponse body = resp.getBody();
    assertEquals(30 * MB, body.getUsedBytes());
    assertEquals(100 * MB, body.getQuotaBytes());
    assertEquals(70 * MB, body.getRemainingBytes());
    assertFalse(body.isFull());
  }

  @Test
  void reportsFullAtTheQuotaAndBeyondIt() {
    when(quotaService.usageFor(user)).thenReturn(new StorageQuotaService.Usage(100 * MB, 100 * MB));
    assertTrue(controller.current().getBody().isFull());

    // Two racing uploads can land over the line (documented in StorageQuotaService); the banner
    // must not disappear because the number went past "exactly full".
    when(quotaService.usageFor(user)).thenReturn(new StorageQuotaService.Usage(104 * MB, 100 * MB));
    StorageUsageResponse over = controller.current().getBody();
    assertTrue(over.isFull());
    assertEquals(0, over.getRemainingBytes());
  }

  @Test
  void aZeroQuotaIsFullEvenWhenEmpty() {
    // 0 is how an operator freezes an account (V45). Nothing can be uploaded, so the banner shows.
    when(quotaService.usageFor(user)).thenReturn(new StorageQuotaService.Usage(0, 0));
    assertTrue(controller.current().getBody().isFull());
  }
}
