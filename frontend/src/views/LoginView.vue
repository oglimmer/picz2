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
      <h1>Sign In</h1>

      <form
        class="login-form"
        @submit.prevent="handleLogin"
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
            placeholder="Enter your password"
            class="auth-input"
            required
          >
          <div class="forgot-password-link">
            <router-link to="/forgot-password">
              Forgot password?
            </router-link>
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
          :disabled="loading"
        >
          {{ loading ? 'Signing in...' : 'Sign In' }}
        </button>

        <div style="text-align:center; margin-top: 8px; font-size: 0.95em;">
          No account yet?
          <router-link to="/register">
            Create one
          </router-link>
        </div>
      </form>
    </div>
  </div>
</template>

<script setup lang="ts">
import {ref, computed, onMounted, onUnmounted} from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuth } from '../composables/useAuth'

const router = useRouter()
const route = useRoute()
const { authEmail, authPassword, loginError, login } = useAuth()

const email = computed({
  get: () => authEmail.value,
  set: (value: string) => authEmail.value = value
})

const password = computed({
  get: () => authPassword.value,
  set: (value: string) => authPassword.value = value
})

const error = computed(() => loginError.value)
const loading = ref(false)

async function handleLogin() {
  loading.value = true
  const success = await login()
  loading.value = false

  if (success) {
    // Redirect to the page they were trying to access, or albums
    const redirect = (route.query.redirect as string) || '/albums'
    router.push(redirect)
  }
}

onMounted(() => {
  document.body.classList.add('landing-page')
})

onUnmounted(() => {
  document.body.classList.remove('landing-page')
})
</script>
