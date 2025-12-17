/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.mapper;

import com.oglimmer.photoupload.entity.SlideshowRecording;
import com.oglimmer.photoupload.model.RecordingInfo;
import java.util.List;
import java.util.stream.Collectors;
import org.mapstruct.AfterMapping;
import org.mapstruct.Mapper;
import org.mapstruct.MappingTarget;

@Mapper(componentModel = "spring")
public interface RecordingInfoMapper {

  @org.mapstruct.Mapping(target = "images", ignore = true) // Set in @AfterMapping
  @org.mapstruct.Mapping(target = "albumId", ignore = true) // Set in @AfterMapping
  RecordingInfo recordingToRecordingInfo(SlideshowRecording recording);

  List<RecordingInfo> recordingsToRecordingInfos(List<SlideshowRecording> recordings);

  @AfterMapping
  default void afterMapping(
      SlideshowRecording recording, @MappingTarget RecordingInfo recordingInfo) {
    // Map nested recording images to RecordingImageInfo objects
    List<RecordingInfo.RecordingImageInfo> imageInfos =
        recording.getImages().stream()
            .map(
                img -> {
                  RecordingInfo.RecordingImageInfo imageInfo =
                      new RecordingInfo.RecordingImageInfo();
                  imageInfo.setFileId(img.getFile().getId());
                  imageInfo.setStartTimeMs(img.getStartTimeMs());
                  imageInfo.setDurationMs(img.getDurationMs());
                  imageInfo.setSequenceOrder(img.getSequenceOrder());
                  return imageInfo;
                })
            .collect(Collectors.toList());
    recordingInfo.setImages(imageInfos);

    // Map album ID
    if (recording.getAlbum() != null) {
      recordingInfo.setAlbumId(recording.getAlbum().getId());
    }
  }
}
