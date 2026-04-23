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
