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
