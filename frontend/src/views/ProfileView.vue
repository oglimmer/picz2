<template>
  <div class="profile-container">
    <div class="profile-card">
      <div class="profile-header">
        <button
          class="back-link"
          @click="goBack"
        >
          ← Back to Albums
        </button>
        <h1>Profile</h1>
      </div>

      <div class="profile-section">
        <h2>Account Information</h2>
        <div class="info-group">
          <label>Email</label>
          <div class="info-value">
            {{ userEmail }}
          </div>
        </div>
      </div>

      <div class="profile-section">
        <h2>Change Password</h2>
        <form
          class="password-form"
          @submit.prevent="handleChangePassword"
        >
          <div class="form-group">
            <label for="current-password">Current Password</label>
            <input
              id="current-password"
              v-model="currentPassword"
              type="password"
              placeholder="Enter current password"
              class="auth-input"
              required
            >
          </div>

          <div class="form-group">
            <label for="new-password">New Password</label>
            <input
              id="new-password"
              v-model="newPassword"
              type="password"
              placeholder="Enter new password (min 8 characters)"
              class="auth-input"
              required
              minlength="8"
            >
          </div>

          <div class="form-group">
            <label for="confirm-password">Confirm New Password</label>
            <input
              id="confirm-password"
              v-model="confirmPassword"
              type="password"
              placeholder="Confirm new password"
              class="auth-input"
              required
            >
          </div>

          <button
            type="submit"
            class="btn btn-primary"
            :disabled="changingPassword"
          >
            {{ changingPassword ? 'Changing Password...' : 'Change Password' }}
          </button>
        </form>
      </div>

      <div class="profile-section danger-section">
        <h2>Danger Zone</h2>

        <div class="danger-actions">
          <div class="action-description">
            <h3>Delete Account</h3>
            <p>Permanently delete your account and all associated data. This action cannot be undone.</p>
          </div>
          <button
            class="btn btn-danger"
            @click="handleDeleteAccount"
            :disabled="deletingAccount"
          >
            {{ deletingAccount ? 'Deleting...' : 'Delete Account' }}
          </button>
        </div>
      </div>

      <div class="profile-actions">
        <button
          class="btn btn-secondary"
          @click="handleLogout"
        >
          Logout
        </button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import { useApi } from '../composables/useApi'
import { useNotifications } from '../composables/useNotifications'
import { useConfirm } from '../composables/useConfirm'

const router = useRouter()
const { authEmail, logout } = useAuth()
const { apiUrl, fetchWithAuth } = useApi()
const { success, error: showError } = useNotifications()
const { confirm: confirmDialog } = useConfirm()

const userEmail = computed(() => authEmail.value)
const currentPassword = ref('')
const newPassword = ref('')
const confirmPassword = ref('')
const changingPassword = ref(false)
const deletingAccount = ref(false)

function goBack() {
  router.push({ name: 'Albums' })
}

async function handleChangePassword() {
  if (newPassword.value !== confirmPassword.value) {
    showError('New passwords do not match')
    return
  }

  if (newPassword.value.length < 8) {
    showError('Password must be at least 8 characters long')
    return
  }

  changingPassword.value = true

  try {
    const response = await fetchWithAuth(`${apiUrl}/api/users/change-password`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        currentPassword: currentPassword.value,
        newPassword: newPassword.value
      })
    })

    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      throw new Error(data.message || 'Failed to change password')
    }

    success('Password changed successfully!')
    currentPassword.value = ''
    newPassword.value = ''
    confirmPassword.value = ''
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    showError(`Error changing password: ${message}`)
  } finally {
    changingPassword.value = false
  }
}

async function handleDeleteAccount() {
  const confirmed = await confirmDialog(
    'Are you sure you want to delete your account?\n\n⚠️ WARNING: This will permanently delete:\n• All your albums\n• All your photos\n• All your tags\n• All your settings\n\nThis action cannot be undone!',
    {
      type: 'danger',
      confirmText: 'Delete My Account'
    }
  )

  if (!confirmed) {
    return
  }

  // Second confirmation
  const doubleConfirmed = await confirmDialog(
    'This is your final warning!\n\nAre you absolutely sure you want to delete your account and all data?',
    {
      type: 'danger',
      confirmText: 'Yes, Delete Everything'
    }
  )

  if (!doubleConfirmed) {
    return
  }

  deletingAccount.value = true

  try {
    const response = await fetchWithAuth(`${apiUrl}/api/users/account`, {
      method: 'DELETE'
    })

    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      throw new Error(data.message || 'Failed to delete account')
    }

    success('Account deleted successfully')
    logout()
    router.push({ name: 'Login' })
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    showError(`Error deleting account: ${message}`)
  } finally {
    deletingAccount.value = false
  }
}

function handleLogout() {
  logout()
  router.push({ name: 'Login' })
}
</script>
