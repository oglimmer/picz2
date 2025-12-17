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

.forgot-password-link {
  text-align: right;
  margin-top: 4px;
}

.forgot-password-link a {
  color: #667eea;
  text-decoration: none;
  font-size: 0.9em;
}

.forgot-password-link a:hover {
  text-decoration: underline;
}
</style>
