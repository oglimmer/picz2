/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.GeocodingProperties;
import com.oglimmer.photoupload.service.ReverseGeocodeService;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

/** The fences around a public, unauthenticated geocoding endpoint. */
@ExtendWith(MockitoExtension.class)
class GeocodeControllerTest {

  @Mock ReverseGeocodeService geocodeService;
  @Mock HttpServletRequest request;

  private GeocodingProperties properties;
  private GeocodeController controller;

  @BeforeEach
  void setUp() {
    properties = new GeocodingProperties();
    controller = new GeocodeController(geocodeService, properties);
    lenient().when(request.getRemoteAddr()).thenReturn("10.0.0.1");
  }

  @Test
  void resolvedNamesMayBeCachedByTheBrowser() {
    when(geocodeService.resolve(any(), anyString()))
        .thenReturn(List.of(new ReverseGeocodeService.ResolvedPlace(50.047, 8.574, "Frankfurt")));

    ResponseEntity<?> response = controller.reverse(List.of("50.047,8.574"), "de", request);

    assertEquals(HttpStatus.OK, response.getStatusCode());
    assertTrue(response.getHeaders().getFirst(HttpHeaders.CACHE_CONTROL).contains("max-age=86400"));
  }

  @Test
  void anUnresolvedNameIsNeverCached() {
    when(geocodeService.resolve(any(), any()))
        .thenReturn(List.of(new ReverseGeocodeService.ResolvedPlace(50.047, 8.574, null)));

    ResponseEntity<?> response = controller.reverse(List.of("50.047,8.574"), null, request);

    assertEquals(HttpStatus.OK, response.getStatusCode());
    // Otherwise a name that was merely slow would be missing from that browser for a day.
    assertTrue(response.getHeaders().getFirst(HttpHeaders.CACHE_CONTROL).contains("no-store"));
  }

  @Test
  void rejectsMalformedCoordinatesWithoutTouchingTheService() {
    ResponseEntity<?> response = controller.reverse(List.of("north-ish"), null, request);

    assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
    verify(geocodeService, never()).resolve(any(), any());
  }

  @Test
  void rejectsCoordinatesOffTheGlobe() {
    ResponseEntity<?> response = controller.reverse(List.of("91.0,8.574"), null, request);

    assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
    verify(geocodeService, never()).resolve(any(), any());
  }

  @Test
  void rejectsOversizedBatches() {
    properties.setMaxPointsPerRequest(2);

    ResponseEntity<?> response =
        controller.reverse(List.of("50.0,8.0", "50.1,8.1", "50.2,8.2"), null, request);

    assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
    verify(geocodeService, never()).resolve(any(), any());
  }

  @Test
  void oneClientCannotUseTheEndpointAsAFreeGeocoder() {
    properties.setMaxRequestsPerMinutePerClient(1);
    when(geocodeService.resolve(any(), any()))
        .thenReturn(List.of(new ReverseGeocodeService.ResolvedPlace(50.047, 8.574, "Frankfurt")));

    assertEquals(
        HttpStatus.OK, controller.reverse(List.of("50.047,8.574"), null, request).getStatusCode());
    assertEquals(
        HttpStatus.TOO_MANY_REQUESTS,
        controller.reverse(List.of("50.047,8.574"), null, request).getStatusCode());
  }
}
