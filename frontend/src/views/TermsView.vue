<template>
  <div class="legal-container">
    <header class="legal-header">
      <h1 class="legal-title">Terms and Conditions</h1>
      <p class="legal-subtitle">Last Updated: {{ new Date().toLocaleDateString() }}</p>
    </header>

    <div class="legal-content">
      <p>
        These Terms and Conditions ("Terms") govern your use of Picz2 - Picture
        Sharing ("the Platform"), provided by oglimmer.com / Oliver Zimpasser
        ("we," "our," or "us"). By accessing or using the Platform, you agree to
        abide by these Terms. If you do not agree with any part of these Terms,
        you should not use the Platform.
      </p>

      <h2>1. Acceptable Use</h2>

      <p>1.1. You must be at least 16 years old to use the Platform.</p>

      <p>
        1.2. You are solely responsible for all content you upload, share, or post
        on the Platform, including images, text, and other materials ("User
        Content"). You agree not to upload or share User Content that is illegal,
        offensive, harmful, defamatory, infringing, or violates any third-party
        rights.
      </p>

      <p>
        1.3. You may not use the Platform for any unauthorized or illegal
        purposes, including but not limited to distributing malware, spamming, or
        engaging in any form of hacking.
      </p>

      <h2>2. Intellectual Property</h2>

      <p>
        2.1. You retain full ownership of all intellectual property rights in your
        User Content. By uploading content to the Platform, you grant us a
        limited, non-exclusive, worldwide, royalty-free license solely to display
        your User Content on the Platform. This license exists only to make your
        content viewable by others via a direct link (URL) that you or others may
        choose to share. We do not promote, sell, license, or otherwise use your
        content beyond displaying it on the Platform.
      </p>

      <p>
        2.2. Access to your content is public in the sense that anyone with the
        unique URL can view it. We do not actively share or distribute these URLs.
        You are solely responsible for the sharing and privacy of the content you
        upload. We disclaim all liability for any access or sharing that occurs as
        a result of someone obtaining the URL.
      </p>

      <p>
        2.3. We do not claim any ownership of your User Content and will never
        sell, license, or use it for any purpose other than displaying it on the
        Platform as described above.
      </p>

      <h2>3. Privacy</h2>

      <p>
        3.1. Our <router-link to="/privacy">Privacy Policy</router-link> explains how we
        collect and process personal data, the purposes and legal bases, retention periods,
        and your rights. By using the Platform, you acknowledge that you have read it.
      </p>

      <h2>4. User Accounts</h2>

      <p>
        4.1. You are responsible for maintaining the confidentiality of your
        account credentials and for all activities that occur under your account.
      </p>

      <p>
        4.2. You agree to provide accurate, current, and complete information
        during the registration process and to update such information to keep it
        accurate, current, and complete.
      </p>

      <p>
        4.3. We reserve the right to suspend or terminate your account at our
        discretion if we believe you have violated these Terms or engaged in any
        fraudulent or abusive behavior.
      </p>

      <h2>5. Email Communication</h2>

      <p>
        5.1. We send transactional or service communications necessary to operate your
        account and the Platform (e.g., account notices, security alerts).
      </p>

      <p>
        5.2. We do not send marketing emails without your prior, explicit consent. If we
        introduce marketing communications in the future, we will request your opt‑in and
        include an unsubscribe option in every message.
      </p>

      <p>
        5.3. Deleting your account removes your email address from our systems, after which
        we will no longer contact you.
      </p>

      <p>5.4. We will not sell your email address to any third party company.</p>

      <h2>6. Content Monitoring</h2>

      <p>
        6.1. By using our services, you acknowledge and agree that we reserve the
        right to scan and monitor any materials you upload, submit, or transmit
        through our platform. This includes both automated and non-automated
        processes designed to identify and detect illegal, prohibited, or
        infringing content.
      </p>

      <p>
        6.2. We are committed to maintaining a safe and lawful environment for all
        users, and this proactive approach helps us ensure compliance with
        applicable laws, regulations, and our terms of service.
      </p>

      <h2>7. Termination</h2>

      <p>
        7.1. You may terminate your use of the Platform at any time by deleting
        your account.
      </p>

      <p>
        7.2. We reserve the right to suspend, terminate, or modify the Platform at
        any time for any reason without notice.
      </p>

      <h2>8. Disclaimer of Warranties</h2>

      <p>
        8.1. The Platform is provided "as is" and "as available." We do not make
        any warranties or representations regarding the accuracy, completeness, or
        reliability of the Platform or any content therein.
      </p>

      <h2>9. Limitation of Liability</h2>

      <p>
        9.1. To the extent permitted by applicable law, we shall not be liable for
        any indirect, incidental, special, consequential, or punitive damages, or
        any loss of profits or revenues, whether incurred directly or indirectly,
        or any loss of data, use, goodwill, or other intangible losses.
      </p>

      <h2>10. Governing Law</h2>

      <p>
        10.1. These Terms shall be governed by and construed in accordance with the
        laws of Germany, without regard to its conflict of law principles.
      </p>

      <h2>11. Changes to Terms</h2>

      <p>
        11.1. We reserve the right to modify or replace these Terms at any time.
        It is your responsibility to review these Terms periodically. Your
        continued use of the Platform after any changes indicates your acceptance
        of those changes.
      </p>

      <h2>12. Contact</h2>

      <p>
        12.1. If you have any questions or concerns about these Terms, please
        contact us at
        <a href="mailto:oglimmer@gmail.com">oglimmer@gmail.com</a>.
      </p>
    </div>

    <footer class="legal-footer">
      <p>© {{ new Date().getFullYear() }} Picz2</p>
      <router-link to="/">Home</router-link> |
      <router-link to="/privacy">Privacy</router-link> |
      <router-link to="/terms">Terms</router-link> |
      <router-link to="/imprint">Imprint</router-link>
    </footer>
  </div>
</template>

<script setup lang="ts">
import '@/assets/css/legal.css';
</script>
