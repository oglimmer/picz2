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

<style scoped>
.subscription-confirm-view {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
}

.confirm-card {
  background: white;
  border-radius: 12px;
  padding: 40px;
  max-width: 500px;
  width: 100%;
  box-shadow: 0 10px 40px rgba(0, 0, 0, 0.2);
  text-align: center;
}

.loading-state,
.error-state,
.success-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 20px;
}

.spinner {
  width: 50px;
  height: 50px;
  border: 4px solid #f3f3f3;
  border-top: 4px solid #667eea;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}

.icon {
  font-size: 4rem;
  line-height: 1;
}

.success-state .icon {
  color: #4CAF50;
}

.error-state .icon {
  color: #f44336;
}

h2 {
  margin: 0;
  font-size: 1.75rem;
  color: #333;
}

p {
  margin: 0;
  color: #666;
  line-height: 1.6;
}

.help-text {
  font-size: 0.9rem;
  color: #999;
}

.info-text {
  color: #555;
}

.album-info {
  margin-top: 20px;
  padding: 15px;
  background-color: #f5f5f5;
  border-radius: 8px;
}

.album-info strong {
  color: #333;
}
</style>
