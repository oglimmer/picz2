/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.mapper;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.model.AlbumInfo;
import java.util.List;
import org.mapstruct.Mapper;

@Mapper(componentModel = "spring")
public interface AlbumMapper {

  @org.mapstruct.Mapping(target = "fileCount", ignore = true) // Computed field, not in entity
  @org.mapstruct.Mapping(
      target = "coverImageFilename",
      ignore = true) // Computed field, not in entity
  @org.mapstruct.Mapping(target = "coverImageToken", ignore = true) // Computed field, not in entity
  AlbumInfo albumToAlbumInfo(Album album);

  List<AlbumInfo> albumsToAlbumInfos(List<Album> albums);
}
