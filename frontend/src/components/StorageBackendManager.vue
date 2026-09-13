<template>
  <div class="storage-manager">
    <p class="storage-intro">
      Photos are stored on this site by default, up to the limit shown below. Got a home
      server — a MinIO box in your home lab, or a little machine humming in the living room?
      Add it, and the files of an album live there instead, with no limit from us. Pick the
      storage when you create an album; it cannot be changed afterwards.
      <router-link
        to="/help/home-server"
        class="storage-guide-link"
      >
        Step-by-step guide: set up MinIO at home
      </router-link>
    </p>

    <div
      v-if="error"
      class="storage-error"
    >
      {{ error }}
    </div>

    <div
      v-if="loading && backends.length === 0"
      class="storage-empty"
    >
      Loading…
    </div>

    <ul
      v-else
      class="storage-list"
    >
      <li
        v-for="backend in backends"
        :key="backend.id"
        class="storage-item"
      >
        <div class="storage-item-main">
          <div class="storage-item-name">
            {{ backend.name }}
            <span
              v-if="backend.systemDefault"
              class="storage-badge"
            >Default</span>
          </div>
          <div class="storage-item-detail">
            <template v-if="backend.systemDefault">
              Provided by this site.
            </template>
            <template v-else>
              {{ backend.endpoint }} · bucket {{ backend.bucket }}
            </template>
          </div>
          <div class="storage-item-usage">
            {{ backend.albumCount === 1 ? '1 album' : backend.albumCount + ' albums' }}
          </div>
          <!-- Only the site's own storage is metered; your own bucket is yours to fill. -->
          <div
            v-if="hasQuota(backend)"
            class="storage-quota"
          >
            <div
              class="storage-quota-bar"
              role="progressbar"
              :aria-valuenow="Math.round(usedFraction(backend) * 100)"
              aria-valuemin="0"
              aria-valuemax="100"
            >
              <div
                class="storage-quota-fill"
                :class="{ 'is-full': usedFraction(backend) >= 1 }"
                :style="{ width: Math.min(100, usedFraction(backend) * 100) + '%' }"
              />
            </div>
            <span class="storage-quota-label">
              {{ formatBytes(backend.usedBytes!) }} of {{ formatBytes(backend.quotaBytes!) }} used
            </span>
          </div>
        </div>
        <div
          v-if="!backend.systemDefault"
          class="storage-item-actions"
        >
          <button
            class="btn btn-secondary"
            @click="startEdit(backend)"
          >
            Edit
          </button>
          <button
            class="btn btn-danger"
            :disabled="backend.albumCount > 0 || busy"
            :title="backend.albumCount > 0
              ? 'Albums are still stored here. Delete them first.'
              : 'Remove this storage'"
            @click="handleDelete(backend)"
          >
            Remove
          </button>
        </div>
      </li>
    </ul>

    <button
      v-if="!formOpen"
      class="btn btn-secondary storage-add-btn"
      @click="startCreate"
    >
      Add your own storage
    </button>

    <form
      v-else
      class="storage-form"
      @submit.prevent="handleSave"
    >
      <h3>{{ editingId ? 'Edit storage' : 'Add storage' }}</h3>

      <p class="storage-form-intro">
        Your photos, on the server in your own home. Before you start, create a bucket on
        your home server's MinIO and an access key that may read, write and delete in it —
        this app does not create the bucket for you. Keep the bucket private: this site fetches
        the photos from your server and passes them on, so nothing on your server needs to be
        public.
      </p>

      <div class="form-group">
        <label for="storage-name">Name</label>
        <input
          id="storage-name"
          v-model="form.name"
          placeholder="Home server"
          required
        >
        <small class="form-hint">Just a label for you, like "Home server". It appears in the album picker.</small>
      </div>

      <div class="form-group">
        <label for="storage-endpoint">Endpoint URL</label>
        <input
          id="storage-endpoint"
          v-model="form.endpoint"
          placeholder="https://minio.example.com"
          required
        >
        <small class="form-hint">
          The API address of the MinIO on your home server (often port 9000) — not the
          Console address, and not the address of your bucket.
        </small>
      </div>

      <div class="form-group">
        <label for="storage-bucket">Bucket</label>
        <input
          id="storage-bucket"
          v-model="form.bucket"
          placeholder="my-photos"
          required
        >
        <small class="form-hint">
          The bucket's name on its own, with no URL and no slashes. It must already exist.
        </small>
      </div>

      <div class="form-group">
        <label for="storage-region">Region</label>
        <input
          id="storage-region"
          v-model="form.region"
          placeholder="us-east-1"
        >
        <small class="form-hint">
          A home server rarely cares about this: MinIO ignores the region unless you set one.
          Leave "us-east-1" unless you changed it on your server.
        </small>
      </div>

      <div class="form-group">
        <label for="storage-access-key">Access key</label>
        <input
          id="storage-access-key"
          v-model="form.accessKey"
          autocomplete="off"
          required
        >
        <small class="form-hint">
          Open the MinIO Console on your home server: Access Keys → Create access key.
        </small>
      </div>

      <div class="form-group">
        <label for="storage-secret-key">Secret key</label>
        <input
          id="storage-secret-key"
          v-model="form.secretKey"
          type="password"
          autocomplete="new-password"
          :placeholder="editingId ? 'Leave empty to keep the saved key' : ''"
          :required="!editingId"
        >
        <!-- The secret never comes back from the server, so an edit form cannot show it. -->
        <small class="form-hint">
          The long half of the key pair. Stored encrypted here and never shown again. MinIO
          also shows it only once, when you create the key, so copy it then.
        </small>
      </div>

      <label class="form-checkbox">
        <input
          v-model="form.pathStyleAccess"
          type="checkbox"
        >
        <span>
          Path-style addressing
          <small class="form-hint">
            Puts the bucket in the path ({{ form.endpoint || 'https://…' }}/{{ form.bucket || 'bucket' }})
            instead of in the hostname. The MinIO on a home server needs this on. Turn it off
            only if you set up your server to expect the bucket name in the hostname.
          </small>
        </span>
      </label>

      <p class="storage-form-note">
        Your home server has to be reachable from the internet: this site calls your home, so
        an address that only works on your home Wi‑Fi is not enough.
      </p>

      <div
        v-if="testResult"
        :class="['storage-test-result', testResult.ok ? 'is-ok' : 'is-bad']"
      >
        <template v-if="testResult.ok">
          Connection works — the test file was written, read and deleted.
        </template>
        <template v-else>
          Could not use this storage ({{ testResult.failedStep }}): {{ testResult.message }}
        </template>
      </div>

      <div class="storage-form-actions">
        <button
          type="submit"
          class="btn btn-primary"
          :disabled="busy"
        >
          {{ busy ? 'Saving…' : 'Save' }}
        </button>
        <button
          type="button"
          class="btn btn-secondary"
          :disabled="busy"
          @click="handleTest"
        >
          Test connection
        </button>
        <button
          type="button"
          class="btn btn-secondary"
          :disabled="busy"
          @click="closeForm"
        >
          Cancel
        </button>
      </div>
    </form>
  </div>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { useStorageBackends } from '../composables/useStorageBackends'
