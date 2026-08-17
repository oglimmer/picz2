<template>
  <header class="group-header">
    <div class="group-header-bar" />
    <div class="group-header-main">
      <div class="group-header-title">
        <h3 class="group-label">
          {{ group.label }}
        </h3>
        <span class="group-count">{{ count }} {{ count === 1 ? 'photo' : 'photos' }}</span>
        <div
          v-if="editable"
          class="group-header-actions"
        >
          <button
            class="group-action-btn"
            title="Edit group label and text"
            @click="$emit('edit', group)"
          >
            ✎ Edit
          </button>
          <button
            class="group-action-btn group-action-btn-danger"
            title="Remove this group (photos stay where they are)"
            @click="$emit('delete', group)"
          >
            🗑️ Remove
          </button>
        </div>
      </div>
      <p
        v-if="group.text"
        class="group-text"
      >
        {{ group.text }}
      </p>
    </div>
  </header>
</template>

<script setup lang="ts">
import type { PresentationGroup } from '@/types'

interface Props {
  group: PresentationGroup
  count: number
  editable?: boolean
}

withDefaults(defineProps<Props>(), {
  editable: false
})

defineEmits<{
  edit: [group: PresentationGroup]
  delete: [group: PresentationGroup]
}>()
</script>

<style scoped>
.group-header {
  display: flex;
  gap: var(--sp-4);
  padding: var(--sp-6) var(--sp-8) var(--sp-3);
}

/* Thin accent rule that ties the heading to the photos underneath it. */
.group-header-bar {
  flex: 0 0 3px;
  border-radius: var(--r-full);
  background: var(--c-accent);
  opacity: .75;
}

.group-header-main {
  flex: 1 1 auto;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: var(--sp-2);
}

.group-header-title {
  display: flex;
  align-items: baseline;
  flex-wrap: wrap;
  gap: var(--sp-3);
}

.group-label {
  font-family: var(--f-display);
  font-size: 1.375rem;
  font-weight: 600;
  line-height: 1.25;
  color: var(--c-text);
  overflow-wrap: anywhere;
}

.group-count {
  flex: 0 0 auto;
  padding: 2px var(--sp-2);
  border-radius: var(--r-full);
  background: var(--c-surface-alt);
  color: var(--c-text-3);
  font-size: .75rem;
  font-weight: 500;
  white-space: nowrap;
}

.group-header-actions {
  margin-left: auto;
  display: flex;
  gap: var(--sp-2);
}

.group-action-btn {
  padding: 4px var(--sp-3);
  background: var(--c-surface);
  color: var(--c-text-2);
  border: 1px solid var(--c-border);
  border-radius: var(--r-full);
  font-family: var(--f-body);
  font-size: .75rem;
  font-weight: 500;
  cursor: pointer;
  white-space: nowrap;
  transition: color var(--t-fast), border-color var(--t-fast), background var(--t-fast);
}
.group-action-btn:hover {
  color: var(--c-accent);
  border-color: var(--c-accent);
  background: var(--c-accent-soft);
}
.group-action-btn-danger:hover {
  color: var(--c-danger);
  border-color: var(--c-danger);
  background: var(--c-danger-soft);
}

.group-text {
  max-width: 68ch;
  color: var(--c-text-2);
  font-size: .9375rem;
  line-height: 1.6;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

@media (max-width: 768px) {
  .group-header { padding: var(--sp-5) var(--sp-4) var(--sp-2); }
  .group-label { font-size: 1.125rem; }
  .group-header-actions { margin-left: 0; }
}
</style>
