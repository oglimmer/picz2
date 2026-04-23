<template>
  <div class="subscription-confirm-view">
    <div class="confirm-card">
      <div v-if="loading" class="loading-state">
        <div class="spinner"></div>
        <p>Confirming your subscription...</p>
      </div>

      <div v-else-if="error" class="error-state">
        <div class="icon">❌</div>
        <h2>Confirmation Failed</h2>
        <p>{{ error }}</p>
        <p class="help-text">
          The confirmation link may have expired or is invalid. Please try subscribing again.
        </p>
      </div>

      <div v-else-if="success" class="success-state">
        <div class="icon">✓</div>
        <h2>Subscription Confirmed!</h2>
        <p>{{ success }}</p>
        <p class="info-text">
          You will now receive email notifications based on your preferences.
        </p>
        <div v-if="albumName" class="album-info">
          <p>Subscribed to: <strong>{{ albumName }}</strong></p>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useApi } from '../composables/useApi'

export default {
  name: 'SubscriptionConfirmView',
  setup() {
    const route = useRoute()
    const { apiUrl } = useApi()

    const loading = ref(true)
    const error = ref('')
    const success = ref('')
    const albumName = ref('')

    onMounted(async () => {
      const token = route.query.token

      if (!token) {
        error.value = 'No confirmation token provided'
        loading.value = false
        return
      }

      try {
        const response = await fetch(`${apiUrl}/api/public/subscriptions/confirm?token=${token}`)
        const data = await response.json()

        if (response.ok) {
          success.value = data.message || 'Your subscription has been confirmed successfully!'
          // You could extract album name from response if needed
        } else {
          error.value = data.message || 'Failed to confirm subscription'
        }
      } catch (err) {
        console.error('Confirmation error:', err)
        error.value = 'An error occurred while confirming your subscription. Please try again later.'
      } finally {
        loading.value = false
      }
    })

    return {
      loading,
      error,
      success,
      albumName
    }
  }
}
</script>
