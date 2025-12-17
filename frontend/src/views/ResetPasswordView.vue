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

      <div v-if="!success">
        <h1>Create New Password</h1>
        <p class="subtitle">
          Enter your new password below.
        </p>

        <form
          class="login-form"
          @submit.prevent="handleSubmit"
        >
          <div class="form-group">
            <label for="password">New Password</label>
            <input
              id="password"
              v-model="password"
              type="password"
              placeholder="Enter new password (min 8 chars)"
              class="auth-input"
              required
              minlength="8"
              autofocus
            >
          </div>

          <div class="form-group">
            <label for="confirm">Confirm Password</label>
            <input
              id="confirm"
              v-model="confirm"
              type="password"
              placeholder="Re-enter your password"
              class="auth-input"
              required
              minlength="8"
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
            {{ loading ? 'Resetting...' : 'Reset Password' }}
          </button>
        </form>
      </div>

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
            <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
            <polyline points="22 4 12 14.01 9 11.01" />
          </svg>
        </div>

        <h2>Password Reset Successful!</h2>
        <p>
          Your password has been successfully reset. You can now log in with your new password.
        </p>

        <router-link
          to="/login"
          class="btn btn-primary"
        >
          Go to Login
        </router-link>
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

const password = ref('')
const confirm = ref('')
const loading = ref(false)
const error = ref('')
const success = ref(false)
const token = ref('')

onMounted(() => {
  document.body.classList.add('landing-page')
  token.value = route.query.token as string

  if (!token.value) {
    error.value = 'Invalid or missing reset token'
  }
})

onUnmounted(() => {
  document.body.classList.remove('landing-page')
})

async function handleSubmit() {
  error.value = ''

  if (!password.value || !confirm.value) {
    error.value = 'Both password fields are required'
    return
  }

  if (password.value.length < 8) {
    error.value = 'Password must be at least 8 characters long'
    return
  }

  if (password.value !== confirm.value) {
    error.value = 'Passwords do not match'
    return
  }

  if (!token.value) {
    error.value = 'Invalid or missing reset token'
    return
  }

  loading.value = true
  try {
    const res = await fetch(`${apiUrl}/api/users/password-reset`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        token: token.value,
        newPassword: password.value
      })
    })

    if (res.ok) {
      success.value = true
    } else {
      try {
        const err = await res.json()
        error.value = err?.message || 'Failed to reset password. The link may have expired.'
      } catch {
        error.value = 'Failed to reset password. The link may have expired.'
      }
    }
  } catch {
    error.value = 'Network error. Please try again.'
  } finally {
    loading.value = false
  }
}
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
  color: #10b981;
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
