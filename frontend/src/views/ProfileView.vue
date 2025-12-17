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

<style scoped>
.profile-container {
  min-height: 100vh;
  background: #f5f5f5;
  padding: 20px;
}

.profile-card {
  max-width: 700px;
  margin: 0 auto;
  background: white;
  border-radius: 12px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
  padding: 30px;
}

.profile-header {
  margin-bottom: 30px;
}

.back-link {
  background: none;
  border: none;
  color: #667eea;
  cursor: pointer;
  font-size: 14px;
  padding: 0;
  margin-bottom: 15px;
  display: inline-block;
}

.back-link:hover {
  text-decoration: underline;
}

.profile-header h1 {
  margin: 0;
  color: #333;
  font-size: 2em;
  font-weight: 700;
}

.profile-section {
  margin-bottom: 40px;
  padding-bottom: 30px;
  border-bottom: 1px solid #e0e0e0;
}

.profile-section:last-of-type {
  border-bottom: none;
}

.profile-section h2 {
  margin: 0 0 20px 0;
  color: #333;
  font-size: 1.3em;
  font-weight: 600;
}

.info-group {
  margin-bottom: 15px;
}

.info-group label {
  display: block;
  font-weight: 600;
  color: #555;
  margin-bottom: 5px;
  font-size: 0.9em;
}

.info-value {
  padding: 10px;
  background: #f8f8f8;
  border-radius: 6px;
  color: #333;
  font-size: 1em;
}

.password-form {
  max-width: 400px;
}

.form-group {
  margin-bottom: 20px;
}

.form-group label {
  display: block;
  font-weight: 600;
  color: #555;
  margin-bottom: 5px;
  font-size: 0.9em;
}

.auth-input {
  width: 100%;
  padding: 12px;
  border: 1px solid #ddd;
  border-radius: 6px;
  font-size: 1em;
  box-sizing: border-box;
}

.auth-input:focus {
  outline: none;
  border-color: #667eea;
  box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
}

.btn {
  padding: 12px 24px;
  border: none;
  border-radius: 6px;
  font-size: 1em;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.btn-primary {
  background: #667eea;
  color: white;
}

.btn-primary:hover:not(:disabled) {
  background: #5568d3;
}

.btn-secondary {
  background: #6c757d;
  color: white;
}

.btn-secondary:hover:not(:disabled) {
  background: #5a6268;
}

.btn-danger {
  background: #dc3545;
  color: white;
}

.btn-danger:hover:not(:disabled) {
  background: #c82333;
}

.danger-section {
  border: 2px solid #dc3545;
  border-radius: 8px;
  padding: 20px;
  background: #fff5f5;
}

.danger-section h2 {
  color: #dc3545;
}

.danger-actions {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 20px;
  flex-wrap: wrap;
}

.action-description h3 {
  margin: 0 0 8px 0;
  color: #333;
  font-size: 1.1em;
  font-weight: 600;
}

.action-description p {
  margin: 0;
  color: #666;
  font-size: 0.9em;
  line-height: 1.5;
}

.profile-actions {
  margin-top: 30px;
  text-align: center;
}

@media (max-width: 600px) {
  .profile-card {
    padding: 20px;
  }

  .danger-actions {
    flex-direction: column;
    align-items: stretch;
  }

  .password-form {
    max-width: 100%;
  }
}
</style>
