<template>
  <div
    ref="root"
    class="enhance-review"
    tabindex="-1"
    role="dialog"
    aria-label="Enhance review"
    @keydown="onKeydown"
  >
    <header class="er-head">
      <div class="er-title">
        <strong>Enhance</strong>
        <span
          v-if="review.files.value.length > 1"
          class="er-count"
        >{{ review.index.value + 1 }} of {{ review.files.value.length }}</span>
        <span
          v-if="current"
          class="er-name"
        >{{ current.originalName || current.filename }}</span>
      </div>
      <button
        class="er-close"
        title="Stop reviewing (Esc). Photos not decided keep their original."
        @click="review.cancel()"
      >
        &times;
      </button>
    </header>

    <div
      class="er-stage"
      @pointerdown.prevent="peek(true)"
      @pointerup="peek(false)"
      @pointercancel="peek(false)"
      @pointerleave="peek(false)"
    >
      <img
        v-if="current"
        class="er-img"
        :class="{ 'er-img--hidden': showingEnhanced }"
        :src="originalUrl"
        :alt="current.originalName"
        draggable="false"
      >
      <img
        v-if="review.previewUrl.value"
        class="er-img"
        :class="{ 'er-img--hidden': !showingEnhanced }"
        :src="review.previewUrl.value"
        alt="Enhanced preview"
        draggable="false"
      >
      <div
        v-if="review.loading.value"
        class="er-status"
      >
        <span class="er-spinner" />
        <span>Building the enhanced version…</span>
      </div>
      <div
        v-else-if="review.error.value"
        class="er-status er-status--error"
      >
        {{ review.error.value }}
      </div>
      <span
        v-if="review.previewUrl.value"
        class="er-badge"
      >{{ showingEnhanced ? 'Enhanced' : 'Original' }}</span>
    </div>

    <footer class="er-foot">
      <div
        class="er-segment"
        role="group"
        aria-label="Compare"
      >
        <button
          :class="{ 'is-on': !showingEnhanced }"
          :disabled="!review.previewUrl.value"
          @click="review.show(false)"
        >
          Original
        </button>
        <button
          :class="{ 'is-on': showingEnhanced }"
          :disabled="!review.previewUrl.value"
          @click="review.show(true)"
        >
          Enhanced
        </button>
      </div>
      <p class="er-hint">
        Press and hold the picture to see the original. Space flips, Enter accepts, Backspace declines.
      </p>
      <div class="er-actions">
        <button
          class="er-btn"
          @click="review.decline()"
        >
          {{ review.error.value ? 'Skip' : 'Keep original' }}
        </button>
        <button
          class="er-btn er-btn--primary"
          :disabled="!review.previewUrl.value || review.loading.value"
          @click="review.accept()"
        >
          Use enhanced
        </button>
      </div>
    </footer>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, useTemplateRef } from 'vue'
import { useApi } from '@/composables/useApi'
import type { EnhanceReview } from '@/composables/gallery/useEnhanceReview'

// The state lives in the composable the gallery owns; this component is the picture of it. Two
// pictures at the largest size the server has, stacked, one visible at a time — a crossfade or a
// split would make a small change harder to see, not easier.
const props = defineProps<{ review: EnhanceReview }>()

const { getImageUrl } = useApi()
const root = useTemplateRef<HTMLElement>('root')
const peeking = ref(false)

const current = computed(() => props.review.current.value)
const originalUrl = computed(() => (current.value ? getImageUrl(current.value, 'large') : ''))
const showingEnhanced = computed(
  () => Boolean(props.review.previewUrl.value) && props.review.showEnhanced.value && !peeking.value
)

function peek(on: boolean) {
  if (!props.review.previewUrl.value) return
  peeking.value = on
}

function onKeydown(e: KeyboardEvent) {
  switch (e.key) {
    case ' ':
      e.preventDefault()
      props.review.toggle()
      break
    case 'Enter':
      e.preventDefault()
      void props.review.accept()
      break
    case 'Backspace':
    case 'Delete':
      e.preventDefault()
      void props.review.decline()
      break
    case 'Escape':
      e.preventDefault()
      void props.review.cancel()
      break
  }
}

onMounted(() => root.value?.focus())
</script>

<style scoped>
.enhance-review {
  position: fixed;
  inset: 0;
  z-index: 1100;
  display: flex;
  flex-direction: column;
  background: rgba(10, 5, 2, 0.96);
  color: #f5efe6;
  outline: none;
}
.er-head,
.er-foot {
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  gap: var(--sp-3);
  padding: var(--sp-3) var(--sp-4);
}
.er-head {
  justify-content: space-between;
}
.er-title {
  display: flex;
  align-items: baseline;
  gap: var(--sp-3);
  min-width: 0;
}
.er-count {
  color: var(--c-text-3);
}
.er-name {
  color: var(--c-text-3);
  font-size: 0.85em;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.er-close {
  background: none;
  border: 0;
  color: inherit;
  font-size: 28px;
  line-height: 1;
  cursor: pointer;
  padding: 0 var(--sp-2);
}
.er-stage {
  position: relative;
  flex: 1 1 auto;
  min-height: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  user-select: none;
  touch-action: none;
  cursor: pointer;
}
.er-img {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: contain;
}
.er-img--hidden {
  visibility: hidden;
}
.er-status {
  position: relative;
  display: flex;
  align-items: center;
  gap: var(--sp-2);
  padding: var(--sp-2) var(--sp-4);
  border-radius: 999px;
  background: rgba(0, 0, 0, 0.55);
}
.er-status--error {
  background: rgba(184, 50, 50, 0.85);
}
.er-spinner {
  width: 14px;
  height: 14px;
  border: 2px solid rgba(255, 255, 255, 0.35);
  border-top-color: #fff;
  border-radius: 50%;
  animation: er-spin 0.8s linear infinite;
}
@keyframes er-spin {
  to {
    transform: rotate(360deg);
  }
}
.er-badge {
  position: absolute;
  top: var(--sp-3);
  left: var(--sp-3);
  padding: 2px 10px;
  border-radius: 999px;
  font-size: 12px;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  background: rgba(0, 0, 0, 0.6);
}
.er-foot {
  flex-wrap: wrap;
  justify-content: space-between;
}
.er-segment {
  display: inline-flex;
  border: 1px solid rgba(255, 255, 255, 0.25);
  border-radius: 999px;
  overflow: hidden;
}
.er-segment button {
  background: none;
  border: 0;
  color: inherit;
  padding: 6px 16px;
  cursor: pointer;
  font: inherit;
}
.er-segment button.is-on {
  background: rgba(255, 255, 255, 0.18);
}
.er-segment button:disabled {
  opacity: 0.4;
  cursor: default;
}
.er-hint {
  flex: 1 1 240px;
  margin: 0;
  color: var(--c-text-3);
  font-size: 12px;
  text-align: center;
}
.er-actions {
  display: flex;
  gap: var(--sp-2);
}
.er-btn {
  border: 1px solid rgba(255, 255, 255, 0.35);
  background: none;
  color: inherit;
  border-radius: 8px;
  padding: 8px 16px;
  font: inherit;
  cursor: pointer;
}
.er-btn--primary {
  background: var(--c-accent);
  border-color: var(--c-accent);
  color: #fff;
}
.er-btn:disabled {
  opacity: 0.4;
  cursor: default;
}
@media (max-width: 600px) {
  .er-hint {
    display: none;
  }
}
</style>
