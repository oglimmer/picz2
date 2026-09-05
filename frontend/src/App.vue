<template>
  <div class="container">
    <StorageFullBanner v-if="isLoggedIn" />
    <router-view />
    <ToastNotifications />
    <ConfirmDialog />
    <footer class="app-footer">
      <template v-if="isLoggedIn">
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
        <span class="footer-separator">|</span>
      </template>
      <span class="version-info">
        Frontend v{{ frontendVersion }} ({{ frontendCommit }}) &middot; Backend v{{ backendVersion }} ({{ backendCommit }})
      </span>
    </footer>
  </div>
</template>

<script setup lang="ts">
import { onMounted, watch } from 'vue'
import { useAuth } from './composables/useAuth'
import { useTags } from './composables/useTags'
import { useVersion } from './composables/useVersion'
import { useStorageUsage } from './composables/useStorageUsage'
import ToastNotifications from './components/ToastNotifications.vue'
import ConfirmDialog from './components/ConfirmDialog.vue'
import StorageFullBanner from './components/StorageFullBanner.vue'

const { isLoggedIn } = useAuth()
const { loadTags } = useTags()
const { frontendVersion, frontendCommit, backendVersion, backendCommit } = useVersion()
const { startPolling, stopPolling } = useStorageUsage()

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

/**
 * The "storage full" banner follows the session: polling starts on sign-in (or on a hard refresh
 * with a live session) and stops, taking the banner down, on sign-out.
 */
watch(isLoggedIn, (loggedIn) => (loggedIn ? startPolling() : stopPolling()), { immediate: true })
</script>
