<template>
  <div
    v-if="show"
    class="dialog-overlay"
    @click.self="close"
  >
    <div class="dialog">
      <div class="dialog-header">
        <h3>{{ isConfirmation ? 'Subscription Confirmed!' : 'Subscribe to Album Updates' }}</h3>
        <button
          class="close-btn"
          @click="close"
        >
          ×
        </button>
      </div>

      <div
        v-if="isConfirmation"
        class="dialog-content"
      >
        <p class="success-message">
          ✓ Your subscription has been confirmed successfully!
        </p>
        <p>You will receive email notifications based on your preferences.</p>
        <div class="dialog-actions">
          <button
            class="btn btn-primary"
            @click="close"
          >
            Close
          </button>
        </div>
      </div>

      <div
        v-else
        class="dialog-content"
      >
        <p>Stay updated when new content is added to <strong>{{ albumName }}</strong></p>

        <form @submit.prevent="handleSubmit">
          <div class="form-group">
            <label for="subscription-email">Email Address</label>
            <input
              id="subscription-email"
              v-model="formData.email"
              type="email"
              placeholder="your.email@example.com"
              required
              :disabled="loading"
            >
          </div>

          <div class="form-group checkbox-group">
            <label class="checkbox-label">
              <input
                v-model="formData.notifyAlbumUpdates"
                type="checkbox"
                :disabled="loading"
              >
              <span>Notify me when new images are added to this album</span>
            </label>
          </div>

          <div class="form-group checkbox-group">
            <label class="checkbox-label">
              <input
                v-model="formData.notifyNewAlbums"
                type="checkbox"
                :disabled="loading"
              >
              <span>Also notify me when the album owner creates new albums</span>
            </label>
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
          >
            {{ success }}
          </div>

          <div class="dialog-actions">
            <button
              type="button"
              class="btn btn-secondary"
              :disabled="loading"
              @click="close"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="btn btn-primary"
              :disabled="loading || (!formData.notifyAlbumUpdates && !formData.notifyNewAlbums)"
            >
              {{ loading ? 'Subscribing...' : 'Subscribe' }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script>
import { ref, reactive, watch } from 'vue'
import { useApi } from '../composables/useApi'

export default {
  name: 'SubscriptionDialog',
  props: {
    show: {
      type: Boolean,
      default: false
    },
    shareToken: {
      type: String,
      required: true
    },
    albumName: {
      type: String,
      default: 'this album'
    },
    isConfirmation: {
      type: Boolean,
      default: false
    }
  },
  emits: ['close', 'subscribed'],
  setup(props, { emit }) {
    const { apiUrl } = useApi()
    const loading = ref(false)
    const error = ref('')
    const success = ref('')

    const formData = reactive({
      email: '',
      notifyAlbumUpdates: true,
      notifyNewAlbums: false
    })

    // Reset form when dialog is closed
    watch(() => props.show, (newValue) => {
      if (!newValue) {
        resetForm()
      }
    })

    function resetForm() {
      formData.email = ''
      formData.notifyAlbumUpdates = true
      formData.notifyNewAlbums = false
      error.value = ''
      success.value = ''
    }

    async function handleSubmit() {
      error.value = ''
      success.value = ''

      if (!formData.notifyAlbumUpdates && !formData.notifyNewAlbums) {
        error.value = 'Please select at least one notification option'
        return
      }

      loading.value = true

      try {
        const response = await fetch(`${apiUrl}/api/public/subscriptions/albums/${props.shareToken}`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            email: formData.email,
            notifyAlbumUpdates: formData.notifyAlbumUpdates,
            notifyNewAlbums: formData.notifyNewAlbums
          })
        })

        const data = await response.json()

        if (response.ok) {
          success.value = data.message || 'Subscription created! Please check your email to confirm.'
          emit('subscribed')

          // Close dialog after 3 seconds
          setTimeout(() => {
            close()
          }, 3000)
        } else {
          error.value = data.message || 'Failed to create subscription. Please try again.'
        }
      } catch (err) {
        console.error('Subscription error:', err)
        error.value = 'An error occurred. Please try again later.'
      } finally {
        loading.value = false
      }
    }

    function close() {
      emit('close')
    }

    return {
      formData,
      loading,
      error,
      success,
      handleSubmit,
      close
    }
  }
}
</script>

<style scoped>
.dialog-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(0, 0, 0, 0.7);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  padding: 20px;
}

.dialog {
  background: white;
  border-radius: 8px;
  max-width: 500px;
  width: 100%;
  max-height: 90vh;
  overflow-y: auto;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
}

.dialog-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 20px;
  border-bottom: 1px solid #e0e0e0;
}

.dialog-header h3 {
  margin: 0;
  font-size: 1.25rem;
  color: #333;
}

.close-btn {
  background: none;
  border: none;
  font-size: 2rem;
  line-height: 1;
  cursor: pointer;
  color: #666;
  padding: 0;
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.close-btn:hover {
  color: #333;
}

.dialog-content {
  padding: 20px;
}

.dialog-content p {
  margin-bottom: 20px;
  color: #555;
}

.form-group {
  margin-bottom: 20px;
}

.form-group label {
  display: block;
  margin-bottom: 8px;
  font-weight: 500;
  color: #333;
}

.form-group input[type="email"] {
  width: 100%;
  padding: 10px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 1rem;
  box-sizing: border-box;
}

.form-group input[type="email"]:focus {
  outline: none;
  border-color: #4CAF50;
}

.checkbox-group {
  margin-bottom: 15px;
}

.checkbox-label {
  display: flex;
  align-items: start;
  cursor: pointer;
  font-weight: normal;
}

.checkbox-label input[type="checkbox"] {
  margin-right: 10px;
  margin-top: 2px;
  cursor: pointer;
}

.checkbox-label span {
  color: #555;
}

.error-message {
  padding: 12px;
  background-color: #ffebee;
  color: #c62828;
  border-radius: 4px;
  margin-bottom: 16px;
}

.success-message {
  padding: 12px;
  background-color: #e8f5e9;
  color: #2e7d32;
  border-radius: 4px;
  margin-bottom: 16px;
}

.dialog-actions {
  display: flex;
  gap: 12px;
  justify-content: flex-end;
  margin-top: 20px;
}

.btn {
  padding: 10px 20px;
  border: none;
  border-radius: 4px;
  font-size: 1rem;
  cursor: pointer;
  transition: all 0.2s;
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn-primary {
  background-color: #4CAF50;
  color: white;
}

.btn-primary:hover:not(:disabled) {
  background-color: #45a049;
}

.btn-secondary {
  background-color: #f5f5f5;
  color: #333;
}

.btn-secondary:hover:not(:disabled) {
  background-color: #e0e0e0;
}
</style>
