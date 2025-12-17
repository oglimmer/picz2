<template>
  <div class="login-container">
    <div class="login-card">
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

      <h1>Reset Password</h1>
      <p class="subtitle">
        Enter your email address and we'll send you a link to reset your password.
      </p>

      <form
        v-if="!submitted"
        class="login-form"
        @submit.prevent="handleSubmit"
      >
        <div class="form-group">
          <label for="email">Email</label>
          <input
            id="email"
            v-model="email"
            type="email"
            placeholder="Enter your email"
            class="auth-input"
            required
            autofocus
          >
        </div>

        <div
          v-if="error"
          class="auth-error"
        >
          {{ error }}
        </div>

        <button
          type="submit"
          class="btn btn-primary btn-lg"
          :disabled="loading"
        >
          {{ loading ? 'Sending...' : 'Send Reset Link' }}
        </button>

        <div style="text-align:center; margin-top: 8px; font-size: 0.95em;">
          Remember your password?
          <router-link to="/login">
            Sign in
          </router-link>
        </div>
      </form>

      <div
        v-else
        class="success-message"
      >
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

        <h2>Check Your Email</h2>
        <p>
          If an account exists for {{ email }}, you will receive a password reset link shortly.
        </p>
        <p>
          The link will expire in 1 hour.
        </p>

        <router-link
          to="/login"
          class="btn btn-primary"
        >
          Back to Login
        </router-link>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useApi } from '../composables/useApi'

const { apiUrl } = useApi()

const email = ref('')
const loading = ref(false)
const error = ref('')
const submitted = ref(false)

async function handleSubmit() {
  error.value = ''
  if (!email.value) {
    error.value = 'Email is required'
    return
  }

  loading.value = true
  try {
    const res = await fetch(`${apiUrl}/api/users/password-reset-request`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: email.value })
    })

    if (res.ok) {
      submitted.value = true
    } else {
      try {
        const err = await res.json()
        error.value = err?.message || 'Failed to send reset link'
      } catch {
        error.value = 'Failed to send reset link'
      }
    }
  } catch {
    error.value = 'Network error. Please try again.'
  } finally {
    loading.value = false
  }
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
  max-width: 450px;
  width: 100%;
}

.login-card h1 {
  text-align: center;
  margin: 0 0 10px 0;
  color: #333;
  font-weight: 700;
  font-size: 1.6em;
}

.subtitle {
  text-align: center;
  color: #666;
  font-size: 0.95em;
  margin: 0 0 24px 0;
  line-height: 1.5;
}

.login-form {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.form-group label {
  font-weight: 500;
  color: #333;
  font-size: 0.9em;
}

.auth-error {
  padding: 12px;
  background: #fee;
  border: 1px solid #fcc;
  border-radius: 6px;
  color: #c33;
  text-align: center;
  font-size: 0.9em;
}

.btn-primary:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.success-message {
  text-align: center;
  padding: 20px 0;
}

.icon-wrapper {
  display: flex;
  justify-content: center;
  margin-bottom: 16px;
}

.icon-wrapper svg {
  width: 60px;
  height: 60px;
  color: #667eea;
}

.success-message h2 {
  color: #333;
  font-size: 1.4em;
  margin: 0 0 12px 0;
}

.success-message p {
  color: #555;
  line-height: 1.6;
  margin: 0 0 12px 0;
}

.success-message .btn {
  margin-top: 12px;
}
</style>
