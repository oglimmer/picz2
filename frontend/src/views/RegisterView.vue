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
          <router-link to="/privacy">
            Privacy
          </router-link>
          <router-link to="/imprint">
            Imprint
          </router-link>
        </nav>
      </header>
      <h1>Create Account</h1>

      <form
        class="login-form"
        @submit.prevent="handleRegister"
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

        <div class="form-group">
          <label for="password">Password</label>
          <input
            id="password"
            v-model="password"
            type="password"
            placeholder="Create a password (min 8 chars)"
            class="auth-input"
            required
            minlength="8"
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

        <div class="consent-section">
          <div class="consent-group">
            <label class="checkbox-label">
              <input
                v-model="acceptTerms"
                type="checkbox"
                class="consent-checkbox"
                required
              >
              <span class="checkbox-text">
                I accept the
                <router-link
                  to="/terms"
                  target="_blank"
                  class="policy-link"
                >
                  Terms and Conditions
                </router-link>
              </span>
            </label>
          </div>

          <div class="consent-group">
            <label class="checkbox-label">
              <input
                v-model="acceptPrivacy"
                type="checkbox"
                class="consent-checkbox"
                required
              >
              <span class="checkbox-text">
                I have read and accept the
                <router-link
                  to="/privacy"
                  target="_blank"
                  class="policy-link"
                >
                  Privacy Policy
                </router-link>
              </span>
            </label>
          </div>
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
          :disabled="loading || !acceptTerms || !acceptPrivacy"
        >
          {{ loading ? 'Creating account...' : 'Create Account' }}
        </button>

        <div style="text-align:center; margin-top: 8px; font-size: 0.95em;">
          Already have an account?
          <router-link to="/login">
            Sign in
          </router-link>
        </div>
      </form>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useApi } from '../composables/useApi'

const router = useRouter()
const { apiUrl } = useApi()

const email = ref('')
const password = ref('')
const confirm = ref('')
const acceptTerms = ref(false)
const acceptPrivacy = ref(false)
const loading = ref(false)
const error = ref('')

async function handleRegister() {
  error.value = ''
  if (!email.value || !password.value) {
    error.value = 'Email and password are required'
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
  if (!acceptTerms.value || !acceptPrivacy.value) {
    error.value = 'You must accept the Terms and Conditions and Privacy Policy'
    return
  }

  loading.value = true
  try {
    const res = await fetch(`${apiUrl}/api/users`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: email.value, password: password.value })
    })

    if (!res.ok) {
      try {
        const err = await res.json()
        error.value = err?.message || 'Failed to create account'
      } catch {
        error.value = 'Failed to create account'
      }
      return
    }

    // Redirect to verification pending page
    router.push('/verification-pending')
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
  max-width: 400px;
  width: 100%;
}

.login-card h1 {
  text-align: center;
  margin: 0 0 20px 0;
  color: #333;
  font-weight: 700;
  font-size: 1.6em;
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

.btn-primary:disabled {
  opacity: 0.6;
  cursor: not-allowed;
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

.consent-section {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px;
  background: #f9fafb;
  border-radius: 8px;
  border: 1px solid #e5e7eb;
}

.consent-group {
  display: flex;
  align-items: flex-start;
}

.checkbox-label {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  cursor: pointer;
  user-select: none;
  line-height: 1.5;
}

.consent-checkbox {
  margin-top: 3px;
  cursor: pointer;
  width: 18px;
  height: 18px;
  flex-shrink: 0;
}

.checkbox-text {
  font-size: 0.9em;
  color: #374151;
}

.policy-link {
  color: #667eea;
  text-decoration: none;
  font-weight: 500;
}

.policy-link:hover {
  text-decoration: underline;
}

.btn-primary:disabled {
  background: #cbd5e1 !important;
  cursor: not-allowed;
}
</style>
