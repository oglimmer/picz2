/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

import com.oglimmer.photoupload.entity.SessionToken;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.repository.SessionTokenRepository;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * D78 — browser session tokens. The properties that matter are the same as for upload tokens: the
 * plaintext is never stored, an expired or unknown token does not resolve, and the two token kinds
 * can never be mistaken for each other.
 */
@ExtendWith(MockitoExtension.class)
class SessionTokenServiceTest {

  @Mock SessionTokenRepository repository;

  SessionTokenService service;
  User user;

  @BeforeEach
  void setUp() {
    service = new SessionTokenService(repository);
    ReflectionTestUtils.setField(service, "ttlDays", 30);
    user = new User();
    user.setId(7L);
    user.setEmail("someone@example.com");
  }

  private SessionToken savedToken() {
    ArgumentCaptor<SessionToken> captor = ArgumentCaptor.forClass(SessionToken.class);
    verify(repository).save(captor.capture());
    return captor.getValue();
  }

  @Test
  void theStoredRowNeverContainsThePlaintext() {
    SessionTokenService.IssuedToken issued = service.issue(user);
    SessionToken saved = savedToken();
    assertTrue(issued.token().startsWith(SessionTokenService.TOKEN_PREFIX));
    assertFalse(saved.getTokenHash().contains(issued.token()));
    assertTrue(saved.getTokenHash().matches("[0-9a-f]{64}"));
    verify(repository).deleteExpired(any(Instant.class));
  }

  @Test
  void aLiveTokenResolvesToItsOwnerAndAnExpiredOneDoesNot() {
    SessionTokenService.IssuedToken issued = service.issue(user);
    SessionToken stored = savedToken();
    when(repository.findByTokenHash(stored.getTokenHash())).thenReturn(Optional.of(stored));

    assertEquals(Optional.of(user), service.resolve(issued.token()));

    stored.setExpiresAt(Instant.now().minus(1, ChronoUnit.MINUTES));
    assertTrue(service.resolve(issued.token()).isEmpty());
  }

  @Test
  void unknownAndForeignValuesDoNotResolve() {
    when(repository.findByTokenHash(anyString())).thenReturn(Optional.empty());
    assertTrue(service.resolve(SessionTokenService.TOKEN_PREFIX + "nonsense").isEmpty());
    // An upload token, a Basic value or garbage must not even reach the database.
    assertTrue(service.resolve(UploadTokenService.TOKEN_PREFIX + "abc").isEmpty());
    assertTrue(service.resolve("someone@example.com:hunter2").isEmpty());
    assertTrue(service.resolve(null).isEmpty());
    verify(repository, times(1)).findByTokenHash(anyString());
  }

  @Test
  void revokeDeletesByHashAndIgnoresForeignValues() {
    SessionTokenService.IssuedToken issued = service.issue(user);
    SessionToken stored = savedToken();

    service.revoke(issued.token());
    verify(repository).deleteByTokenHash(stored.getTokenHash());

    service.revoke("Basic nonsense");
    verify(repository, times(1)).deleteByTokenHash(anyString());
  }

  @Test
  void revokeAllForDeletesEverySessionOfTheAccount() {
    when(repository.deleteByUserId(7L)).thenReturn(3);
    assertEquals(3, service.revokeAllFor(7L));
  }
}
