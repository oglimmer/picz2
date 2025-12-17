/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;

@Service
@Slf4j
@RequiredArgsConstructor
public class EmailService {

  private final JavaMailSender mailSender;

  @Value("${app.base-url:http://localhost}")
  private String baseUrl;

  @Value("${spring.mail.from:noreply@junta-online.net}")
  private String fromEmail;

  @Value("${app.mail.enabled:true}")
  private boolean mailEnabled;

  /**
   * Send email or log it if mail is disabled
   *
   * @param message The email message to send or log
   */
  private void sendOrLog(SimpleMailMessage message) {
    if (mailEnabled) {
      mailSender.send(message);
    } else {
      log.info(
          "Email sending is disabled. Would have sent email:\nFrom: {}\nTo: {}\nSubject: {}\nBody:\n{}",
          message.getFrom(),
          message.getTo() != null && message.getTo().length > 0 ? message.getTo()[0] : "N/A",
          message.getSubject(),
          message.getText());
    }
  }

  /**
   * Send email verification link to user
   *
   * @param toEmail User's email address
   * @param verificationToken Unique verification token
   */
  public void sendVerificationEmail(String toEmail, String verificationToken) {
    try {
      String verificationLink = baseUrl + "/verify-email?token=" + verificationToken;

      SimpleMailMessage message = new SimpleMailMessage();
      message.setFrom(fromEmail);
      message.setTo(toEmail);
      message.setSubject("Verify your Picz2 account");
      message.setText(
          """
          Welcome to Picz2!

          Please verify your email address by clicking the link below:

          %s

          This link will expire in 24 hours.

          If you did not create an account, please ignore this email.

          ---
          Picz2 - Picture Sharing
          %s
          """
              .formatted(verificationLink, baseUrl));

      sendOrLog(message);
      log.info("Verification email sent to: {}", toEmail);

    } catch (Exception e) {
      log.error("Failed to send verification email to: {}", toEmail, e);
      throw new RuntimeException("Failed to send verification email", e);
    }
  }

  /**
   * Send welcome email after successful verification
   *
   * @param toEmail User's email address
   */
  public void sendWelcomeEmail(String toEmail) {
    try {
      SimpleMailMessage message = new SimpleMailMessage();
      message.setFrom(fromEmail);
      message.setTo(toEmail);
      message.setSubject("Welcome to Picz2!");
      message.setText(
          """
          Welcome to Picz2!

          Your email has been successfully verified. You can now log in and start sharing your photos.

          Get started: %s/login

          ---
          Picz2 - Picture Sharing
          %s
          """
              .formatted(baseUrl, baseUrl));

      sendOrLog(message);
      log.info("Welcome email sent to: {}", toEmail);

    } catch (Exception e) {
      log.error("Failed to send welcome email to: {}", toEmail, e);
      // Don't throw - welcome email is not critical
    }
  }

  /**
   * Send password reset link to user
   *
   * @param toEmail User's email address
   * @param resetToken Unique password reset token
   */
  public void sendPasswordResetEmail(String toEmail, String resetToken) {
    try {
      String resetLink = baseUrl + "/reset-password?token=" + resetToken;

      SimpleMailMessage message = new SimpleMailMessage();
      message.setFrom(fromEmail);
      message.setTo(toEmail);
      message.setSubject("Reset your Picz2 password");
      message.setText(
          """
          Hello,

          We received a request to reset your Picz2 account password.

          Click the link below to reset your password:

          %s

          This link will expire in 1 hour.

          If you did not request a password reset, please ignore this email. Your password will remain unchanged.

          ---
          Picz2 - Picture Sharing
          %s
          """
              .formatted(resetLink, baseUrl));

      sendOrLog(message);
      log.info("Password reset email sent to: {}", toEmail);

    } catch (Exception e) {
      log.error("Failed to send password reset email to: {}", toEmail, e);
      throw new RuntimeException("Failed to send password reset email", e);
    }
  }