import { useNotifications } from '../composables/useNotifications'
import { useConfirm } from '../composables/useConfirm'
import { formatBytes } from '@/utils/format'
import type { StorageBackend, StorageBackendInput, StorageBackendTestResult } from '@/types'

const {
  backends,
  loading,
  error,
  loadBackends,
  createBackend,
  updateBackend,
  deleteBackend,
  testBackend,
} = useStorageBackends()
const { success, error: showError } = useNotifications()
const { confirm: confirmDialog } = useConfirm()

const formOpen = ref(false)
const editingId = ref<number | null>(null)
const busy = ref(false)
const testResult = ref<StorageBackendTestResult | null>(null)

const form = reactive<StorageBackendInput>({
  name: '',
  endpoint: '',
  region: 'us-east-1',
  bucket: '',
  accessKey: '',
  secretKey: '',
  pathStyleAccess: true,
})

onMounted(loadBackends)

/** Only the site's own storage reports a limit; a user's own bucket reports none. */
function hasQuota(backend: StorageBackend): boolean {
  return typeof backend.usedBytes === 'number' && typeof backend.quotaBytes === 'number'
}

function usedFraction(backend: StorageBackend): number {
  const quota = backend.quotaBytes ?? 0
  // A quota of zero is a frozen account, not a divide-by-zero: it is full by definition.
  if (quota <= 0) return 1
  return (backend.usedBytes ?? 0) / quota
}

function resetForm() {
  form.name = ''
  form.endpoint = ''
  form.region = 'us-east-1'
  form.bucket = ''
  form.accessKey = ''
  form.secretKey = ''
  form.pathStyleAccess = true
  testResult.value = null
}

/**
 * The copy is written for a self-hosted MinIO, and `resetForm` leaves its settings (region
 * "us-east-1", path-style on). Nothing is locked, so any other server that speaks the same
 * protocol works as well.
 */
function startCreate() {
  resetForm()
  editingId.value = null
  formOpen.value = true
}

function startEdit(backend: StorageBackend) {
  resetForm()
  editingId.value = backend.id
  form.name = backend.name
  form.endpoint = backend.endpoint ?? ''
  form.region = backend.region ?? 'us-east-1'
  form.bucket = backend.bucket ?? ''
  form.accessKey = backend.accessKey ?? ''
  // secretKey stays empty on purpose: the server never returns it, and an empty value on save
  // means "keep the stored one".
  form.pathStyleAccess = backend.pathStyleAccess
  formOpen.value = true
}

function closeForm() {
  formOpen.value = false
  editingId.value = null
  resetForm()
}

/** Omit an empty secret entirely, so the server can tell "unchanged" from "cleared". */
function payload(): StorageBackendInput {
  const body: StorageBackendInput = {
    name: form.name,
    endpoint: form.endpoint,
    region: form.region,
    bucket: form.bucket,
    accessKey: form.accessKey,
    pathStyleAccess: form.pathStyleAccess,
  }
  if (form.secretKey) {
    body.secretKey = form.secretKey
  }
  return body
}

