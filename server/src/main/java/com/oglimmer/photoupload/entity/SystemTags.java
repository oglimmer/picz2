/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.entity;

import java.util.Set;

/**
 * The per-user tags the application creates and relies on, as opposed to the ones a user types.
 *
 * <p>They live here rather than on a service because {@link User} needs {@link #HIDDEN} for its
 * column default, and an entity must not reach into the service layer.
 *
 * <p>Both are protected from rename and delete ({@code TagService}) and are implicitly enabled on
 * every album ({@code AlbumTagService}), so an upload can never be refused the tag it needs. They
 * differ in one thing only: {@link #HIDDEN} is stripped from everything a public visitor can see,
 * {@link #ALL} is not.
 */
public final class SystemTags {

  /**
   * Attached to every new asset since D68, and the tag public visitors filter on to mean "the whole
   * album".
   */
  public static final String ALL = "all";

  /**
   * The holding pen (D70). An asset carrying this tag is filtered out of the public album listing,
   * out of the public single-image page and out of subscription notifications, whatever else it is
   * tagged with. The owner sees it normally in their own gallery — that is the point, they are
   * meant to review it and re-tag it.
   *
   * <p>Since D79 it is derived, not assigned: a file carries {@code hidden} exactly while it has no
   * other tag. Giving a file any real tag takes {@code hidden} off in the same transaction; taking
   * the last real tag off (or deleting that tag) puts it back. {@code FileStorageService} and
   * {@code TagService} enforce this on every tag edit; nothing rewrites older rows.
   */
  public static final String HIDDEN = "hidden";

  /** The two names a user may choose between for {@code User.newAssetTag}. */
  public static final Set<String> NEW_ASSET_CHOICES = Set.of(HIDDEN, ALL);

  private static final Set<String> ALL_NAMES = Set.of(ALL, HIDDEN);

  /** True for a reserved name: it cannot be created, renamed or deleted by hand. */
  public static boolean isSystemTag(String name) {
    return ALL_NAMES.contains(name);
  }

  private SystemTags() {}
}
