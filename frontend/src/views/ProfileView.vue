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

      <div class="profile-section">
        <h2>New Photo Visibility</h2>
        <p class="section-intro">
          Every photo and video you upload is tagged automatically. This is the tag it gets.
          Public visitors of a shared album never see anything tagged <code>hidden</code>.
        </p>

        <!-- Buttons, not <input type="radio">. The switch to `all` is confirmed asynchronously,
             and the browser marks a radio checked the instant it is clicked — so cancelling the
             dialog left a radio ticked for a setting that was never saved, and Vue had no reason
             to patch it back, because the value it binds to never changed. A button owns no state
             of its own: the dot below is drawn from `newAssetTag` and nothing else, so a cancel,
             a failed save and a reload all show the same thing. -->
        <div
          class="visibility-options"
          role="radiogroup"
          aria-label="Tag for newly uploaded photos"
        >
          <button
            v-for="option in visibilityOptions"
            :key="option.value"
            type="button"
            role="radio"
            class="visibility-option"
            :class="{ selected: newAssetTag === option.value }"
            :aria-checked="newAssetTag === option.value"
            :disabled="savingNewAssetTag || loadingNewAssetTag"
            @click="chooseNewAssetTag(option.value)"
          >
            <span
              class="visibility-dot"
              aria-hidden="true"
            />
            <span class="visibility-body">
              <span class="visibility-title">
                {{ option.title }}
                <span
                  v-if="option.recommended"
                  class="badge"
                >Recommended</span>
              </span>
              <span class="visibility-detail">{{ option.detail }}</span>
            </span>
          </button>
        </div>

        <p class="section-note">
          Changing this only affects photos uploaded from now on. Nothing already in your albums
          is re-tagged either way.
        </p>
      </div>

      <div class="profile-section">
        <h2>Photo storage</h2>
        <StorageBackendManager />
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
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import { useApi } from '../composables/useApi'
import { useNotifications } from '../composables/useNotifications'
import { useConfirm } from '../composables/useConfirm'
import { useSettings, type NewAssetTag } from '../composables/useSettings'
import StorageBackendManager from '../components/StorageBackendManager.vue'

const router = useRouter()
const { authEmail, logout, login } = useAuth()
const { apiUrl, fetchWithAuth } = useApi()
const { success, error: showError } = useNotifications()
const { confirm: confirmDialog } = useConfirm()
const { newAssetTag, loadNewAssetTag, updateNewAssetTag } = useSettings()

const userEmail = computed(() => authEmail.value)
const currentPassword = ref('')
const newPassword = ref('')
const confirmPassword = ref('')
const changingPassword = ref(false)
const deletingAccount = ref(false)
const loadingNewAssetTag = ref(true)
const savingNewAssetTag = ref(false)

const visibilityOptions: { value: NewAssetTag, title: string, detail: string, recommended?: boolean }[] = [
  {
    value: 'hidden',
    title: 'Keep new photos hidden',
    detail: 'New uploads get the "hidden" tag. Nobody with your share link can see them. You look '
      + 'at them in your gallery, remove "hidden", and only then do they go public.',
    recommended: true
  },
  {
    value: 'all',
    title: 'Publish new photos straight away',
    detail: 'New uploads get the "all" tag. In a published album they appear on the share link '
      + 'within seconds of the upload, with no review. Anything your phone uploads automatically '
      + 'goes public the same way.'
  }
]

onMounted(async () => {
  await loadNewAssetTag()
  loadingNewAssetTag.value = false
})

/**
 * Switch which tag new uploads get.
 *
 * Only the move towards `all` asks first. Going back to `hidden` can only ever take photos off a
 * public page, so a dialog there would be noise; going to `all` puts every future upload in front
 * of strangers the moment it finishes processing, and that is worth one deliberate click.
 *
 * The radio is driven by the shared ref rather than local state, so a rejected or cancelled change
 * leaves the old option selected without any manual roll-back.
 */
async function chooseNewAssetTag(tagName: NewAssetTag) {
  if (tagName === newAssetTag.value || savingNewAssetTag.value) {
    return
  }

  if (tagName === 'all') {
    const confirmed = await confirmDialog(
      'Publish every new photo straight away?\n\n'
        + 'From now on, each photo and video you upload is tagged "all" and becomes visible to '
        + 'anyone holding the share link of a published album — within seconds, with no review '
        + 'step.\n\n'
        + 'Photos your phone uploads automatically are included.\n\n'
        + 'You can switch back at any time, but photos published in the meantime stay published '
        + 'until you re-tag them by hand.',
      {
        type: 'danger',
        confirmText: 'Yes, publish new photos'
      }
    )

    if (!confirmed) {
      return
    }
  }

  savingNewAssetTag.value = true

  try {
    await updateNewAssetTag(tagName)
    success(
      tagName === 'hidden'
        ? 'New photos will stay hidden until you publish them'
        : 'New photos will be published straight away'
    )
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    showError(`Could not save the setting: ${message}`)
  } finally {
    savingNewAssetTag.value = false
  }
}

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

    // The server revokes every session on a password change (D78), this one included. Sign
    // straight back in with the new password so the user is not bounced to the login page.
    const stillIn = await login(authEmail.value, newPassword.value)
    success('Password changed successfully!')
    currentPassword.value = ''
    newPassword.value = ''
    confirmPassword.value = ''
    if (!stillIn) {
      logout()
      router.push({ name: 'Login' })
    }
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
