<template>
  <MenuButton
    class="masthead-account"
    align="right"
    role="menu"
  >
    <template #trigger="{ open, toggle }">
      <button
        class="account-btn"
        aria-haspopup="menu"
        :aria-expanded="open"
        @click="toggle"
      >
        <span class="account-name">{{ authEmail || 'Account' }}</span>
        <svg
          class="chev"
          width="9"
          height="9"
          viewBox="0 0 10 10"
          fill="none"
          stroke="currentColor"
          stroke-width="1.6"
        >
          <path d="M2 4l3 3 3-3" />
        </svg>
      </button>
    </template>

    <template #default="{ close }">
      <!-- Page-local group (library settings, album settings) goes above the account group. -->
      <slot :close="close" />
      <div
        v-if="$slots.default"
        class="popover-sep"
      />
      <p class="popover-head">
        Account
      </p>
      <button
        class="menu-item"
        role="menuitem"
        @click="close(); goToProfile()"
      >
        <span class="menu-item-label">Profile &amp; password</span>
      </button>
      <button
        class="menu-item menu-item--danger"
        role="menuitem"
        @click="close(); handleSignOut()"
      >
        <span class="menu-item-label">Sign out</span>
      </button>
    </template>
  </MenuButton>
</template>

<script setup lang="ts">
import { useRouter } from 'vue-router'
import { useAuth } from '@/composables/useAuth'
import MenuButton from './MenuButton.vue'

const router = useRouter()
const { authEmail, logout } = useAuth()

function goToProfile() {
  router.push({ name: 'Profile' })
}

function handleSignOut() {
  logout()
  router.push({ name: 'Login' })
}
</script>
