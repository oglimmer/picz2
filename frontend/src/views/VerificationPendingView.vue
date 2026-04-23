<template>
  <div class="login-container">
    <div class="login-card verification-card">
      <header class="topbar">
        <div class="brand">
          Picz2
        </div>
        <nav class="nav-links">
          <router-link to="/" v-if="!isLoggedIn">
            Home
          </router-link>
          <button @click="handleLogout" v-if="isLoggedIn" class="link-button">
            Logout
          </button>
        </nav>
      </header>

      <div class="verification-content">
        <div class="icon-wrapper">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z" />
            <polyline points="22,6 12,13 2,6" />
          </svg>
        </div>

        <h1>Check Your Email</h1>

        <p class="message" v-if="authEmail">
          We've sent a confirmation link to <strong>{{ authEmail }}</strong>.
        </p>
        <p class="message" v-else>
          We've sent a confirmation link to your email address.
        </p>

        <p class="message">
          Please click the link in the email to verify your account and complete the registration process.
        </p>

        <div v-if="successMessage" class="success-box">
          {{ successMessage }}
        </div>

        <div v-if="errorMessage" class="error-box">
          {{ errorMessage }}
        </div>

        <div class="info-box">
          <strong>Didn't receive the email?</strong>
          <ul>
            <li>Check your spam or junk folder</li>
            <li>Make sure you entered the correct email address</li>
            <li>The link will expire in 24 hours</li>
          </ul>
        </div>

        <div class="actions">
          <button
            v-if="isLoggedIn"
            @click="resendEmail"
            :disabled="isResending"
            class="btn btn-secondary"
          >
            {{ isResending ? 'Sending...' : 'Resend Verification Email' }}
          </button>
          <router-link
            v-else
            to="/login"
            class="btn btn-primary"
          >
            Back to Login
          </router-link>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import { getApiUrl } from '../utils/api-config'

const apiUrl = getApiUrl()
const router = useRouter()
const { isLoggedIn, authEmail, logout, getAuthHeaders } = useAuth()

const isResending = ref(false)
const successMessage = ref('')
const errorMessage = ref('')

async function resendEmail() {
  isResending.value = true
  successMessage.value = ''
  errorMessage.value = ''

  try {
    const response = await fetch(`${apiUrl}/api/users/resend-verification`, {
      method: 'POST',
      headers: getAuthHeaders(),
    })

    if (response.ok) {
      successMessage.value = 'Verification email sent successfully! Please check your inbox.'
    } else {
      const errorData = await response.json().catch(() => ({}))
      errorMessage.value = errorData.message || 'Failed to send verification email. Please try again.'
    }
  } catch (error) {
    errorMessage.value = 'An error occurred. Please try again later.'
  } finally {
    isResending.value = false
  }
}

function handleLogout() {
  logout()
  router.push('/login')
}

onMounted(() => {
  document.body.classList.add('landing-page')
})

onUnmounted(() => {
  document.body.classList.remove('landing-page')
})
</script>