async function handleTest() {
  busy.value = true
  testResult.value = null
  try {
    testResult.value = await testBackend(payload(), editingId.value ?? undefined)
  } finally {
    busy.value = false
  }
}

async function handleSave() {
  busy.value = true
  testResult.value = null
  try {
    if (editingId.value) {
      await updateBackend(editingId.value, payload())
      success('Storage updated')
    } else {
      await createBackend(payload())
      success('Storage added')
    }
    closeForm()
  } catch (err) {
    // The server only saves settings it has proved work, so this message is the real reason.
    showError(err instanceof Error ? err.message : 'Could not save this storage')
  } finally {
    busy.value = false
  }
}

async function handleDelete(backend: StorageBackend) {
  const ok = await confirmDialog(
    `Remove "${backend.name}"? Your bucket and its files are left untouched.`,
    { confirmText: 'Remove', type: 'danger' },
  )
  if (!ok) return

  busy.value = true
  try {
    await deleteBackend(backend.id)
    success('Storage removed')
  } catch (err) {
    showError(err instanceof Error ? err.message : 'Could not remove this storage')
  } finally {
    busy.value = false
  }
}
</script>

<style scoped>
.storage-intro {
  margin: 0 0 var(--sp-4);
  color: var(--c-text-2);
  font-size: .9375rem;
  line-height: 1.5;
}

.storage-guide-link {
  display: block;
  margin-top: var(--sp-2);
  color: var(--c-accent);
}

.storage-error {
  margin-bottom: var(--sp-3);
  color: var(--c-danger, #c0392b);
  font-size: .875rem;
}

.storage-empty {
  color: var(--c-text-3);
  font-size: .875rem;
}

.storage-list {
  list-style: none;
  margin: 0 0 var(--sp-4);
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: var(--sp-2);
}

.storage-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--sp-4);
  padding: var(--sp-3) var(--sp-4);
  border: 1.5px solid var(--c-border);
  border-radius: var(--r-md);
  background: var(--c-surface);
}

.storage-item-name {
  font-weight: 600;
  display: flex;
  align-items: center;
  gap: var(--sp-2);
}

.storage-badge {
  font-size: .6875rem;
  font-weight: 600;
  letter-spacing: .03em;
  text-transform: uppercase;
  padding: 2px 6px;
  border-radius: var(--r-sm, 4px);
  background: var(--c-border);
  color: var(--c-text-2);
}

.storage-quota {
  margin-top: 6px;
  display: flex;
  flex-direction: column;
  gap: 4px;
  max-width: 280px;
}

.storage-quota-bar {
  height: 6px;
  border-radius: 999px;
  background: var(--c-border);
  overflow: hidden;
}

.storage-quota-fill {
  height: 100%;
  background: var(--c-accent);
  transition: width var(--t-fast);
}
.storage-quota-fill.is-full {
  background: #c0392b;
}

.storage-quota-label {
  font-size: .75rem;
  color: var(--c-text-3);
}

.storage-item-detail,
.storage-item-usage {
  font-size: .8125rem;
  color: var(--c-text-3);
  word-break: break-all;
}

.storage-item-actions {
  display: flex;
  gap: var(--sp-2);
  flex-shrink: 0;
}

.storage-form {
  display: flex;
  flex-direction: column;
  gap: var(--sp-3);
  padding: var(--sp-4);
  border: 1.5px solid var(--c-border);
  border-radius: var(--r-md);
}

.storage-form h3 {
  margin: 0;
}

.form-checkbox {
  display: flex;
  align-items: flex-start;
  gap: var(--sp-2);
  font-size: .875rem;
  color: var(--c-text-2);
}

.form-hint {
  display: block;
  margin-top: 4px;
  color: var(--c-text-3);
  font-size: .75rem;
  line-height: 1.45;
}

.storage-form-intro {
  margin: 0;
  color: var(--c-text-2);
  font-size: .875rem;
  line-height: 1.5;
}

/* The one thing that trips people up with a home server: the phone or browser can reach it, the
   photo server cannot. Set apart from the field hints so it is not read as an optional aside. */
.storage-form-note {
  margin: 0;
  padding: var(--sp-3);
  border-left: 3px solid var(--c-accent);
  border-radius: var(--r-md);
  background: var(--c-surface);
  color: var(--c-text-2);
  font-size: .8125rem;
  line-height: 1.5;
}

.storage-test-result {
  padding: var(--sp-3);
  border-radius: var(--r-md);
  font-size: .875rem;
}
.storage-test-result.is-ok {
  background: rgba(46, 160, 67, .12);
  color: #1f7a33;
}
.storage-test-result.is-bad {
  background: rgba(192, 57, 43, .12);
  color: #a5281c;
}

.storage-form-actions {
  display: flex;
  gap: var(--sp-2);
  flex-wrap: wrap;
}
</style>
