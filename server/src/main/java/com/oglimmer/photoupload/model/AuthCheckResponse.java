/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
public class AuthCheckResponse {

  private boolean success;
  private String email;
  private boolean emailVerified;

  /**
   * Whether this account holds {@code ROLE_ADMIN} (D74). Lets a client hide operator-only controls
   * — the gallery language names, for one — instead of showing a field that answers 403.
   */
  private boolean admin;
}
