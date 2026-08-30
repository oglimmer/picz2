/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.time.Instant;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class AlbumInfo {

  private Long id;
  private String name;
  private String description;
  private Instant createdAt;
  private Instant updatedAt;
  private Integer displayOrder;
  private Integer fileCount;
  private String coverImageFilename; // Filename of cover image (first photo in album)
  private String coverImageToken; // Public token of cover image
  private String shareToken; // Public share token for accessing album

  // Whether the share link is live. Owner-facing only: the public share-token response never
  // carries it, because an unpublished album never produces a response at all.
  private Boolean published;
  private Instant publishedAt;

  // Saved view for the map filter (D35): MapKit's CoordinateRegion, centre + span in degrees.
  // Null — all four together — means no saved view, and the map frames every pin instead. Flat
  // fields rather than a nested object so MapStruct maps them from the entity by name.
  private Double mapCenterLat;
  private Double mapCenterLng;
  private Double mapSpanLat;
  private Double mapSpanLng;

  // Where this album's bytes live. Read-only after creation — the API rejects a change rather
  // than silently leaving half the objects on the old backend.
  private Long storageBackendId;
  private String storageBackendName;
}
