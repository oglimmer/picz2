/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.mapper;

import com.oglimmer.photoupload.entity.PresentationGroup;
import com.oglimmer.photoupload.model.PresentationGroupInfo;
import java.util.List;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;

@Mapper(componentModel = "spring")
public interface PresentationGroupMapper {

  @Mapping(target = "albumId", source = "album.id")
  @Mapping(target = "tag", source = "tag.name")
  @Mapping(target = "startFileId", source = "startFile.id")
  @Mapping(target = "text", source = "bodyText")
  PresentationGroupInfo groupToGroupInfo(PresentationGroup group);

  List<PresentationGroupInfo> groupsToGroupInfos(List<PresentationGroup> groups);
}
