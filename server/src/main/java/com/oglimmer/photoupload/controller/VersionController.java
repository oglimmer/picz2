/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.model.ApiResponse;
import com.oglimmer.photoupload.model.VersionInfo;
import org.springframework.boot.info.BuildProperties;
import org.springframework.boot.info.GitProperties;
import org.springframework.lang.Nullable;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/version")
public class VersionController {

  private final BuildProperties buildProperties;
  private final GitProperties gitProperties; // may be null if git.properties not present

  public VersionController(
      @Nullable BuildProperties buildProperties, @Nullable GitProperties gitProperties) {
    this.buildProperties = buildProperties;
    this.gitProperties = gitProperties;
  }

  @GetMapping
  public ApiResponse<VersionInfo> getVersion() {
    String version = buildProperties != null ? buildProperties.getVersion() : "unknown";
    String time =
        buildProperties != null && buildProperties.getTime() != null
            ? buildProperties.getTime().toString()
            : "";

    String commit = "unknown";
    String branch = "";
    if (gitProperties != null) {
      try {
        String id = gitProperties.getShortCommitId();
        if (id == null || id.isBlank()) {
          id = gitProperties.getCommitId();
        }
        if (id != null && !id.isBlank()) {
          commit = id;
        }
      } catch (Exception ignored) {
      }
      try {
        String b = gitProperties.getBranch();
        if (b != null) {
          branch = b;
        }
      } catch (Exception ignored) {
      }
    }

    return ApiResponse.success(new VersionInfo(version, commit, branch, time));
  }
}
