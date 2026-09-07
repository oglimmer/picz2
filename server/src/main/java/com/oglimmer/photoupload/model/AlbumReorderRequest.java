/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.util.List;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * The body of {@code PUT /api/albums/reorder}: the caller's albums in the order they should be
 * listed in. Deliberately separate from {@link ReorderRequest}, which carries file ids — the two
 * live at different endpoints and a shared field name would let a client post one to the other.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class AlbumReorderRequest {

  private List<Long> albumIds;
}
