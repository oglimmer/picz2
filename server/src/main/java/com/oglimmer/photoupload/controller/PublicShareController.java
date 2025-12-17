/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.model.AlbumInfo;
import com.oglimmer.photoupload.model.FileInfo;
import com.oglimmer.photoupload.service.AlbumService;
import com.oglimmer.photoupload.service.FileStorageService;
import jakarta.servlet.http.HttpServletResponse;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;

/**
 * Controller for serving public share pages with Open Graph and Twitter Card meta tags. These pages
 * are specifically designed for social media sharing and crawlers.
 *
 * <p>The HTML pages contain meta tags that social media bots can read, plus JavaScript that
 * redirects regular users to the Vue SPA. This approach works because bots don't execute
 * JavaScript.
 */
@Controller
@RequiredArgsConstructor
public class PublicShareController {

  private final AlbumService albumService;
  private final FileStorageService fileStorageService;

  @Value("${app.base-url:http://localhost}")
  private String baseUrl;

  /**
   * Serves an HTML page with Open Graph and Twitter Card meta tags for shared albums. This allows
   * social media platforms to display rich previews when the link is shared.
   *
   * @param shareToken The share token for the album
   * @param model The Spring MVC model
   * @return The Thymeleaf template name
   */
  @GetMapping("/public/album/{shareToken}")
  public String getPublicAlbum(
      @PathVariable String shareToken, Model model, HttpServletResponse response) {
    // Add cache control headers (allow caching but revalidate)
    response.setHeader("Cache-Control", "public, max-age=3600, must-revalidate");

    // Get album information
    AlbumInfo album = albumService.getAlbumByShareToken(shareToken);

    // Get album files to find a cover image
    List<FileInfo> files = fileStorageService.listFilesByAlbumByShareToken(shareToken);

    // Prepare data for the template
    model.addAttribute("album", album);
    model.addAttribute("shareToken", shareToken);
    model.addAttribute("baseUrl", baseUrl);

    // Find the first image to use as the OG image
    FileInfo coverImage =
        files.stream()
            .filter(file -> file.getMimetype() != null && file.getMimetype().startsWith("image/"))
            .findFirst()
            .orElse(null);

    if (coverImage != null) {
      model.addAttribute(
          "coverImageUrl", baseUrl + "/api/i/" + coverImage.getPublicToken() + "?size=large");
      model.addAttribute("coverImageToken", coverImage.getPublicToken());
      model.addAttribute("coverImageType", coverImage.getMimetype());
    }

    model.addAttribute("fileCount", files.size());

    // Calculate description
    String description = album.getName();
    if (files.size() > 0) {
      description += " - " + files.size() + " photo" + (files.size() != 1 ? "s" : "");
    }
    model.addAttribute("description", description);

    return "public-album";
  }

  /**
   * Serves an HTML page with Open Graph and Twitter Card meta tags for a specific image in a shared
   * album.
   *
   * @param shareToken The share token for the album
   * @param imageToken The public token for the specific image
   * @param model The Spring MVC model
   * @return The Thymeleaf template name
   */
  @GetMapping("/public/album/{shareToken}/{imageToken}")
  public String getPublicImage(
      @PathVariable String shareToken,
      @PathVariable String imageToken,
      Model model,
      HttpServletResponse response) {
    // Add cache control headers (allow caching but revalidate)
    response.setHeader("Cache-Control", "public, max-age=3600, must-revalidate");

    // Get album information
    AlbumInfo album = albumService.getAlbumByShareToken(shareToken);

    // Get the specific file
    FileInfo file = fileStorageService.getFileInfoByPublicToken(imageToken);

    // Prepare data for the template
    model.addAttribute("album", album);
    model.addAttribute("shareToken", shareToken);
    model.addAttribute("imageToken", imageToken);
    model.addAttribute("baseUrl", baseUrl);

    // Use the specific image as the OG image
    model.addAttribute("coverImageUrl", baseUrl + "/api/i/" + imageToken + "?size=large");
    model.addAttribute("coverImageToken", imageToken);
    model.addAttribute("coverImageType", file.getMimetype());

    // Description for specific image
    String description = file.getOriginalName() != null ? file.getOriginalName() : "Photo";
    description += " from " + album.getName();
    model.addAttribute("description", description);

    return "public-image";
  }
}
