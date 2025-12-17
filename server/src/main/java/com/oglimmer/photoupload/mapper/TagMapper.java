/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.mapper;

import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.model.TagInfo;
import java.util.List;
import org.mapstruct.Mapper;

@Mapper(componentModel = "spring")
public interface TagMapper {

  TagInfo tagToTagInfo(Tag tag);

  List<TagInfo> tagsToTagInfos(List<Tag> tags);
}
