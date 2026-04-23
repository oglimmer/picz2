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
