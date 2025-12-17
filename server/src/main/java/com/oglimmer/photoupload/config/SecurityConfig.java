/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import com.oglimmer.photoupload.security.CustomUserDetailsService;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.config.annotation.authentication.builders.AuthenticationManagerBuilder;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;

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
        .httpBasic(basic -> basic.realmName("PhotoUpload"));

    return http.build();
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
