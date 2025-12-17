<template>
  <Teleport to="body">
    <Transition name="consent">
      <div
        v-if="showConsent"
        class="consent-overlay"
      >
        <div class="consent-banner">
          <div class="consent-content">
            <h3 class="consent-title">
              Privacy & Cookies
            </h3>
            <p class="consent-message">
              This website collects analytics to understand how features are used and to improve your experience.
              We track page views, feature usage, and interactions using your IP address and browser information.
              If you accept, we will set a visitor tracking cookie to recognize you on return visits.
              If you decline, we still collect the same analytics data, but without the persistent cookie.
              You can decline and still use the site normally.
            </p>
            <p class="consent-info">
              <a
                href="#"
                class="consent-link"
                @click.prevent="showDetails = !showDetails"
              >
                {{ showDetails ? 'Hide details' : 'Learn more' }}
              </a>
            </p>
            <div
              v-if="showDetails"
              class="consent-details"
            >
              <p><strong>What we collect:</strong></p>
              <ul>
                <li>Pages you visit and features you use</li>
                <li>Browser type and device information</li>
                <li>IP address (processed on our servers)</li>
                <li>Time spent on pages</li>
              </ul>
              <p><strong>What we don't collect:</strong></p>
              <ul>
                <li>Personal information or names</li>
                <li>Email addresses</li>
                <li>Content you upload or view</li>
              </ul>
              <p class="consent-note">
                <strong>Accept:</strong> Sets a visitor tracking cookie to recognize returning visitors across sessions.<br>
                <strong>Decline:</strong> No cookies set, but analytics still collected using IP/browser data only.<br><br>
                Data is stored securely and not sold to third parties. You can change your preference any time by clearing
                your browser cookies. Learn more in our <router-link to="/privacy">Privacy Policy</router-link>.
              </p>
            </div>
          </div>

          <div class="consent-actions">
            <button
              class="consent-button consent-button-accept"
              @click="handleAccept"
            >
              Accept Cookie
            </button>
            <button
              class="consent-button consent-button-decline"
              @click="handleDecline"
            >
              Decline Cookie
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'

const showConsent = ref(false)
const showDetails = ref(false)

const CONSENT_COOKIE = 'cookie_consent'
const CONSENT_EXPIRY_DAYS = 365 // 1 year

const emit = defineEmits<{
  consent: [accepted: boolean]
}>()

onMounted(() => {
  // Check if user has already made a choice
  const consent = getConsentStatus()
  if (consent === null) {
    // No consent choice made yet, show banner
    showConsent.value = true
  }
})

function getConsentStatus(): boolean | null {
  const cookies = document.cookie.split(';')
  for (const cookie of cookies) {
    const [name, value] = cookie.trim().split('=')
    if (name === CONSENT_COOKIE) {
      return value === 'accepted'
    }
  }
  return null
}

function setConsentCookie(accepted: boolean) {
  const expiryDate = new Date()
  expiryDate.setDate(expiryDate.getDate() + CONSENT_EXPIRY_DAYS)
  const value = accepted ? 'accepted' : 'declined'
  document.cookie = `${CONSENT_COOKIE}=${value}; expires=${expiryDate.toUTCString()}; path=/; SameSite=Lax; Secure`
}

function handleAccept() {
  setConsentCookie(true)
  showConsent.value = false
  emit('consent', true)
}

function handleDecline() {
  setConsentCookie(false)
  showConsent.value = false
  emit('consent', false)
}
</script>

<style scoped>
.consent-overlay {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  z-index: 10000;
  padding: 20px;
  pointer-events: none;
}

.consent-banner {
  max-width: 800px;
  margin: 0 auto;
  background: white;
  border-radius: 12px;
  box-shadow: 0 -4px 20px rgba(0, 0, 0, 0.15);
  padding: 24px;
  pointer-events: auto;
  border: 1px solid #e5e7eb;
}

.consent-content {
  margin-bottom: 20px;
}

.consent-title {
  margin: 0 0 12px 0;
  font-size: 1.25rem;
  font-weight: 600;
  color: #111827;
}

.consent-message {
  margin: 0 0 12px 0;
  font-size: 0.95rem;
  line-height: 1.6;
  color: #4b5563;
}

.consent-info {
  margin: 0;
}

.consent-link {
  color: #667eea;
  text-decoration: none;
  font-size: 0.9rem;
  font-weight: 500;
  cursor: pointer;
}

.consent-link:hover {
  text-decoration: underline;
}

.consent-details {
  margin-top: 16px;
  padding: 16px;
  background: #f9fafb;
  border-radius: 8px;
  font-size: 0.875rem;
  color: #374151;
}

.consent-details p {
  margin: 8px 0;
}

.consent-details strong {
  color: #111827;
}

.consent-details ul {
  margin: 8px 0;
  padding-left: 24px;
}

.consent-details li {
  margin: 4px 0;
  line-height: 1.5;
}

.consent-note {
  margin-top: 12px;
  padding-top: 12px;
  border-top: 1px solid #e5e7eb;
  font-style: italic;
  color: #6b7280;
}

.consent-actions {
  display: flex;
  gap: 12px;
  justify-content: flex-end;
}

.consent-button {
  padding: 12px 24px;
  border-radius: 8px;
  font-size: 0.95rem;
  font-weight: 600;
  border: none;
  cursor: pointer;
  transition: all 0.2s;
  min-width: 140px;
}

.consent-button:focus {
  outline: none;
  box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.3);
}

.consent-button-accept {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
}

.consent-button-accept:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
}

.consent-button-decline {
  background: #f3f4f6;
  color: #6b7280;
}

.consent-button-decline:hover {
  background: #e5e7eb;
  color: #4b5563;
}

/* Transition animations */
.consent-enter-active {
  transition: all 0.4s ease-out;
}

.consent-leave-active {
  transition: all 0.3s ease-in;
}

.consent-enter-from {
  opacity: 0;
  transform: translateY(100%);
}

.consent-leave-to {
  opacity: 0;
  transform: translateY(100%);
}

/* Responsive design */
@media (max-width: 640px) {
  .consent-overlay {
    padding: 0;
  }

  .consent-banner {
    border-radius: 12px 12px 0 0;
    padding: 20px;
  }

  .consent-title {
    font-size: 1.1rem;
  }

  .consent-message {
    font-size: 0.875rem;
  }

  .consent-actions {
    flex-direction: column-reverse;
  }

  .consent-button {
    width: 100%;
  }
}
</style>
