/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.entity;

public enum ProcessingStatus {
  INGESTED,
  QUEUED,
  PROCESSING,
  DONE,
  FAILED,
  DEAD_LETTER
}
