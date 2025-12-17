<template>
  <div class="legal-container">
    <header class="legal-header">
      <h1 class="legal-title">Privacy Policy</h1>
      <p class="legal-subtitle">Last Updated: {{ new Date().toLocaleDateString() }}</p>
    </header>

    <div class="legal-content">
      <p>
        This Privacy Policy explains how oglimmer.com / Oliver Zimpasser ("we",
        "our", "us") processes personal data when you use Picz2 – Picture Sharing
        (the "Platform"). It applies to all visitors and registered users.
      </p>

      <h2>1. Controller</h2>
      <p>
        Controller under Art. 4(7) GDPR:<br />
        Oliver Zimpasser, Berliner Str. 39a, 63110 Rodgau, Germany<br />
        Email: <a href="mailto:oglimmer@gmail.com">oglimmer@gmail.com</a>
      </p>

      <h2>2. Data We Process</h2>
      <p>
        We process the following categories of data depending on how you use the Platform:
      </p>
      <ul>
        <li>Account data (e.g., email address, login data).</li>
        <li>User content and metadata you upload (e.g., images and image metadata).</li>
        <li>Usage data (e.g., pages viewed, feature interactions).</li>
        <li>Technical data (e.g., IP address, browser/user-agent, device information).</li>
        <li>Identifiers stored in cookies/local storage (e.g., consent choice, visitor ID upon consent).</li>
      </ul>

      <h2>3. Purposes and Legal Bases</h2>
      <ul>
        <li>
          Service provision and account management (Art. 6(1)(b) GDPR): operating the Platform,
          authentication, transactional communications, user content display.
        </li>
        <li>
          Security, abuse prevention and troubleshooting (Art. 6(1)(f) GDPR): maintaining service
          integrity, preventing misuse, logging limited technical data such as IP address and user-agent.
        </li>
        <li>
          Usage statistics/analytics (Art. 6(1)(a) GDPR for cookies; Art. 6(1)(f) GDPR otherwise):
          we generate aggregated statistics about public galleries. If you consent, we set a
          `visitor_id` cookie. If you decline, we still process minimal technical data (e.g., IP
          address and user-agent) on our servers to produce basic, aggregated statistics and to
          secure the service, without setting analytics cookies.
        </li>
        <li>
          Legal obligations (Art. 6(1)(c) GDPR): complying with statutory requirements.
        </li>
      </ul>

      <h2>4. Cookies</h2>
      <p>We use cookies only as described below:</p>
      <ul>
        <li>
          <code>cookie_consent</code> (essential): stores your consent choice for up to 12 months.
        </li>
        <li>
          <code>visitor_id</code> (analytics, optional): set for about 90 days only if you accept
          analytics cookies; used to count unique visits to public galleries.
        </li>
      </ul>
      <p>You can change your choice any time by clearing your browser cookies.</p>

      <h2>5. Analytics and Server Logs</h2>
      <p>
        We do not use third‑party analytics. Analytics events are handled on our servers. If you
        accept analytics cookies, we use a `visitor_id` cookie. If you decline, we do not set
        analytics cookies; we may still process IP address and user-agent to derive a short-lived
        pseudonymous identifier for aggregated statistics and service security. You can object to
        processing based on legitimate interests (see Section 9).
      </p>

      <h2>6. Recipients and Transfers</h2>
      <p>
        We do not sell your data. Where we use service providers (e.g., hosting or email delivery),
        they act as processors under Art. 28 GDPR and process data only on our instructions. We do
        not transfer data outside the EU unless adequate safeguards are in place.
      </p>

      <h2>7. Retention</h2>
      <ul>
        <li>Account data: retained for the life of your account; deleted upon account deletion.</li>
        <li>User content: retained until you remove it or delete your account.</li>
        <li>Analytics and usage data: retained for a limited period appropriate for aggregated reporting.</li>
        <li>Server logs and security data: retained for a short period unless needed to investigate issues.</li>
      </ul>

      <h2>8. Security</h2>
      <p>
        We implement appropriate technical and organizational measures to protect your data. No
        online service can guarantee absolute security.
      </p>

      <h2>9. Your Rights (EU/EEA)</h2>
      <p>
        You have the rights of access, rectification, erasure, restriction, portability, and
        objection (Art. 15–21 GDPR). Where processing is based on consent, you may withdraw consent
        at any time with effect for the future. You also have the right to lodge a complaint with a
        supervisory authority in Germany.
      </p>

      <h2>10. Children</h2>
      <p>
        The Platform is not intended for children under 16. Do not create an account or upload
        content if you are under 16.
      </p>

      <h2>11. Changes to this Policy</h2>
      <p>
        We may update this Privacy Policy to reflect changes in our practices or legal requirements.
        The “Last Updated” date reflects the effective date of the current version.
      </p>

      <h2>12. Contact</h2>
      <p>
        For privacy questions or requests, contact: <a href="mailto:oglimmer@gmail.com">oglimmer@gmail.com</a>.
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
