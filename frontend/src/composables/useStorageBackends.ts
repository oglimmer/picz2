import { ref, type Ref } from "vue";
import { useApi } from "./useApi";
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
  const { apiUrl, fetchWithAuth } = useApi();

  const backends = ref<StorageBackend[]>([]);
  const loading = ref<boolean>(false);
  const error = ref<string | null>(null);

  /** The server's error body carries the useful sentence; the status code does not. */
  async function messageFrom(response: Response): Promise<string> {
    try {
      const body = await response.json();
      return body?.message || body?.error || `Request failed (${response.status})`;
    } catch {
      return `Request failed (${response.status})`;
    }
  }

  async function loadBackends(): Promise<void> {
    loading.value = true;
    error.value = null;
    try {
      const response = await fetchWithAuth(`${apiUrl}/api/storage-backends`);
      if (!response.ok) {
        throw new Error(await messageFrom(response));
      }
      backends.value = await response.json();
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown error";
      error.value = `Could not load storage: ${message}`;
      console.error("Error loading storage backends:", err);
    } finally {
      loading.value = false;
    }
  }

  async function createBackend(
    input: StorageBackendInput,
  ): Promise<StorageBackend> {
    const response = await fetchWithAuth(`${apiUrl}/api/storage-backends`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(input),
    });
    if (!response.ok) {
      throw new Error(await messageFrom(response));
    }
    const created: StorageBackend = await response.json();
    backends.value.push(created);
    return created;
  }

  async function updateBackend(
    id: number,
    input: StorageBackendInput,
  ): Promise<StorageBackend> {
    const response = await fetchWithAuth(
      `${apiUrl}/api/storage-backends/${id}`,
      {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(input),
      },
    );
    if (!response.ok) {
      throw new Error(await messageFrom(response));
    }
    const saved: StorageBackend = await response.json();
    const index = backends.value.findIndex((b) => b.id === id);
    if (index >= 0) {
      backends.value[index] = saved;
    }
    return saved;
  }

  async function deleteBackend(id: number): Promise<void> {
    const response = await fetchWithAuth(
      `${apiUrl}/api/storage-backends/${id}`,
      { method: "DELETE" },
    );
    if (!response.ok) {
      throw new Error(await messageFrom(response));
    }
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
    const response = await fetchWithAuth(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(input),
    });
    if (!response.ok) {
      return { ok: false, failedStep: "connect", message: await messageFrom(response) };
    }
    return await response.json();
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
