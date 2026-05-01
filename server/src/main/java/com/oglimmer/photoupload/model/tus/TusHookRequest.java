/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model.tus;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.List;
import java.util.Map;

/**
 * tusd v2 HTTP hook payload. Field names are PascalCase on the wire (tusd convention) so we map
 * via {@link JsonProperty} and let Java keep its camelCase. {@link JsonIgnoreProperties} keeps us
 * forward-compatible with new fields tusd may add (e.g. {@code Storage}, {@code IsFinal}).
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record TusHookRequest(
    @JsonProperty("Type") String type,
    @JsonProperty("Event") TusEvent event) {

  @JsonIgnoreProperties(ignoreUnknown = true)
  public record TusEvent(
      @JsonProperty("Upload") TusUpload upload,
      @JsonProperty("HTTPRequest") TusHttpRequest httpRequest) {}

  @JsonIgnoreProperties(ignoreUnknown = true)
  public record TusUpload(
      @JsonProperty("ID") String id,
      @JsonProperty("Size") long size,
      @JsonProperty("Offset") long offset,
      @JsonProperty("MetaData") Map<String, String> metaData,
      // Storage carries the authoritative S3 location of the upload: keys "Type" (e.g. "s3store"),
      // "Bucket", and "Key". The "Key" is what we COPY/DELETE in post-finish — must NOT be
      // reconstructed from {prefix + Upload.ID} because the S3 store's Upload.ID is
      // "<objectName>+<multipartUploadId>", a synthetic identifier whose first component is the
      // S3 object key. Reading Storage.Key avoids the parse-and-pray.
      @JsonProperty("Storage") Map<String, String> storage) {}

  @JsonIgnoreProperties(ignoreUnknown = true)
  public record TusHttpRequest(
      @JsonProperty("Method") String method,
      @JsonProperty("URI") String uri,
      @JsonProperty("RemoteAddr") String remoteAddr,
      @JsonProperty("Header") Map<String, List<String>> header) {}
}
