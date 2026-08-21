/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.GeocodingProperties;
import com.oglimmer.photoupload.entity.GeocodeCacheEntry;
import com.oglimmer.photoupload.repository.GeocodeCacheRepository;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * The point of this service is that Apple is asked as seldom as possible, so that is what these
 * tests pin down: repeats, near-misses, duplicates in one batch and the outbound ceiling.
 */
@ExtendWith(MockitoExtension.class)
class ReverseGeocodeServiceTest {

  @Mock GeocodeCacheRepository repository;
  @Mock AppleMapsGeocodeClient client;
  @Mock AppleMapsTokenService tokenService;

  private GeocodingProperties properties;
  private ReverseGeocodeService service;

  private static final AppleMapsGeocodeClient.ApplePlace FRANKFURT =
      new AppleMapsGeocodeClient.ApplePlace(
          "Frankfurt am Main", "Frankfurt", null, "Hesse", "Germany", "DE");

  @BeforeEach
  void setUp() {
    properties = new GeocodingProperties();
    lenient().when(tokenService.isEnabled()).thenReturn(true);
    lenient().when(repository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
    service =
        new ReverseGeocodeService(
            repository, client, tokenService, properties, new SimpleMeterRegistry());
  }

  /** Mirrors ReverseGeocodeService.LABEL_VERSION — bump both together when the rule changes. */
  private static final int CURRENT_LABEL_VERSION = 2;

  private ReverseGeocodeService.Point point(double lat, double lng) {
    return new ReverseGeocodeService.Point(lat, lng);
  }

  /** The Server API shape: city and province inside structuredAddress, country at the top. */
  private static AppleMapsGeocodeClient.ApplePlace banff() {
    return new AppleMapsGeocodeClient.ApplePlace(
        "Banff National Park",
        null,
        null,
        null,
        "Canada",
        "CA",
        new AppleMapsGeocodeClient.StructuredAddress(
            "Alberta", "Banff", "Banff Townsite", List.of("Banff National Park"), List.of()));
  }

  @Test
  void resolvesAPointAndRemembersItSoTheSecondAskCostsNothing() {
    when(client.reverseGeocode(anyDouble(), anyDouble(), eq("en")))
        .thenReturn(Optional.of(FRANKFURT));

    List<ReverseGeocodeService.ResolvedPlace> first =
        service.resolve(List.of(point(50.047, 8.574)), "en");
    List<ReverseGeocodeService.ResolvedPlace> second =
        service.resolve(List.of(point(50.047, 8.574)), "en");

    assertEquals("Frankfurt", first.get(0).name());
    assertEquals("Frankfurt", second.get(0).name());
    // Second call came out of the memory layer — the repository was not even consulted again.
    verify(client, times(1)).reverseGeocode(anyDouble(), anyDouble(), anyString());
  }

  @Test
  void collapsesDuplicatePointsInsideOneBatch() {
    when(client.reverseGeocode(anyDouble(), anyDouble(), eq("en")))
        .thenReturn(Optional.of(FRANKFURT));

    List<ReverseGeocodeService.ResolvedPlace> resolved =
        service.resolve(
            List.of(point(50.047, 8.574), point(50.047, 8.574), point(50.04701, 8.57404)), "en");

    assertEquals(3, resolved.size());
    resolved.forEach(place -> assertEquals("Frankfurt", place.name()));
    // Three requested points, one place: the fifth decimal is below the ~11 m snapping grid.
    verify(client, times(1)).reverseGeocode(anyDouble(), anyDouble(), anyString());
  }

  @Test
  void reusesACachedNameFromANeighbouringPointInsteadOfAskingAgain() {
    GeocodeCacheEntry neighbour = new GeocodeCacheEntry();
    neighbour.setLatE4(500470);
    neighbour.setLngE4(85740);
    neighbour.setLanguage("en");
    neighbour.setPlaceName("Frankfurt");
    neighbour.setResolvedAt(Instant.now());
    // Written by the current label rule; an older one would (correctly) be re-resolved instead.
    neighbour.setResolverVersion(CURRENT_LABEL_VERSION);
    when(repository.findByLatE4AndLngE4AndLanguage(anyInt(), anyInt(), anyString()))
        .thenReturn(Optional.empty());
    when(repository.findNearby(
            anyString(), anyInt(), anyInt(), anyInt(), anyInt(), anyInt(), anyInt(), any()))
        .thenReturn(List.of(neighbour));

    // ~150 m away: inside the default 300 m reuse radius.
    List<ReverseGeocodeService.ResolvedPlace> resolved =
        service.resolve(List.of(point(50.0483, 8.574)), "en");

    assertEquals("Frankfurt", resolved.get(0).name());
    verify(client, never()).reverseGeocode(anyDouble(), anyDouble(), anyString());
  }

  @Test
  void answersWithoutANameOnceTheOutboundCeilingIsHit() {
    properties.setMaxLookupsPerMinute(1);
    when(client.reverseGeocode(anyDouble(), anyDouble(), eq("en")))
        .thenReturn(Optional.of(FRANKFURT));

    List<ReverseGeocodeService.ResolvedPlace> resolved =
        service.resolve(List.of(point(50.047, 8.574), point(48.137, 11.575)), "en");

    assertEquals("Frankfurt", resolved.get(0).name());
    // The second point was over the ceiling: no name, no exception, and Apple was asked once.
    assertNull(resolved.get(1).name());
    verify(client, times(1)).reverseGeocode(anyDouble(), anyDouble(), anyString());
  }

  @Test
  void labelsARegionWithItsTownWhenAppleKnowsOne() {
    when(client.reverseGeocode(anyDouble(), anyDouble(), anyString()))
        .thenReturn(Optional.of(banff()));

    assertEquals("Banff", service.resolve(List.of(point(51.1784, -115.5708)), "en").get(0).name());
  }

  @Test
  void labelsAWildernessRegionWithItsNamedAreaRatherThanItsProvince() {
    AppleMapsGeocodeClient.ApplePlace parkway =
        new AppleMapsGeocodeClient.ApplePlace(
            "Icefields Parkway",
            null,
            null,
            null,
            "Canada",
            "CA",
            new AppleMapsGeocodeClient.StructuredAddress(
                "Alberta", null, null, List.of("Jasper National Park"), List.of()));
    when(client.reverseGeocode(anyDouble(), anyDouble(), anyString()))
        .thenReturn(Optional.of(parkway));

    assertEquals(
        "Jasper National Park", service.resolve(List.of(point(52.2, -117.2)), "en").get(0).name());
  }

  @Test
  void aProvinceOnlyAnswerCarriesItsCountrySoItCannotBeMisread() {
    AppleMapsGeocodeClient.ApplePlace remote =
        new AppleMapsGeocodeClient.ApplePlace(
            null,
            null,
            null,
            null,
            "Canada",
            "CA",
            new AppleMapsGeocodeClient.StructuredAddress("Alberta", null, null, null, null));
    when(client.reverseGeocode(anyDouble(), anyDouble(), anyString()))
        .thenReturn(Optional.of(remote));

    assertEquals(
        "Alberta, Canada", service.resolve(List.of(point(54.0, -114.0)), "en").get(0).name());
  }

  @Test
  void aNameFromAnOlderLabelRuleIsResolvedAgainInsteadOfBeingTrusted() {
    // What the first release wrote for every Canadian coordinate: the country, and nothing else.
    GeocodeCacheEntry stale = new GeocodeCacheEntry();
    stale.setLatE4(511784);
    stale.setLngE4(-1155708);
    stale.setLanguage("en");
    stale.setPlaceName("Canada");
    stale.setResolvedAt(Instant.now());
    stale.setResolverVersion(1);
    when(repository.findByLatE4AndLngE4AndLanguage(anyInt(), anyInt(), anyString()))
        .thenReturn(Optional.of(stale));
    when(client.reverseGeocode(anyDouble(), anyDouble(), anyString()))
        .thenReturn(Optional.of(banff()));

    assertEquals("Banff", service.resolve(List.of(point(51.1784, -115.5708)), "en").get(0).name());
    verify(client, times(1)).reverseGeocode(anyDouble(), anyDouble(), anyString());
  }

  @Test
  void aNeighbourCachedByAnOlderRuleIsNotSpreadSideways() {
    GeocodeCacheEntry staleNeighbour = new GeocodeCacheEntry();
    staleNeighbour.setLatE4(511784);
    staleNeighbour.setLngE4(-1155708);
    staleNeighbour.setLanguage("en");
    staleNeighbour.setPlaceName("Canada");
    staleNeighbour.setResolvedAt(Instant.now());
    staleNeighbour.setResolverVersion(1);
    when(repository.findByLatE4AndLngE4AndLanguage(anyInt(), anyInt(), anyString()))
        .thenReturn(Optional.empty());
    when(repository.findNearby(
            anyString(), anyInt(), anyInt(), anyInt(), anyInt(), anyInt(), anyInt(), any()))
        .thenReturn(List.of(staleNeighbour));
    when(client.reverseGeocode(anyDouble(), anyDouble(), anyString()))
        .thenReturn(Optional.of(banff()));

    assertEquals("Banff", service.resolve(List.of(point(51.18, -115.57)), "en").get(0).name());
  }

  @Test
  void unsupportedLanguagesFallBackToTheDefaultRatherThanMultiplyingCacheKeys() {
    when(client.reverseGeocode(anyDouble(), anyDouble(), eq("en")))
        .thenReturn(Optional.of(FRANKFURT));

    service.resolve(List.of(point(50.047, 8.574)), "sv-SE");

    verify(client, times(1)).reverseGeocode(anyDouble(), anyDouble(), eq("en"));
  }

  @Test
  void asksInTheRequestedLanguageWhenItIsOneWeSupport() {
    when(client.reverseGeocode(anyDouble(), anyDouble(), eq("de")))
        .thenReturn(Optional.of(FRANKFURT));

    service.resolve(List.of(point(50.047, 8.574)), "de-DE");

    verify(client, times(1)).reverseGeocode(anyDouble(), anyDouble(), eq("de"));
  }

  @Test
  void geocodingTurnedOffMeansNoNamesAndNoCalls() {
    properties.setEnabled(false);

    List<ReverseGeocodeService.ResolvedPlace> resolved =
        service.resolve(List.of(point(50.047, 8.574)), "en");

    assertNull(resolved.get(0).name());
    verify(client, never()).reverseGeocode(anyDouble(), anyDouble(), anyString());
  }
}