  /**
   * Send subscription confirmation email
   *
   * @param toEmail Subscriber's email address
   * @param confirmationToken Unique confirmation token
   * @param albumName Name of the album being subscribed to
   * @param unsubscribeToken Unique unsubscribe token
   */
  public void sendSubscriptionConfirmationEmail(
      String toEmail, String confirmationToken, String albumName, String unsubscribeToken) {
    try {
      String confirmationLink = baseUrl + "/public/subscription/confirm?token=" + confirmationToken;
      String unsubscribeLink =
          baseUrl + "/api/public/subscriptions/unsubscribe?token=" + unsubscribeToken;

      SimpleMailMessage message = new SimpleMailMessage();
      message.setFrom(fromEmail);
      message.setTo(toEmail);
      message.setSubject("Confirm your album subscription - " + albumName);
      message.setText(
          """
          Hello,

          You have requested to subscribe to updates for the album "%s".

          Please confirm your subscription by clicking the link below:

          %s

          Once confirmed, you will receive notifications when:
          - New images are added to this album (if selected)
          - New albums are created by the album owner (if selected)

          If you did not request this subscription, please ignore this email.

          ---
          Picz2 - Picture Sharing
          %s

          Unsubscribe: %s
          """
              .formatted(albumName, confirmationLink, baseUrl, unsubscribeLink));

      sendOrLog(message);
      log.info("Subscription confirmation email sent to: {}", toEmail);

    } catch (Exception e) {
      log.error("Failed to send subscription confirmation email to: {}", toEmail, e);
      throw new RuntimeException("Failed to send subscription confirmation email", e);
    }
  }

  /**
   * Send album update notification email
   *
   * @param toEmail Subscriber's email address
   * @param albumName Name of the album that was updated
   * @param shareToken Album share token for viewing
   * @param newImageCount Number of new images added
   * @param unsubscribeToken Unique unsubscribe token
   */
  public void sendAlbumUpdateNotification(
      String toEmail,
      String albumName,
      String shareToken,
      int newImageCount,
      String unsubscribeToken) {
    try {
      String albumLink = baseUrl + "/public/album/" + shareToken;
      String unsubscribeLink =
          baseUrl + "/api/public/subscriptions/unsubscribe?token=" + unsubscribeToken;

      SimpleMailMessage message = new SimpleMailMessage();
      message.setFrom(fromEmail);
      message.setTo(toEmail);
      message.setSubject("New images added to " + albumName);
      message.setText(
          """
          Hello,

          The album "%s" you're subscribed to has been updated!

          %d new image%s been added.

          View the album: %s

          ---
          Picz2 - Picture Sharing
          %s

          Unsubscribe: %s
          """
              .formatted(
                  albumName,
                  newImageCount,
                  newImageCount == 1 ? " has" : "s have",
                  albumLink,
                  baseUrl,
                  unsubscribeLink));

      sendOrLog(message);
      log.info("Album update notification sent to: {} for album: {}", toEmail, albumName);

    } catch (Exception e) {
      log.error("Failed to send album update notification to: {}", toEmail, e);
      // Don't throw - notifications are not critical
    }
  }

  /**
   * Send new album notification email
   *
   * @param toEmail Subscriber's email address
   * @param ownerName Name of the album owner
   * @param newAlbumName Name of the new album
   * @param shareToken Album share token for viewing
   * @param unsubscribeToken Unique unsubscribe token
   */
  public void sendNewAlbumNotification(
      String toEmail,
      String ownerName,
      String newAlbumName,
      String shareToken,
      String unsubscribeToken) {
    try {
      String albumLink = baseUrl + "/public/album/" + shareToken;
      String unsubscribeLink =
          baseUrl + "/api/public/subscriptions/unsubscribe?token=" + unsubscribeToken;

      SimpleMailMessage message = new SimpleMailMessage();
      message.setFrom(fromEmail);
      message.setTo(toEmail);
      message.setSubject("New album from " + ownerName + ": " + newAlbumName);
      message.setText(
          """
          Hello,

          %s has created a new album: "%s"

          View the new album: %s

          ---
          Picz2 - Picture Sharing
          %s

          Unsubscribe: %s
          """
              .formatted(ownerName, newAlbumName, albumLink, baseUrl, unsubscribeLink));

      sendOrLog(message);
      log.info(
          "New album notification sent to: {} for album: {} by {}",
          toEmail,
          newAlbumName,
          ownerName);

    } catch (Exception e) {
      log.error("Failed to send new album notification to: {}", toEmail, e);
      // Don't throw - notifications are not critical
    }
  }
}
