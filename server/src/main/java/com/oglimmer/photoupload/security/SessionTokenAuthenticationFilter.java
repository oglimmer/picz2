/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.security;

import com.oglimmer.photoupload.service.SessionTokenService;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpHeaders;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Turns {@code Authorization: Bearer zst_…} into an authenticated principal (D78).
 *
 * <p>Runs ahead of Spring's Basic filter. A request carrying anything other than one of our session
 * tokens passes straight through untouched, so Basic (iOS, curl) keeps working exactly as before.
 * An unknown or expired token is likewise left alone rather than answered here: the request then
 * reaches the authorisation layer unauthenticated and gets the same silent 401 as a missing header,
 * which is what tells the browser to drop the token and show the login page.
 *
 * <p>Authorities come from {@link CustomUserDetailsService} so {@code ROLE_ADMIN} (D74) means the
 * same thing whichever way a user authenticated.
 */
@RequiredArgsConstructor
public class SessionTokenAuthenticationFilter extends OncePerRequestFilter {

  private static final String BEARER = "Bearer ";

  private final SessionTokenService sessionTokenService;
  private final CustomUserDetailsService userDetailsService;

  /** The session token in this request's Authorization header, or null when it carries none. */
  public static String bearerToken(HttpServletRequest request) {
    String header = request.getHeader(HttpHeaders.AUTHORIZATION);
    if (header == null || !header.regionMatches(true, 0, BEARER, 0, BEARER.length())) {
      return null;
    }
    String token = header.substring(BEARER.length()).trim();
    return SessionTokenService.looksLikeToken(token) ? token : null;
  }

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain chain)
      throws ServletException, IOException {
    String token = bearerToken(request);
    if (token != null && SecurityContextHolder.getContext().getAuthentication() == null) {
      sessionTokenService
          .resolve(token)
          .ifPresent(
              user -> {
                UserDetails details = userDetailsService.loadUserByUsername(user.getEmail());
                UsernamePasswordAuthenticationToken authentication =
                    new UsernamePasswordAuthenticationToken(
                        details, null, details.getAuthorities());
                SecurityContextHolder.getContext().setAuthentication(authentication);
              });
    }
    chain.doFilter(request, response);
  }
}
