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
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useApi } from '@/composables/useApi'

const route = useRoute()
const { apiUrl, requestPublicJson } = useApi()

const loading = ref(true)
const error = ref('')
const success = ref('')

onMounted(async () => {
  const token = typeof route.query.token === 'string' ? route.query.token : ''

  if (!token) {
    error.value = 'No confirmation token provided'
    loading.value = false
    return
  }

  try {
    const data = await requestPublicJson<{ message?: string }>(
      `${apiUrl}/api/public/subscriptions/confirm?token=${encodeURIComponent(token)}`
    )
    success.value = data.message || 'Your subscription has been confirmed successfully!'
  } catch (err) {
    error.value = err instanceof Error && err.message
      ? err.message
      : 'An error occurred while confirming your subscription. Please try again later.'
  } finally {
    loading.value = false
  }
})
</script>
