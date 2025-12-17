<template>
  <div class="legal-container">
    <header class="legal-header">
      <h1 class="legal-title">Imprint / Impressum</h1>
      <p class="legal-subtitle">Legal information and contact details</p>
    </header>

    <div class="legal-content">
      <p>For Germany: Angaben gemäß § 5 TMG</p>

      <h2>Diensteanbieter / Website Provider</h2>
      <p>Diese Webseite wird bereitgestellt von / This website is provided by:</p>

      <h3>Oliver Zimpasser</h3>
      <p>
        Berliner Str. 39a<br />
        63110 Rodgau<br />
        Germany
      </p>

      <h2>Kontakt / Contact</h2>
      <p>
        E‑Mail: <a href="mailto:oglimmer@gmail.com">oglimmer@gmail.com</a><br />
        (Angaben zur schnellen elektronischen Kontaktaufnahme und unmittelbaren Kommunikation gem. § 5 Abs. 1 Nr. 2 TMG)
      </p>

      <h2>Verantwortlich i.S.d. § 18 Abs. 2 MStV</h2>
      <p>
        Verantwortlich für den Inhalt / Responsible for content:<br />
        Oliver Zimpasser, Berliner Str. 39a, 63110 Rodgau, Germany
      </p>

      <h2>EU‑Streitschlichtung / Dispute Resolution</h2>
      <p>
        Die Europäische Kommission stellt eine Plattform zur Online‑Streitbeilegung (OS) bereit:
        <a href="https://ec.europa.eu/consumers/odr" target="_blank" rel="noopener">https://ec.europa.eu/consumers/odr</a>.
        Wir sind nicht verpflichtet und grundsätzlich nicht bereit, an Streitbeilegungsverfahren vor einer
        Verbraucherschlichtungsstelle teilzunehmen.
      </p>

      <h2>Service Information</h2>
      <p>All services are provided free of charge.</p>
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
