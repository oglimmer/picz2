<template>
  <div
    v-if="storageFull"
    class="storage-full-banner"
    role="alert"
    aria-live="assertive"
  >
    <span
      class="storage-full-banner__icon"
      aria-hidden="true"
    >⚠</span>
    <span class="storage-full-banner__text">
      <strong>Your storage on this site is full.</strong>
      New photos cannot be uploaded until you free some space or
      <router-link to="/profile">add your own storage</router-link>.
    </span>
  </div>
</template>

<script setup lang="ts">
/**
 * Persistent warning while uploads to the site's own storage are refused (507). Deliberately has
 * no close button and remembers nothing: it goes away exactly when the server says there is room
 * again, and not before — a dismissed warning would leave the user wondering why the next upload
 * fails.
 */
import { useStorageUsage } from '../composables/useStorageUsage'

const { storageFull } = useStorageUsage()
</script>

<style scoped>
.storage-full-banner {
  position: sticky;
  top: 0;
  z-index: 1100;
  display: flex;
  align-items: center;
  gap: var(--sp-3);
  padding: var(--sp-3) var(--sp-4);
  background: var(--c-warn-soft);
  color: var(--c-text);
  border-bottom: 2px solid var(--c-warn);
  font-family: var(--f-body);
  font-size: 0.95rem;
  line-height: 1.4;
}

.storage-full-banner__icon {
  color: var(--c-warn);
  font-size: 1.25rem;
  flex-shrink: 0;
}

.storage-full-banner a {
  color: var(--c-accent);
  text-decoration: underline;
}
</style>
