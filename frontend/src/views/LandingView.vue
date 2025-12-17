<template>
  <div class="legal-container">
    <header class="legal-header">
      <h1 class="legal-title">📸 Picz2</h1>
      <p class="legal-subtitle">Share vacation moments, without the social media hassle</p>
    </header>

    <div class="legal-content">
      <div class="features">
          <div class="feature highlight-feature">
            <div class="feature-icon">
              ✨
            </div>
            <h3>Private & Simple</h3>
            <p>Private photo galleries for your travel memories. No accounts needed for viewers.</p>
          </div>
          <div class="feature">
            <div class="feature-icon">
              🖼️
            </div>
            <h3>Organize Albums</h3>
            <p>Create and manage your photo albums with ease</p>
          </div>

          <div class="feature">
            <div class="feature-icon">
              🏷️
            </div>
            <h3>Smart Tagging</h3>
            <p>Tag and categorize your photos for quick access</p>
          </div>

          <div class="feature">
            <div class="feature-icon">
              🔗
            </div>
            <h3>Share & Present</h3>
            <p>Share albums with others or present in slideshow mode</p>
          </div>

          <div class="feature">
            <div class="feature-icon">
              🎙️
            </div>
            <h3>Audio Recording</h3>
            <p>Record narration during slideshows with synchronized playback</p>
          </div>
        </div>

      <div class="cta-section">
        <button
          class="btn-primary btn-large"
          @click="goToLogin"
        >
          Get Started
        </button>
      </div>
    </div>

    <footer class="legal-footer">
      <p>© {{ new Date().getFullYear() }} Picz2</p>
      <router-link to="/privacy">Privacy</router-link> |
      <router-link to="/terms">Terms</router-link> |
      <router-link to="/imprint">Imprint</router-link>
    </footer>
  </div>
</template>

<script setup lang="ts">
import { useRouter } from 'vue-router';
import '@/assets/css/legal.css';

const router = useRouter();

function goToLogin() {
  router.push('/login');
}
</script>

<style scoped>
.features {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 20px;
  margin-bottom: 28px;
  text-align: left;
}

.highlight-feature {
  grid-column: 1 / -1;
  text-align: center;
}

.feature {
  padding: 15px;
  border-radius: 10px;
  background: #f8f9fa;
  transition: transform 0.3s, box-shadow 0.3s;
}

.feature:hover {
  transform: translateY(-3px);
  box-shadow: 0 5px 15px rgba(0, 0, 0, 0.1);
}

.feature-icon {
  font-size: 2.2em;
  margin-bottom: 8px;
}

.feature h3 {
  margin: 0 0 6px 0;
  color: #333;
  font-size: 1.1em;
  font-weight: 600;
}

.feature p {
  margin: 0;
  color: #666;
  line-height: 1.4;
  font-size: 0.85em;
}

.cta-section {
  text-align: center;
  margin-top: 40px;
  margin-bottom: 40px;
}

.btn-primary {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 16px 48px;
  border-radius: 50px;
  font-size: 1.1rem;
  font-weight: 600;
  border: none;
  cursor: pointer;
  transition: transform 0.3s ease, box-shadow 0.3s ease;
}

.btn-primary:hover {
  transform: translateY(-3px);
  box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3);
}

@media (max-width: 768px) {
  .features {
    grid-template-columns: 1fr;
  }
}
</style>
