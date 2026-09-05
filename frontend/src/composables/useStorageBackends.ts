import { ref, type Ref } from "vue";
import { useApi, jsonBody } from "./useApi";
import type {
  StorageBackend,
  StorageBackendInput,
  StorageBackendTestResult,
} from "@/types";

export interface StorageBackendsComposable {
  backends: Ref<StorageBackend[]>;
  loading: Ref<boolean>;
  error: Ref<string | null>;
  loadBackends: () => Promise<void>;
  createBackend: (input: StorageBackendInput) => Promise<StorageBackend>;
  updateBackend: (
    id: number,
    input: StorageBackendInput,
  ) => Promise<StorageBackend>;
  deleteBackend: (id: number) => Promise<void>;
  testBackend: (
    input: StorageBackendInput,
    id?: number,
  ) => Promise<StorageBackendTestResult>;
}

/**
 * "Bring your own storage": the user registers an S3-compatible endpoint they pay for, and points
 * new albums at it. The list always includes the instance's own storage as a read-only entry, so
 * the album picker can render one list without special-casing the default.
 */
export function useStorageBackends(): StorageBackendsComposable {
  const { apiUrl, requestJson } = useApi();

  const backends = ref<StorageBackend[]>([]);
  const loading = ref<boolean>(false);
  const error = ref<string | null>(null);

  async function loadBackends(): Promise<void> {
    loading.value = true;
    error.value = null;
    try {
      backends.value = await requestJson<StorageBackend[]>(`${apiUrl}/api/storage-backends`);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown error";
      error.value = `Could not load storage: ${message}`;
    } finally {
      loading.value = false;
    }
  }

  async function createBackend(
    input: StorageBackendInput,
  ): Promise<StorageBackend> {
    const created = await requestJson<StorageBackend>(
      `${apiUrl}/api/storage-backends`,
      jsonBody("POST", input),
    );
    backends.value.push(created);
    return created;
  }

  async function updateBackend(
    id: number,
    input: StorageBackendInput,
  ): Promise<StorageBackend> {
    const saved = await requestJson<StorageBackend>(
      `${apiUrl}/api/storage-backends/${id}`,
      jsonBody("PUT", input),
    );
    const index = backends.value.findIndex((b) => b.id === id);
    if (index >= 0) {
      backends.value[index] = saved;
    }
    return saved;
  }

  async function deleteBackend(id: number): Promise<void> {
    await requestJson(`${apiUrl}/api/storage-backends/${id}`, { method: "DELETE" });
    backends.value = backends.value.filter((b) => b.id !== id);
  }

  /**
   * Try the settings without saving. A bad endpoint answers 200 with `ok: false` — the request
   * worked, the storage did not — so only a transport failure throws here.
   */
  async function testBackend(
    input: StorageBackendInput,
    id?: number,
  ): Promise<StorageBackendTestResult> {
    const url = id
      ? `${apiUrl}/api/storage-backends/${id}/test`
      : `${apiUrl}/api/storage-backends/test`;
    // Not requestJson: a refused request is itself an answer here, not an exception.
    try {
      return await requestJson<StorageBackendTestResult>(url, jsonBody("POST", input));
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown error";
      return { ok: false, failedStep: "connect", message };
    }
  }

  return {
    backends,
    loading,
    error,
    loadBackends,
    createBackend,
    updateBackend,
    deleteBackend,
    testBackend,
  };
}
