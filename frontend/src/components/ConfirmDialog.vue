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

<style scoped>
.dialog-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.6);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 10001;
  padding: 20px;
}

.dialog-container {
  max-width: 500px;
  width: 100%;
}

.dialog {
  background: white;
  border-radius: 12px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.dialog-icon {
  padding: 24px 24px 0 24px;
  display: flex;
  justify-content: center;
  width: 64px;
  height: 64px;
  margin: 0 auto;
}

.dialog-icon svg {
  width: 64px;
  height: 64px;
}

.dialog-danger .dialog-icon {
  color: #ef4444;
}

.dialog-warning .dialog-icon {
  color: #f59e0b;
}

.dialog-info .dialog-icon {
  color: #3b82f6;
}

.dialog-content {
  padding: 24px;
  text-align: center;
}

.dialog-message {
  margin: 0;
  font-size: 16px;
  line-height: 1.6;
  color: #1f2937;
}

.dialog-actions {
  padding: 0 24px 24px 24px;
  display: flex;
  gap: 12px;
  justify-content: flex-end;
}

.dialog-button {
  padding: 10px 20px;
  border-radius: 8px;
  font-size: 14px;
  font-weight: 500;
  border: none;
  cursor: pointer;
  transition: all 0.2s;
  min-width: 100px;
}

.dialog-button:focus {
  outline: none;
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.3);
}

.dialog-button-cancel {
  background: #f3f4f6;
  color: #6b7280;
}

.dialog-button-cancel:hover {
  background: #e5e7eb;
  color: #4b5563;
}

.dialog-button-confirm {
  background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
  color: white;
}

.dialog-button-confirm:hover {
  background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%);
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(37, 99, 235, 0.4);
}

.dialog-danger .dialog-button-confirm {
  background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
}

.dialog-danger .dialog-button-confirm:hover {
  background: linear-gradient(135deg, #dc2626 0%, #b91c1c 100%);
  box-shadow: 0 4px 12px rgba(239, 68, 68, 0.4);
}

.dialog-warning .dialog-button-confirm {
  background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);
}

.dialog-warning .dialog-button-confirm:hover {
  background: linear-gradient(135deg, #d97706 0%, #b45309 100%);
  box-shadow: 0 4px 12px rgba(245, 158, 11, 0.4);
}

/* Transition animations */
.dialog-enter-active {
  transition: opacity 0.3s ease;
}

.dialog-leave-active {
  transition: opacity 0.2s ease;
}

.dialog-enter-from,
.dialog-leave-to {
  opacity: 0;
}

.dialog-enter-active .dialog-container {
  transition: transform 0.3s cubic-bezier(0.68, -0.55, 0.265, 1.55);
}

.dialog-leave-active .dialog-container {
  transition: transform 0.2s ease;
}

.dialog-enter-from .dialog-container {
  transform: scale(0.9);
}

.dialog-leave-to .dialog-container {
  transform: scale(0.95);
}

/* Responsive design */
@media (max-width: 640px) {
  .dialog-overlay {
    padding: 10px;
  }

  .dialog-actions {
    flex-direction: column-reverse;
  }

  .dialog-button {
    width: 100%;
  }
}
</style>
