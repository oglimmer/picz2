/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

class ApiResponseTest {

  @Test
  void successFactorySetsFields() {
    ApiResponse<String> resp = ApiResponse.success("ok");
    assertTrue(resp.isSuccess());
    assertEquals("ok", resp.getData());
    assertNull(resp.getError());
  }

  @Test
  void errorFactorySetsFields() {
    ApiResponse<Void> resp = ApiResponse.error("boom");
    assertFalse(resp.isSuccess());
    assertNull(resp.getData());
    assertEquals("boom", resp.getError());
  }
}
