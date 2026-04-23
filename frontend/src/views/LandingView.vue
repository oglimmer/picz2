<template>
  <div class="landing">

    <nav class="lp-nav">
      <span class="lp-brand">Picz</span>
      <div class="lp-nav-links">
        <router-link to="/privacy">Privacy</router-link>
        <router-link to="/imprint">Imprint</router-link>
        <button class="lp-signin-btn" @click="goToLogin">Sign In</button>
      </div>
    </nav>

    <section class="lp-hero">
      <div class="lp-hero-text">
        <p class="lp-eyebrow">Private &middot; Simple &middot; Yours</p>
        <h1 class="lp-headline">Your memories,<br>beautifully shared.</h1>
        <p class="lp-tagline">
          Private photo galleries for the people who matter.
          No social media, no algorithms, no&nbsp;ads.
        </p>
        <button class="lp-cta" @click="goToLogin">
          Get Started
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/>
          </svg>
        </button>
      </div>

      <div class="lp-hero-visual" aria-hidden="true">
        <div class="photo-stack">
          <div class="photo-card photo-card--1">
            <div class="photo-card-img"></div>
            <span class="photo-card-label">Summer 2024</span>
          </div>
          <div class="photo-card photo-card--2">
            <div class="photo-card-img"></div>
            <span class="photo-card-label">Lisbon Trip</span>
          </div>
          <div class="photo-card photo-card--3">
            <div class="photo-card-img"></div>
            <span class="photo-card-label">Family Photos</span>
          </div>
        </div>
      </div>
    </section>

    <section class="lp-features">
      <h2 class="lp-section-title">Everything you need,<br>nothing you don't</h2>
      <div class="lp-grid">
        <div class="lp-feature lp-feature--highlight">
          <div class="lp-feature-icon">✨</div>
          <h3>Private &amp; Simple</h3>
          <p>Private photo galleries for your travel memories. No accounts needed for viewers.</p>
        </div>
        <div class="lp-feature">
          <div class="lp-feature-icon">🖼️</div>
          <h3>Organize Albums</h3>
          <p>Create and manage your photo albums with ease.</p>
        </div>
        <div class="lp-feature">
          <div class="lp-feature-icon">🏷️</div>
          <h3>Smart Tagging</h3>
          <p>Tag and categorize your photos for quick access.</p>
        </div>
        <div class="lp-feature">
          <div class="lp-feature-icon">🔗</div>
          <h3>Share &amp; Present</h3>
          <p>Share albums with others or present in slideshow mode.</p>
        </div>
        <div class="lp-feature">
          <div class="lp-feature-icon">🎙️</div>
          <h3>Audio Recording</h3>
          <p>Record narration during slideshows with synchronized playback.</p>
        </div>
      </div>
    </section>

    <footer class="lp-footer">
      <p class="lp-footer-copy">© {{ new Date().getFullYear() }} Picz</p>
      <div class="lp-footer-links">
        <router-link to="/privacy">Privacy</router-link>
        <span>·</span>
        <router-link to="/terms">Terms</router-link>
        <span>·</span>
        <router-link to="/imprint">Imprint</router-link>
      </div>
    </footer>

  </div>
</template>

<script setup lang="ts">
import { useRouter } from 'vue-router';

const router = useRouter();

function goToLogin() {
  router.push('/login');
}
</script>
