/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import com.oglimmer.photoupload.security.CustomUserDetailsService;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.config.annotation.authentication.builders.AuthenticationManagerBuilder;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.SecurityFilterChain;

@Profile(Profiles.API)
@Configuration
@EnableWebSecurity
@RequiredArgsConstructor
public class SecurityConfig {

  private final CustomUserDetailsService userDetailsService;

  @Bean
  public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http.cors(cors -> cors.configure(http))
        .csrf(AbstractHttpConfigurer::disable)
        .authorizeHttpRequests(
            auth ->
                auth.requestMatchers(HttpMethod.GET, "/api/i/**")
                    .permitAll()
                    .requestMatchers(HttpMethod.GET, "/api/r/**")
                    .permitAll()
                    .requestMatchers(HttpMethod.GET, "/api/albums/public/**")
                    .permitAll()
                    .requestMatchers(HttpMethod.POST, "/api/albums/public/*/analytics/**")
                    .permitAll()
                    .requestMatchers("/api/public/subscriptions/**")
                    .permitAll()
                    .requestMatchers(HttpMethod.GET, "/api/albums/*/recordings")
                    .permitAll()
                    .requestMatchers(HttpMethod.GET, "/api/settings/languages")
                    .permitAll()
                    .requestMatchers(HttpMethod.POST, "/api/users")
                    .permitAll()
                    .requestMatchers(HttpMethod.GET, "/api/users/verify-email")
                    .permitAll()
                    .requestMatchers(HttpMethod.POST, "/api/users/password-reset-request")
                    .permitAll()
                    .requestMatchers(HttpMethod.POST, "/api/users/password-reset")
                    .permitAll()
                    .requestMatchers(HttpMethod.GET, "/api/version")
                    .permitAll()
                    .requestMatchers(HttpMethod.GET, "/api/capabilities")
                    .permitAll()
                    // Public share links show the map too, so their visitors need a MapKit token.
                    .requestMatchers(HttpMethod.GET, "/api/maps/token")
                    .permitAll()
                    // tusd→api hook callbacks. The path-secret in the URL is the auth boundary
                    // (validated constant-time inside TusHookController); Spring Security just
                    // needs to let the request through. Cluster-internal only — never on Ingress.
                    .requestMatchers(HttpMethod.POST, "/api/tus/hooks/**")
                    .permitAll()
                    .requestMatchers(HttpMethod.GET, "/public/album/**")
                    .permitAll()
                    .requestMatchers(HttpMethod.GET, "/api/public/subscription/**")
                    .permitAll()
                    .requestMatchers("/", "/actuator/health/**", "/actuator/info")
                    .permitAll()
                    .requestMatchers("/v3/api-docs/**", "/swagger-ui/**", "/swagger-ui.html")
                    .permitAll()
                    .anyRequest()
                    .authenticated())
        .httpBasic(basic -> basic.authenticationEntryPoint(silentBasicEntryPoint()));

    return http.build();
  }

  /**
   * Answers unauthenticated requests with a 401 the browser will not act on.
   *
   * <p>Spring's default entry point sends {@code WWW-Authenticate: Basic realm="PhotoUpload"},
   * which is a standing instruction to the browser to prompt for credentials — and Chrome obeys it
   * even for {@code fetch()} calls made by page JavaScript. This SPA builds its own Basic header
   * from localStorage (see {@code useAuth.verifyCredentials}), so the native dialog is pure
   * interference: a visitor whose saved password had gone stale got a credentials prompt on a
   * <em>public</em> share link, over a background request they never asked for, and the app did not
   * mount until they dismissed it.
   *
   * <p>The scheme name is deliberately misspelt rather than dropped: RFC 7235 requires a challenge
   * on a 401, and no browser recognises {@code xBasic}, so the header stays present and inert.
   * Every client we ship sends its credentials up front and reads the status code, so none of them
   * depended on being challenged.
   */
  // Package-private so SecurityConfigTest can assert the challenge directly, without standing up a
  // servlet context just to read one header.
  AuthenticationEntryPoint silentBasicEntryPoint() {
    return (request, response, authException) -> {
      response.setHeader(HttpHeaders.WWW_AUTHENTICATE, "xBasic realm=\"PhotoUpload\"");
      response.sendError(HttpStatus.UNAUTHORIZED.value(), "Unauthorized");
    };
  }

  @Bean
  public PasswordEncoder passwordEncoder() {
    // Use BCrypt for secure password hashing
    return new BCryptPasswordEncoder();
  }

  @Bean
  public AuthenticationManager authenticationManager(HttpSecurity http) throws Exception {
    AuthenticationManagerBuilder authenticationManagerBuilder =
        http.getSharedObject(AuthenticationManagerBuilder.class);
    authenticationManagerBuilder
        .userDetailsService(userDetailsService)
        .passwordEncoder(passwordEncoder());
    return authenticationManagerBuilder.build();
  }
}
