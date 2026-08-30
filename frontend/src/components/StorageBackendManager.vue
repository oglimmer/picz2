<template>
  <div class="storage-manager">
    <p class="storage-intro">
      Photos are stored on this site by default, up to the limit shown below. You can add
      your own S3-compatible storage instead — then the files live in your bucket, on your
      bill, with no limit from us. Pick the storage when you create an album; it cannot be
      changed afterwards.
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
        You need a bucket that already exists, and a key pair that may read, write and
        delete in it. This app does not create the bucket for you. Keep the bucket
        private — photos are served through short-lived signed links, so nothing needs
        to be public.
      </p>

      <div class="form-group">
        <label for="storage-provider">Provider</label>
        <select
          id="storage-provider"
          v-model="providerId"
          @change="applyProvider"
        >
          <option
            v-for="option in providers"
            :key="option.id"
            :value="option.id"
          >
            {{ option.label }}
          </option>
        </select>
        <small class="form-hint">
          Picking one fills in the endpoint shape and the right settings. You can still edit
          everything below.
        </small>
      </div>

      <div class="form-group">
        <label for="storage-name">Name</label>
        <input
          id="storage-name"
          v-model="form.name"
          placeholder="My photo bucket"
          required
        >
        <small class="form-hint">Just a label for you. It appears in the album picker.</small>
      </div>

      <div class="form-group">
        <label for="storage-endpoint">Endpoint URL</label>
        <input
          id="storage-endpoint"
          v-model="form.endpoint"
          :placeholder="provider.endpointTemplate"
          required
        >
        <small class="form-hint">
          The S3 address of your provider — not the address of your bucket.
          Replace anything in &lt;angle brackets&gt;.
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
        <small class="form-hint">{{ provider.regionHint }}</small>
      </div>

      <div class="form-group">
        <label for="storage-access-key">Access key</label>
        <input
          id="storage-access-key"
          v-model="form.accessKey"
          autocomplete="off"
          required
        >
        <small class="form-hint">{{ provider.keysHint }}</small>
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
          The long half of the key pair. Stored encrypted here and never shown again — most
          providers only show it once too, when you create the key.
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
            instead of in the hostname. Amazon S3 wants this off; almost everyone else wants it on.
            The provider list above sets it for you.
          </small>
        </span>
      </label>

      <p
        v-if="provider.note"
        class="storage-form-note"
      >
        {{ provider.note }}
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
import { computed, onMounted, reactive, ref } from 'vue'
import { useStorageBackends } from '../composables/useStorageBackends'
import { useNotifications } from '../composables/useNotifications'
import { useConfirm } from '../composables/useConfirm'
import { formatBytes } from '@/utils/format'
import { STORAGE_PROVIDERS, findProvider } from '@/utils/storageProviders'
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
const providers = STORAGE_PROVIDERS
// Which preset the form is following. Only a convenience — nothing about it is sent to the
// server, which sees the resulting endpoint/region/path-style like any hand-typed set.
const providerId = ref<string>('aws')
const provider = computed(() => findProvider(providerId.value) ?? STORAGE_PROVIDERS[0])
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

function startCreate() {
  resetForm()
  editingId.value = null
  providerId.value = 'aws'
  applyProvider()
  formOpen.value = true
}

/**
 * Copy the chosen preset into the connection fields. Only the three the preset actually knows —
 * name, bucket and the keys are the user's, and clearing them on a stray change of the dropdown
 * would throw away typing.
 */
function applyProvider() {
  form.endpoint = provider.value.endpointTemplate
  form.region = provider.value.region
  form.pathStyleAccess = provider.value.pathStyleAccess
  testResult.value = null
}

function startEdit(backend: StorageBackend) {
  resetForm()
  editingId.value = backend.id
  // Guess the preset back from the saved endpoint, so the hints under the fields describe the
  // provider this backend actually points at rather than whichever one happened to be selected.
  providerId.value = guessProvider(backend.endpoint ?? '')
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

/**
 * Which preset an existing endpoint looks like, so an edit form shows hints about the provider it
 * actually points at.
 *
 * Matched on the domain *suffix*, never the prefix: "https://s3." is the start of both the Amazon
 * and the Backblaze template, so a prefix match would file every B2 bucket under AWS — whichever
 * happened to be listed first. The tail after the last placeholder is unique per provider.
 */
function guessProvider(endpoint: string): string {
  const host = endpoint.toLowerCase().replace(/\/+$/, '')
  const match = STORAGE_PROVIDERS.find(p => {
    if (p.id === 'other') return false
    const template = p.endpointTemplate.toLowerCase()
    const suffix = template.includes('>') ? (template.split('>').pop() ?? '') : ''
    return suffix.length > 4 && host.endsWith(suffix)
  })
  return match?.id ?? 'other'
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

/* Provider-specific gotcha — the thing that makes the difference between a key that works and
   one that 403s. Set apart from the field hints so it is not read as another optional aside. */
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
