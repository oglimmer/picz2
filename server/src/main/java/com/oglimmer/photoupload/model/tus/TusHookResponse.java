/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model.tus;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.Map;

/**
 * Phase 5 — tusd v2 HTTP hook response envelope. tusd JSON-decodes our HTTP 200 body into this
 * shape; the {@code HTTPResponse.StatusCode} inside is what tusd actually surfaces to the
 * client. Returning a non-2xx HTTP status from the controller (or an empty body) makes tusd log
 * "failed to parse hook response" and propagate 500 to the client — that was the R1-deploy bug.
 *
 * <p>Field names are PascalCase per tusd's Go convention, mapped via {@link JsonProperty}. Null
 * fields are omitted ({@link JsonInclude.Include#NON_NULL}) so {@link #allow()} renders as
 * {@code {"RejectUpload":false}} rather than carrying a useless empty {@code HTTPResponse}.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record TusHookResponse(
    @JsonProperty("HTTPResponse") HttpResponse httpResponse,
    @JsonProperty("RejectUpload") boolean rejectUpload,
    @JsonProperty("StopUpload") boolean stopUpload) {

  /** Allow the request to proceed. tusd uses its default 200 (or 201 for pre-create). */
  public static TusHookResponse allow() {
    return new TusHookResponse(null, false, false);
  }

  /**
   * Reject with a specific HTTP status. tusd surfaces {@code statusCode} + {@code body} +
   * {@code header} verbatim to the client. Used for 401/409/503.
   */
  public static TusHookResponse reject(int statusCode, String body, Map<String, String> header) {
    return new TusHookResponse(
        new HttpResponse(statusCode, body, header == null ? Map.of() : header), true, false);
  }

  public static TusHookResponse reject(int statusCode, String body) {
    return reject(statusCode, body, Map.of());
  }

  @JsonInclude(JsonInclude.Include.NON_NULL)
  public record HttpResponse(
      @JsonProperty("StatusCode") int statusCode,
      @JsonProperty("Body") String body,
      @JsonProperty("Header") Map<String, String> header) {}
}
