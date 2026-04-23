<template>
  <div class="login-container">
    <div class="login-card verification-card">
      <header class="topbar">
        <div class="brand">
          Picz2
        </div>
        <nav class="nav-links">
          <router-link to="/">
            Home
          </router-link>
          <router-link to="/login">
            Login
          </router-link>
        </nav>
      </header>

      <div class="verification-content">
        <div
          v-if="loading"
          class="loading"
        >
          <div class="spinner" />
          <p>Verifying your email...</p>
        </div>

        <div
          v-else-if="success"
          class="success"
        >
          <div class="icon-wrapper success-icon">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
              <polyline points="22 4 12 14.01 9 11.01" />
            </svg>
          </div>

          <h1>Email Verified!</h1>

          <p class="message">
            Your email has been successfully verified. You can now log in to your account.
          </p>

          <div class="actions">
            <router-link
              to="/login"
              class="btn btn-primary"
            >
              Go to Login
            </router-link>
          </div>
        </div>

        <div
          v-else
          class="error"
        >
          <div class="icon-wrapper error-icon">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <circle
                cx="12"
                cy="12"
                r="10"
              />
              <line
                x1="12"
                y1="8"
                x2="12"
                y2="12"
              />
              <line
                x1="12"
                y1="16"
                x2="12.01"
                y2="16"
              />
            </svg>
          </div>

          <h1>Verification Failed</h1>

          <p class="message error-message">
            {{ errorMessage }}
          </p>

          <div class="actions">
            <router-link
              to="/register"
              class="btn btn-primary"
            >
              Back to Registration
            </router-link>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import { useApi } from '../composables/useApi'

const route = useRoute()
const { apiUrl } = useApi()

const loading = ref(true)
const success = ref(false)
const errorMessage = ref('The verification link is invalid or has expired.')

async function verifyEmail() {
  const token = route.query.token as string

  if (!token) {
    errorMessage.value = 'No verification token provided.'
    loading.value = false
    return
  }

  try {
    const res = await fetch(`${apiUrl}/api/users/verify-email?token=${encodeURIComponent(token)}`, {
      method: 'GET'
    })

    if (res.ok) {
      success.value = true
    } else {
      try {
        const err = await res.json()
        errorMessage.value = err?.message || 'The verification link is invalid or has expired.'
      } catch {
        errorMessage.value = 'The verification link is invalid or has expired.'
      }
    }
  } catch {
    errorMessage.value = 'Network error. Please try again later.'
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  document.body.classList.add('landing-page')
  verifyEmail()
})

onUnmounted(() => {
  document.body.classList.remove('landing-page')
})
</script>
