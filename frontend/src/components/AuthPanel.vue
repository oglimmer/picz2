<template>
  <div class="auth-panel">
    <template v-if="!isLoggedIn">
      <input
        v-model="email"
        type="email"
        placeholder="Email"
        class="auth-input"
      >
      <input
        v-model="password"
        type="password"
        placeholder="Password"
        class="auth-input"
        @keyup.enter="handleLogin"
      >
      <button
        class="btn-primary"
        @click="handleLogin"
      >
        Login
      </button>
      <div
        v-if="error"
        class="auth-error"
      >
        {{ error }}
      </div>
    </template>
    <template v-else>
      <span class="auth-user">🔐 {{ email }}</span>
      <button
        class="btn-secondary"
        @click="handleLogout"
      >
        Logout
      </button>
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useAuth } from '@/composables/useAuth'

const emit = defineEmits<{
  'login-success': []
}>()

const { authEmail, authPassword, isLoggedIn, loginError, login, logout } = useAuth()

const email = computed({
  get: () => authEmail.value,
  set: (value: string) => authEmail.value = value
})

const password = computed({
  get: () => authPassword.value,
  set: (value: string) => authPassword.value = value
})

const error = computed(() => loginError.value)

async function handleLogin() {
  const success = await login()
  if (success) {
    emit('login-success')
  }
}

function handleLogout() {
  logout()
}
</script>
