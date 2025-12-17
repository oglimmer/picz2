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

.icon-wrapper {
  display: flex;
  justify-content: center;
  margin-bottom: 10px;
}

.icon-wrapper svg {
  width: 80px;
  height: 80px;
  color: #667eea;
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

.info-box {
  background: #f9fafb;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  padding: 20px;
  text-align: left;
}

.info-box strong {
  color: #333;
  display: block;
  margin-bottom: 10px;
}

.info-box ul {
  margin: 0;
  padding-left: 20px;
  color: #555;
}

.info-box li {
  margin-bottom: 6px;
}

.success-box {
  background: #d1fae5;
  border: 1px solid #6ee7b7;
  border-radius: 8px;
  padding: 15px;
  color: #065f46;
  font-weight: 500;
}

.error-box {
  background: #fee2e2;
  border: 1px solid #fca5a5;
  border-radius: 8px;
  padding: 15px;
  color: #991b1b;
  font-weight: 500;
}

.actions {
  margin-top: 10px;
}

.btn {
  display: inline-block;
  padding: 12px 30px;
  text-decoration: none;
  border: none;
  border-radius: 6px;
  font-size: 1em;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
}

.btn-primary {
  background: #667eea;
  color: white;
}

.btn-primary:hover {
  background: #5568d3;
}

.btn-secondary {
  background: #f3f4f6;
  color: #374151;
  border: 1px solid #d1d5db;
}

.btn-secondary:hover:not(:disabled) {
  background: #e5e7eb;
}

.btn-secondary:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.link-button {
  background: none;
  border: none;
  color: #667eea;
  cursor: pointer;
  font-size: 1em;
  padding: 8px 16px;
  text-decoration: none;
  transition: color 0.2s;
}

.link-button:hover {
  color: #5568d3;
  text-decoration: underline;
}
</style>
