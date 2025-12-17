<template>
  <div class="language-management-panel">
    <h3>Manage Languages</h3>

    <div class="language-list">
      <div class="language-item">
        <div class="language-display">
          <span class="language-label">Language 1:</span>
          <input
            v-model="localLanguage1Name"
            class="language-input"
            :disabled="updating"
            placeholder="e.g., German"
            @blur="handleUpdateLanguage1"
            @keyup.enter="handleUpdateLanguage1"
          >
        </div>
      </div>

      <div class="language-item">
        <div class="language-display">
          <span class="language-label">Language 2:</span>
          <input
            v-model="localLanguage2Name"
            class="language-input"
            :disabled="updating"
            placeholder="e.g., English"
            @blur="handleUpdateLanguage2"
            @keyup.enter="handleUpdateLanguage2"
          >
        </div>
      </div>
    </div>

    <div
      v-if="error"
      class="error-message"
    >
      {{ error }}
    </div>
    <div
      v-if="success"
      class="success-message"
      role="status"
    >
      {{ success }}
    </div>

    <div class="form-actions">
      <button
        class="btn-secondary"
        @click="emit('close')"
      >
        Close
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
import { useSettings } from '@/composables/useSettings'

const emit = defineEmits(['close'])

const {
  language1Name,
  language2Name,
  updateLanguage1Name,
  updateLanguage2Name
} = useSettings()

const localLanguage1Name = ref(language1Name.value)
const localLanguage2Name = ref(language2Name.value)
const updating = ref(false)
const error = ref<string | null>(null)
const success = ref<string | null>(null)

// Watch for changes in the composable values
watch(language1Name, (newValue) => {
  localLanguage1Name.value = newValue
})

watch(language2Name, (newValue) => {
  localLanguage2Name.value = newValue
})

async function handleUpdateLanguage1() {
  if (localLanguage1Name.value.trim() === '') {
    error.value = 'Language 1 name cannot be empty'
    localLanguage1Name.value = language1Name.value
    return
  }

  if (localLanguage1Name.value === language1Name.value) {
    return // No change
  }

  updating.value = true
  error.value = null
  success.value = null

  try {
    await updateLanguage1Name(localLanguage1Name.value)
    success.value = 'Language 1 name updated successfully!'
    setTimeout(() => {
      success.value = null
    }, 3000)
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    error.value = `Failed to update Language 1: ${message}`
    localLanguage1Name.value = language1Name.value
  } finally {
    updating.value = false
  }
}

async function handleUpdateLanguage2() {
  if (localLanguage2Name.value.trim() === '') {
    error.value = 'Language 2 name cannot be empty'
    localLanguage2Name.value = language2Name.value
    return
  }

  if (localLanguage2Name.value === language2Name.value) {
    return // No change
  }

  updating.value = true
  error.value = null
  success.value = null

  try {
    await updateLanguage2Name(localLanguage2Name.value)
    success.value = 'Language 2 name updated successfully!'
    setTimeout(() => {
      success.value = null
    }, 3000)
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    error.value = `Failed to update Language 2: ${message}`
    localLanguage2Name.value = language2Name.value
  } finally {
    updating.value = false
  }
}
</script>
