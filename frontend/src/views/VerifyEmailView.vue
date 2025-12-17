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

<style scoped>
.login-container {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  padding: 20px;
}

.login-card {
  background: white;
  border-radius: 12px;
  padding: 40px;
  box-shadow: 0 10px 40px rgba(0, 0, 0, 0.2);
  max-width: 500px;
  width: 100%;
}

.verification-card {
  text-align: center;
}

.verification-content {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.loading {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 20px;
  padding: 40px 0;
}

.spinner {
  width: 60px;
  height: 60px;
  border: 4px solid #f3f4f6;
  border-top-color: #667eea;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

.loading p {
  color: #555;
  font-size: 1.1em;
}

.icon-wrapper {
  display: flex;
  justify-content: center;
  margin-bottom: 10px;
}

.icon-wrapper svg {
  width: 80px;
  height: 80px;
}

.success-icon svg {
  color: #10b981;
}

.error-icon svg {
  color: #ef4444;
}

h1 {
  margin: 0;
  color: #333;
  font-weight: 700;
  font-size: 1.8em;
}

.message {
  color: #555;
  line-height: 1.6;
  margin: 0;
  font-size: 1.05em;
}

.error-message {
  color: #dc2626;
  font-weight: 500;
}

.actions {
  margin-top: 10px;
}

.btn {
  display: inline-block;
  padding: 12px 30px;
  text-decoration: none;
}
</style>
