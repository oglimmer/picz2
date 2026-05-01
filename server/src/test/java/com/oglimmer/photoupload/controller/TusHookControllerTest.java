/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.TusProperties;
import com.oglimmer.photoupload.model.tus.TusHookRequest;
import com.oglimmer.photoupload.model.tus.TusHookResponse;
import com.oglimmer.photoupload.service.TusHookService;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

/**
 * Phase 5 — covers the path-secret guard and the "always 200 + JSON body" envelope. The
 * dispatch table itself (pre-create / post-finish / post-terminate handlers) lives in {@link
 * TusHookService} and is exercised by {@code TusHookServiceTest}.
 */
@ExtendWith(MockitoExtension.class)
class TusHookControllerTest {

  private static final String CORRECT_SECRET =
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

  @Mock TusProperties properties;
  @Mock TusHookService hookService;

  @InjectMocks TusHookController controller;

  @BeforeEach
  void setUp() {
    when(properties.getHookSecret()).thenReturn(CORRECT_SECRET);
  }

  @Test
  void rejectsWrongSecretAs404() {
    ResponseEntity<?> resp = controller.handle("wrong", preCreatePayload());
    assertEquals(HttpStatus.NOT_FOUND, resp.getStatusCode());
    verifyNoInteractions(hookService);
  }

  @Test
  void rejectsSameLengthWrongSecretAs404() {
    String sameLenWrong = CORRECT_SECRET.replace('0', 'f');
    ResponseEntity<?> resp = controller.handle(sameLenWrong, preCreatePayload());
    assertEquals(HttpStatus.NOT_FOUND, resp.getStatusCode());
    verifyNoInteractions(hookService);
  }

  @Test
  void rejectsEmptySecretAs404() {
    ResponseEntity<?> resp = controller.handle("", preCreatePayload());
    assertEquals(HttpStatus.NOT_FOUND, resp.getStatusCode());
    verifyNoInteractions(hookService);
  }

  @Test
  void dispatchesPreCreateAndWrapsResponse() {
    when(hookService.handlePreCreate(any())).thenReturn(TusHookResponse.allow());
    ResponseEntity<?> resp = controller.handle(CORRECT_SECRET, preCreatePayload());

    // Always HTTP 200 — tusd reads HTTPResponse.StatusCode inside the JSON body to decide what
    // to surface to the actual client.
    assertEquals(HttpStatus.OK, resp.getStatusCode());
    assertTrue(resp.getBody() instanceof TusHookResponse);
    TusHookResponse body = (TusHookResponse) resp.getBody();
    assertFalse(body.rejectUpload());
    verify(hookService, times(1)).handlePreCreate(any());
    verify(hookService, never()).handlePostFinish(any());
  }

  @Test
  void dispatchesPostFinish() {
    when(hookService.handlePostFinish(any())).thenReturn(TusHookResponse.allow());
    ResponseEntity<?> resp =
        controller.handle(
            CORRECT_SECRET,
            new TusHookRequest(
                "post-finish",
                new TusHookRequest.TusEvent(
                    new TusHookRequest.TusUpload("abc", 1L, 1L, Map.of(), null), null)));

    assertEquals(HttpStatus.OK, resp.getStatusCode());
    verify(hookService, times(1)).handlePostFinish(any());
  }

  @Test
  void dispatchesPostTerminate() {
    when(hookService.handlePostTerminate(any())).thenReturn(TusHookResponse.allow());
    ResponseEntity<?> resp =
        controller.handle(
            CORRECT_SECRET,
            new TusHookRequest(
                "post-terminate",
                new TusHookRequest.TusEvent(
                    new TusHookRequest.TusUpload("abc", 0L, 0L, Map.of(), null), null)));

    assertEquals(HttpStatus.OK, resp.getStatusCode());
    verify(hookService, times(1)).handlePostTerminate(any());
  }

  @Test
  void rejectsMissingTypeWithHookShape() {
    ResponseEntity<?> resp =
        controller.handle(
            CORRECT_SECRET,
            new TusHookRequest(
                null,
                new TusHookRequest.TusEvent(
                    new TusHookRequest.TusUpload("abc", 0L, 0L, Map.of(), null), null)));

    // Still 200 to tusd — the rejection ride along inside the JSON body.
    assertEquals(HttpStatus.OK, resp.getStatusCode());
    assertTrue(resp.getBody() instanceof TusHookResponse);
    TusHookResponse body = (TusHookResponse) resp.getBody();
    assertTrue(body.rejectUpload());
    assertEquals(400, body.httpResponse().statusCode());
    verifyNoInteractions(hookService);
  }

  @Test
  void unknownTypeIsAcked() {
    ResponseEntity<?> resp =
        controller.handle(
            CORRECT_SECRET,
            new TusHookRequest(
                "pre-finish",
                new TusHookRequest.TusEvent(
                    new TusHookRequest.TusUpload("abc", 0L, 0L, Map.of(), null), null)));

    assertEquals(HttpStatus.OK, resp.getStatusCode());
    assertTrue(resp.getBody() instanceof TusHookResponse);
    TusHookResponse body = (TusHookResponse) resp.getBody();
    assertFalse(body.rejectUpload());
    verifyNoInteractions(hookService);
  }

  private static TusHookRequest preCreatePayload() {
    return new TusHookRequest(
        "pre-create",
        new TusHookRequest.TusEvent(
            new TusHookRequest.TusUpload(null, 0L, 0L, Map.of(), null), null));
  }
}
