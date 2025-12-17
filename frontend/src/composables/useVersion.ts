import { ref, computed, onMounted } from "vue";
import { useApi } from "./useApi";

declare const __APP_VERSION__: string;
declare const __GIT_COMMIT__: string;

export function useVersion() {
  const { apiUrl } = useApi();
  const frontendVersion = ref<string>(
    typeof __APP_VERSION__ !== "undefined" ? __APP_VERSION__ : "unknown",
  );
  const frontendCommit = ref<string>(
    typeof __GIT_COMMIT__ !== "undefined" ? __GIT_COMMIT__ : "unknown",
  );

  const backendVersion = ref<string>("unknown");
  const backendCommit = ref<string>("unknown");
  const loading = ref<boolean>(false);
  const error = ref<string>("");

  async function loadBackendInfo() {
    loading.value = true;
    error.value = "";
    try {
      const resp = await fetch(`${apiUrl}/api/version`);
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const data = await resp.json();

      // Expect ApiResponse<VersionInfo> shape
      const payload = data && data.data ? data.data : null;
      if (payload) {
        backendVersion.value = (payload.version || "unknown") as string;
        backendCommit.value = ((payload.commit || "unknown") as string).slice(
          0,
          12,
        );
      } else {
        backendVersion.value = "unknown";
        backendCommit.value = "unknown";
      }
    } catch (e: unknown) {
      error.value = (e as Error)?.message || "Failed to load backend info";
    } finally {
      loading.value = false;
    }
  }

  const hasBackendInfo = computed(
    () =>
      backendVersion.value !== "unknown" || backendCommit.value !== "unknown",
  );

  onMounted(() => {
    // Fire and forget; UI remains usable if this fails
    loadBackendInfo();
  });

  return {
    frontendVersion,
    frontendCommit,
    backendVersion,
    backendCommit,
    hasBackendInfo,
    loading,
    error,
    loadBackendInfo,
  };
}
