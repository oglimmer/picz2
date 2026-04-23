<template>
  <Teleport to="body">
    <Transition name="dialog">
      <div
        v-if="currentDialog"
        class="dialog-overlay"
        @click="handleCancel"
      >
        <div
          class="dialog-container"
          @click.stop
        >
          <div :class="['dialog', `dialog-${currentDialog.type}`]">
            <div class="dialog-icon">
              <svg
                v-if="currentDialog.type === 'danger'"
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="currentColor"
              >
                <path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z" />
              </svg>
              <svg
                v-else-if="currentDialog.type === 'info'"
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="currentColor"
              >
                <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z" />
              </svg>
              <svg
                v-else
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="currentColor"
              >
                <path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z" />
              </svg>
            </div>

            <div class="dialog-content">
              <p class="dialog-message">
                {{ currentDialog.message }}
              </p>
            </div>

            <div class="dialog-actions">
              <button
                class="dialog-button dialog-button-cancel"
                @click="handleCancel"
                @keydown.enter.prevent="handleCancel"
              >
                {{ currentDialog.cancelText }}
              </button>
              <button
                ref="confirmButton"
                class="dialog-button dialog-button-confirm"
                @click="handleConfirm"
                @keydown.enter.prevent="handleConfirm"
              >
                {{ currentDialog.confirmText }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { watch, nextTick, ref } from 'vue'
import { useConfirm } from '../composables/useConfirm'

const { currentDialog, resolveDialog } = useConfirm()
const confirmButton = ref<HTMLButtonElement>()

const handleConfirm = () => {
  resolveDialog(true)
}

const handleCancel = () => {
  resolveDialog(false)
}

// Handle keyboard shortcuts
const handleKeydown = (e: KeyboardEvent) => {
  if (!currentDialog.value) return

  if (e.key === 'Escape') {
    handleCancel()
  } else if (e.key === 'Enter' && !e.shiftKey) {
    handleConfirm()
  }
}

// Watch for dialog changes to manage keyboard listeners and focus
watch(currentDialog, async (dialog) => {
  if (dialog) {
    document.addEventListener('keydown', handleKeydown)
    // Focus the confirm button when dialog opens
    await nextTick()
    confirmButton.value?.focus()
  } else {
    document.removeEventListener('keydown', handleKeydown)
  }
})
</script>
