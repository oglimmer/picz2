/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.mapper;

import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.model.FileInfo;
import java.util.List;
import java.util.stream.Collectors;
import org.mapstruct.AfterMapping;
import org.mapstruct.Mapper;
import org.mapstruct.MappingTarget;

@Mapper(componentModel = "spring")
public interface FileInfoMapper {

  @org.mapstruct.Mapping(source = "mimeType", target = "mimetype")
  @org.mapstruct.Mapping(source = "fileSize", target = "size")
  @org.mapstruct.Mapping(source = "storedFilename", target = "filename")
  @org.mapstruct.Mapping(source = "filePath", target = "path")
  @org.mapstruct.Mapping(target = "tags", ignore = true) // Set in @AfterMapping
  @org.mapstruct.Mapping(target = "albumId", ignore = true) // Set in @AfterMapping
  @org.mapstruct.Mapping(target = "albumName", ignore = true) // Set in @AfterMapping
  FileInfo fileMetadataToFileInfo(FileMetadata metadata);

  List<FileInfo> fileMetadatasToFileInfos(List<FileMetadata> metadatas);

  @AfterMapping
  default void afterMapping(FileMetadata metadata, @MappingTarget FileInfo fileInfo) {
    // Map tags if imageTag relationships are loaded (for optimized queries with JOIN FETCH)
    if (metadata.getImageTags() != null && !metadata.getImageTags().isEmpty()) {
      List<String> tags =
          metadata.getImageTags().stream()
              .map(imageTag -> imageTag.getTag().getName())
              .collect(Collectors.toList());
      fileInfo.setTags(tags);
    }

    // Map album info
    if (metadata.getAlbum() != null) {
      fileInfo.setAlbumId(metadata.getAlbum().getId());
      fileInfo.setAlbumName(metadata.getAlbum().getName());
    }
  }
}
