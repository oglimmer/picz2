/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

/**
 * Pins the shape of the Apple Maps <em>Server</em> API reply.
 *
 * <p>This is the test that was missing the first time round. The Server API nests the city, the
 * district and the state inside {@code structuredAddress}, while MapKit JS puts them at the top
 * level. Modelling the wrong one fails silently — {@code country} still parses — so every region in
 * a country ends up labelled after the country, and nothing in a compile or a mock-based test
 * notices.
 */
class AppleMapsGeocodeResponseTest {

  private final ObjectMapper mapper = new ObjectMapper();

  /**
   * Trimmed from a real /v1/reverseGeocode reply; unknown fields are kept to prove they're ignored.
   */
  private static final String BANFF_JSON =
      """
      {
        "results": [
          {
            "coordinate": { "latitude": 51.1784, "longitude": -115.5708 },
            "country": "Canada",
            "countryCode": "CA",
            "name": "Banff National Park",
            "formattedAddressLines": ["Banff, AB", "Canada"],
            "structuredAddress": {
              "administrativeArea": "Alberta",
              "administrativeAreaCode": "AB",
              "locality": "Banff",
              "subLocality": "Banff Townsite",
              "areasOfInterest": ["Banff National Park"],
              "dependentLocalities": [],
              "postCode": "T1L"
            }
          }
        ]
      }
      """;

  @Test
  void readsTheCityOutOfStructuredAddressRatherThanStoppingAtTheCountry() throws Exception {
    AppleMapsGeocodeClient.ReverseGeocodeResponse response =
        mapper.readValue(BANFF_JSON, AppleMapsGeocodeClient.ReverseGeocodeResponse.class);

    AppleMapsGeocodeClient.ApplePlace place = response.results().get(0);
    assertEquals("Banff", place.cityName());
    assertEquals("Banff Townsite", place.districtName());
    assertEquals("Alberta", place.stateName());
    assertEquals("Canada", place.country());
    assertEquals("Banff National Park", place.areaOfInterestName());
  }

  @Test
  void aCoordinateWithNoTownStillYieldsItsNamedArea() throws Exception {
    String json =
        """
        {
          "results": [
            {
              "country": "Canada",
              "countryCode": "CA",
              "name": "Icefields Parkway",
              "structuredAddress": {
                "administrativeArea": "Alberta",
                "areasOfInterest": ["Jasper National Park"]
              }
            }
          ]
        }
        """;

    AppleMapsGeocodeClient.ApplePlace place =
        mapper
            .readValue(json, AppleMapsGeocodeClient.ReverseGeocodeResponse.class)
            .results()
            .get(0);

    assertNull(place.cityName());
    assertEquals("Jasper National Park", place.areaOfInterestName());
    assertEquals("Alberta", place.stateName());
  }

  @Test
  void theFlatMapKitShapeStillParsesIfAppleEverSendsIt() throws Exception {
    String json =
        """
        {"results": [{"locality": "Frankfurt", "administrativeArea": "Hesse", "country": "Germany"}]}
        """;

    AppleMapsGeocodeClient.ApplePlace place =
        mapper
            .readValue(json, AppleMapsGeocodeClient.ReverseGeocodeResponse.class)
            .results()
            .get(0);

    assertEquals("Frankfurt", place.cityName());
    assertEquals("Hesse", place.stateName());
  }

  @Test
  void emptyResultsAreNotAnError() throws Exception {
    AppleMapsGeocodeClient.ReverseGeocodeResponse response =
        mapper.readValue(
            """
            {"results": []}
            """,
            AppleMapsGeocodeClient.ReverseGeocodeResponse.class);

    assertEquals(0, response.results().size());
  }
}
