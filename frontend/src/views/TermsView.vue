<template>
  <div class="legal-container">
    <header class="legal-header">
      <h1 class="legal-title">Terms and Conditions</h1>
      <p class="legal-subtitle">Last Updated: 31 August 2026</p>
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

      <h2>5. Storage of Your Content</h2>

      <p>
        5.1. <strong>Storage we operate.</strong> Unless you choose otherwise, your User
        Content is stored on storage we operate, within a storage allowance we set for your
        account. The allowance is 100&nbsp;MiB unless we set a different one for you, and we
        may change it at any time. It counts original files, the copies we generate from them
        (thumbnails, resized images, transcoded video) and narration audio. When the allowance
        is used up, further uploads are refused until you free space or we raise it. We are
        under no obligation to store User Content beyond your allowance.
      </p>

      <p>
        5.2. <strong>Storage you provide.</strong> You may connect an S3-compatible storage
        bucket that you control and select it when you create an album. The selection is
        permanent for that album: an album cannot be moved to different storage afterwards.
        Content held in your own bucket does not count towards the allowance in 5.1 and we do
        not cap it.
      </p>

      <p>
        5.3. <strong>Your responsibility for your storage.</strong> You warrant that you are
        entitled to use the bucket and the credentials you supply, and that supplying them to
        us does not breach your agreement with your storage provider. You alone are
        responsible for your contract with that provider and for all charges it raises,
        including storage, request and egress fees; for the availability, durability, backup
        and geographic location of the data held there; and for any loss of User Content
        caused by that provider, by your revoking, rotating or deleting the credentials, or by
        your deleting or reconfiguring the bucket. We do not back up your bucket, and we are
        not liable for costs, loss or unavailability arising from storage you provide.
      </p>

      <p>
        5.4. <strong>What you instruct us to do there.</strong> By connecting a bucket you
        instruct us, and grant us the access needed, to write, read, copy and delete objects
        in it in order to operate the Platform for you. That includes storing originals and
        the copies we generate from them, deleting objects when you delete a photo or an
        album, and deleting original files under 5.6. When you add or change a connected
        storage we write, read and delete a small test object to confirm the credentials work.
        Grant us credentials limited to a single bucket and to those operations.
      </p>

      <p>
        5.5. <strong>Uploads and viewing still run through us.</strong> Every upload is
        received by our servers and held on storage we operate before it is transferred to
        your bucket. Viewing works the same way: viewers request content from us and we fetch
        it from your bucket. Your storage provider therefore does not receive the IP addresses
        of people who view your galleries, and a copy of every uploaded file passes through
        our systems even for albums stored with you.
      </p>

      <p>
        5.6. <strong>Original files are not archived.</strong> An uploaded original file is
        deleted about 7 days after upload, once the smaller copies generated from it exist.
        Those copies remain and your galleries continue to work, but the full-resolution
        original is gone. The purpose is to keep the cost of running a gallery low, so this
        applies to albums on storage you provide as well: the same automated process runs
        against your bucket, and it is what keeps your own storage bill down. The Platform is a
        gallery, not a backup service. Keep your own copy of anything you cannot afford to
        lose.
      </p>

      <p>
        5.7. <strong>Credentials.</strong> We store the secret access key you give us in
        encrypted form and use your credentials only to operate the Platform for you. You may
        remove a connected storage at any time unless an album still uses it. Revoking or
        changing the keys at your provider will stop the affected albums from working.
      </p>

      <p>
        5.8. <strong>Deleting your account.</strong> When you delete your account we delete
        your account data and your stored credentials from our systems, and content held on
        storage we operate is removed by our clean-up processes. We do not delete the objects
        left in a bucket you provided, because we no longer hold credentials for it. Removing
        that content is your responsibility.
      </p>

      <p>
        5.9. <strong>Availability of the feature.</strong> We may change, suspend or withdraw
        the option to use storage you provide. If your bucket, your provider or your
        credentials become unavailable, the albums stored there will not load. That is outside
        our control.
      </p>

      <h2>6. Email Communication</h2>

      <p>
        6.1. We send transactional or service communications necessary to operate your
        account and the Platform (e.g., account notices, security alerts).
      </p>

      <p>
        6.2. We do not send marketing emails without your prior, explicit consent. If we
        introduce marketing communications in the future, we will request your opt‑in and
        include an unsubscribe option in every message.
      </p>

      <p>
        6.3. Deleting your account removes your email address from our systems, after which
        we will no longer contact you.
      </p>

      <p>6.4. We will not sell your email address to any third party company.</p>

      <h2>7. Content Monitoring</h2>

      <p>
        7.1. By using our services, you acknowledge and agree that we reserve the
        right to scan and monitor any materials you upload, submit, or transmit
        through our platform. This includes both automated and non-automated
        processes designed to identify and detect illegal, prohibited, or
        infringing content.
      </p>

      <p>
        7.2. We are committed to maintaining a safe and lawful environment for all
        users, and this proactive approach helps us ensure compliance with
        applicable laws, regulations, and our terms of service.
      </p>

      <h2>8. Termination</h2>

      <p>
        8.1. You may terminate your use of the Platform at any time by deleting
        your account.
      </p>

      <p>
        8.2. We reserve the right to suspend, terminate, or modify the Platform at
        any time for any reason without notice.
      </p>

      <h2>9. Disclaimer of Warranties</h2>

      <p>
        9.1. The Platform is provided "as is" and "as available." We do not make
        any warranties or representations regarding the accuracy, completeness, or
        reliability of the Platform or any content therein.
      </p>

      <h2>10. Limitation of Liability</h2>

      <p>
        10.1. To the extent permitted by applicable law, we shall not be liable for
        any indirect, incidental, special, consequential, or punitive damages, or
        any loss of profits or revenues, whether incurred directly or indirectly,
        or any loss of data, use, goodwill, or other intangible losses.
      </p>

      <h2>11. Governing Law</h2>

      <p>
        11.1. These Terms shall be governed by and construed in accordance with the
        laws of Germany, without regard to its conflict of law principles.
      </p>

      <h2>12. Changes to Terms</h2>

      <p>
        12.1. We reserve the right to modify or replace these Terms at any time.
        It is your responsibility to review these Terms periodically. Your
        continued use of the Platform after any changes indicates your acceptance
        of those changes.
      </p>

      <h2>13. Contact</h2>

      <p>
        13.1. If you have any questions or concerns about these Terms, please
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
