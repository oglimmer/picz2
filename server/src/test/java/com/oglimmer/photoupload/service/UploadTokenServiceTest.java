/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

import com.oglimmer.photoupload.entity.UploadToken;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.repository.UploadTokenRepository;
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
 * §5.9 — scoped upload tokens.
 *
 * <p>The properties worth pinning are the security ones: the plaintext is never persisted, an
 * expired token is refused, and a legacy {@code email:password} value is never mistaken for a token
 * (or the transition would turn every old client into an unauthenticated one).
 */
@ExtendWith(MockitoExtension.class)
class UploadTokenServiceTest {

  @Mock UploadTokenRepository uploadTokenRepository;

  UploadTokenService service;
  User user;

  @BeforeEach
  void setUp() {
    service = new UploadTokenService(uploadTokenRepository);
    ReflectionTestUtils.setField(service, "ttlHours", 24);
    user = new User();
    user.setId(7L);
    user.setEmail("someone@example.com");
  }

  private UploadToken capturedSavedToken() {
    ArgumentCaptor<UploadToken> captor = ArgumentCaptor.forClass(UploadToken.class);
    verify(uploadTokenRepository).save(captor.capture());
    return captor.getValue();
  }

  @Test
  void theStoredRowNeverContainsThePlaintextToken() {
    UploadTokenService.IssuedToken issued = service.issue(user);

    UploadToken saved = capturedSavedToken();
    assertNotEquals(issued.token(), saved.getTokenHash());
    assertFalse(saved.getTokenHash().contains(issued.token()));
    // Hex SHA-256, so a dump of this table replays nothing.
    assertEquals(64, saved.getTokenHash().length());
    assertTrue(saved.getTokenHash().matches("[0-9a-f]{64}"));
  }

  @Test
  void issuedTokensCarryThePrefixAndAreUnique() {
    String first = service.issue(user).token();
    String second = service.issue(user).token();

    assertTrue(first.startsWith(UploadTokenService.TOKEN_PREFIX));
    assertNotEquals(first, second);
  }

  @Test
  void issuingSweepsExpiredRows() {
    service.issue(user);
    verify(uploadTokenRepository).deleteExpired(any(Instant.class));
  }

  @Test
  void aLiveTokenResolvesToItsOwner() {
    UploadTokenService.IssuedToken issued = service.issue(user);
    UploadToken stored = capturedSavedToken();
    when(uploadTokenRepository.findByTokenHash(stored.getTokenHash()))
        .thenReturn(Optional.of(stored));

    assertEquals(Optional.of(user), service.resolve(issued.token()));
  }

  @Test
  void anExpiredTokenDoesNotResolve() {
    UploadTokenService.IssuedToken issued = service.issue(user);
    UploadToken stored = capturedSavedToken();
    stored.setExpiresAt(Instant.now().minus(1, ChronoUnit.MINUTES));
    when(uploadTokenRepository.findByTokenHash(stored.getTokenHash()))
        .thenReturn(Optional.of(stored));

    assertTrue(service.resolve(issued.token()).isEmpty());
  }

  @Test
  void anUnknownTokenDoesNotResolve() {
    when(uploadTokenRepository.findByTokenHash(anyString())).thenReturn(Optional.empty());
    assertTrue(service.resolve(UploadTokenService.TOKEN_PREFIX + "nonsense").isEmpty());
  }

  /**
   * The transition guard. An old client sends {@code email:password}; if that were routed to the
   * token path it would fail to resolve and the upload would be rejected, breaking every app that
   * has not been updated.
   */
  @Test
  void legacyCredentialsAreNotMistakenForAToken() {
    assertFalse(UploadTokenService.looksLikeToken("someone@example.com:hunter2"));
    assertFalse(UploadTokenService.looksLikeToken(null));
    assertFalse(UploadTokenService.looksLikeToken(""));
    assertTrue(UploadTokenService.looksLikeToken(UploadTokenService.TOKEN_PREFIX + "abc"));
  }

  /** A non-token value must not even reach the database. */
  @Test
  void resolvingANonTokenNeverQueries() {
    assertTrue(service.resolve("someone@example.com:hunter2").isEmpty());
    verify(uploadTokenRepository, never()).findByTokenHash(anyString());
  }

  @Test
  void revokingRemovesEveryTokenForTheUser() {
    when(uploadTokenRepository.deleteByUserId(7L)).thenReturn(3);
    assertEquals(3, service.revokeAllFor(7L));
  }
}
