/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.DuplicateResourceException;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.repository.UserRepository;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Slf4j
@RequiredArgsConstructor
public class UserService {

  private static final Pattern EMAIL_PATTERN = Pattern.compile("^[^@\n\r]+@[^@\n\r]+\\.[^@\n\r]+$");
  private static final SecureRandom RANDOM = new SecureRandom();
  private final UserRepository userRepository;
  private final PasswordEncoder passwordEncoder;
  private final EmailService emailService;

  @Transactional
  public User createUser(String email, String password) {
    validateEmail(email);
    validatePassword(password);

    userRepository
        .findByEmail(email)
        .ifPresent(
            u -> {
              throw new DuplicateResourceException("User", "email", email);
            });

    User user = new User();
    user.setEmail(email.trim().toLowerCase());
    user.setPassword(passwordEncoder.encode(password));
    user.setEmailVerified(false);

    // Generate verification token
    String token = generateVerificationToken();
    user.setVerificationToken(token);
    user.setVerificationTokenExpiry(Instant.now().plus(24, ChronoUnit.HOURS));

    User saved = userRepository.save(user);
    log.info("Created user: {} (id={})", saved.getEmail(), saved.getId());

    // Send verification email
    try {
      emailService.sendVerificationEmail(saved.getEmail(), token);
    } catch (Exception e) {
      log.error("Failed to send verification email to {}", saved.getEmail(), e);
      // Don't fail user creation if email fails
    }

    return saved;
  }

  @Transactional
  public void verifyEmail(String token) {
    User user =
        userRepository
            .findByVerificationToken(token)
            .orElseThrow(() -> new ValidationException("Invalid or expired verification token"));

    if (user.isEmailVerified()) {
      log.info("User {} already verified", user.getEmail());
      return;
    }

    if (user.getVerificationTokenExpiry() == null
        || user.getVerificationTokenExpiry().isBefore(Instant.now())) {
      throw new ValidationException("Verification token has expired");
    }

    user.setEmailVerified(true);
    user.setVerificationToken(null);
    user.setVerificationTokenExpiry(null);

    userRepository.save(user);
    log.info("User {} verified successfully", user.getEmail());

    // Send welcome email
    try {
      emailService.sendWelcomeEmail(user.getEmail());
    } catch (Exception e) {
      log.error("Failed to send welcome email to {}", user.getEmail(), e);
    }
  }

  @Transactional
  public void resendVerificationEmail(String email) {
    User user =
        userRepository
            .findByEmail(email.trim().toLowerCase())
            .orElseThrow(() -> new ValidationException("User not found"));

    if (user.isEmailVerified()) {
      throw new ValidationException("Email is already verified");
    }

    // Generate new verification token
    String token = generateVerificationToken();
    user.setVerificationToken(token);
    user.setVerificationTokenExpiry(Instant.now().plus(24, ChronoUnit.HOURS));

    userRepository.save(user);
    log.info("Resending verification email for user: {}", user.getEmail());

    // Send verification email
    try {
      emailService.sendVerificationEmail(user.getEmail(), token);
    } catch (Exception e) {
      log.error("Failed to resend verification email to {}", user.getEmail(), e);
      throw new RuntimeException("Failed to send verification email");
    }
  }

  @Transactional
  public void requestPasswordReset(String email) {
    User user =
        userRepository
            .findByEmail(email.trim().toLowerCase())
            .orElseThrow(() -> new ValidationException("No account found with this email address"));

    // Generate reset token
    String token = generateVerificationToken();
    user.setPasswordResetToken(token);
    user.setPasswordResetTokenExpiry(Instant.now().plus(1, ChronoUnit.HOURS));

    userRepository.save(user);
    log.info("Password reset requested for user: {}", user.getEmail());

    // Send reset email
    try {
      emailService.sendPasswordResetEmail(user.getEmail(), token);
    } catch (Exception e) {
      log.error("Failed to send password reset email to {}", user.getEmail(), e);
      throw new RuntimeException("Failed to send password reset email");
    }
  }

  @Transactional
  public void resetPassword(String token, String newPassword) {
    validatePassword(newPassword);

    User user =
        userRepository
            .findByPasswordResetToken(token)
            .orElseThrow(() -> new ValidationException("Invalid or expired password reset token"));

    if (user.getPasswordResetTokenExpiry() == null
        || user.getPasswordResetTokenExpiry().isBefore(Instant.now())) {
      throw new ValidationException("Password reset token has expired");
    }

    user.setPassword(passwordEncoder.encode(newPassword));
    user.setPasswordResetToken(null);
    user.setPasswordResetTokenExpiry(null);

    userRepository.save(user);
    log.info("Password reset successfully for user: {}", user.getEmail());
  }

  private String generateVerificationToken() {
    byte[] bytes = new byte[32];
    RANDOM.nextBytes(bytes);
    return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
  }

  private void validateEmail(String email) {
    if (email == null || email.trim().isEmpty()) {
      throw new ValidationException("Email is required");
    }
    if (!EMAIL_PATTERN.matcher(email.trim()).matches()) {
      throw new ValidationException("Invalid email format");
    }
  }

  @Transactional
  public void changePassword(String email, String currentPassword, String newPassword) {
    validatePassword(newPassword);

    User user =
        userRepository
            .findByEmail(email.trim().toLowerCase())
            .orElseThrow(() -> new ValidationException("User not found"));

    // Verify current password
    if (!passwordEncoder.matches(currentPassword, user.getPassword())) {
      throw new ValidationException("Current password is incorrect");
    }

    // Update to new password
    user.setPassword(passwordEncoder.encode(newPassword));
    userRepository.save(user);
    log.info("Password changed successfully for user: {}", user.getEmail());
  }

  @Transactional
  public void deleteAccount(String email) {
    User user =
        userRepository
            .findByEmail(email.trim().toLowerCase())
            .orElseThrow(() -> new ValidationException("User not found"));

    log.info("Deleting user account: {} (id={})", user.getEmail(), user.getId());
    userRepository.delete(user);
    log.info("User account deleted: {}", user.getEmail());
  }

  private void validatePassword(String password) {
    if (password == null || password.length() < 8) {
      throw new ValidationException("Password must be at least 8 characters long");
    }
  }
}
