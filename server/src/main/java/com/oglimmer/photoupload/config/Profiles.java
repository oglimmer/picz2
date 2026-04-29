/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

/**
 * Spring profile name constants. Use these in {@code @Profile(Profiles.API)} /
 * {@code @Profile(Profiles.WORKER)} so renames are caught by the compiler and the deployment
 * boundary stays grep-able.
 */
public final class Profiles {

  public static final String API = "api";
  public static final String WORKER = "worker";

  private Profiles() {}
}
