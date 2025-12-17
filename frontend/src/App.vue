<template>
  <div class="container">
    <router-view />
    <ToastNotifications />
    <ConfirmDialog />
    <div
      v-if="isLoggedIn"
      class="footer-links"
    >
      <router-link to="/imprint">
        Imprint
      </router-link>
      <span class="footer-separator">|</span>
      <router-link to="/privacy">
        Privacy Policy
      </router-link>
      <span class="footer-separator">|</span>
      <router-link to="/terms">
        Terms of Service
      </router-link>
    </div>
    <div class="version-info">
      <span>
        Frontend v{{ frontendVersion }} ({{ frontendCommit }}) | Backend v{{ backendVersion }} ({{ backendCommit }})
      </span>
    </div>
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue'
import { useAuth } from './composables/useAuth'
import { useTags } from './composables/useTags'
import { useVersion } from './composables/useVersion'
import ToastNotifications from './components/ToastNotifications.vue'
import ConfirmDialog from './components/ConfirmDialog.vue'

const { isLoggedIn } = useAuth()
const { loadTags } = useTags()
const { frontendVersion, frontendCommit, backendVersion, backendCommit } = useVersion()

/**
 * Load app data on mount if logged in
 */
onMounted(async () => {
  // Auth is already initialized in main.ts before app mount
  // Load initial data if logged in
  if (isLoggedIn.value) {
    await loadTags()
  }
})
</script>
