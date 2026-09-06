import { computed, ref, type ComputedRef, type Ref } from "vue";
import type { AlbumFile } from "@/types";
import type { PollFailure } from "../useProcessingPoller";

export interface EnhanceReviewDeps {
  /** `POST /api/files/{id}/enhance-preview` — 202, the worker builds the preview. */
  requestPreview: (fileId: number) => Promise<void>;
  waitForProcessing: (fileIds: number[], timeoutMs: number) => Promise<PollFailure[]>;
  /** The finished preview as an object URL. */
  loadPreview: (fileId: number) => Promise<string>;
  discardPreview: (fileId: number) => Promise<void>;
  /** Injected so tests do not need a DOM `URL`. */
  revokeUrl?: (url: string) => void;
}

export interface EnhanceReview {
  files: Ref<AlbumFile[]>;
  index: Ref<number>;
  current: ComputedRef<AlbumFile | null>;
  /** Object URL of the current photo's preview, null while it is being built or after a failure. */
  previewUrl: Ref<string | null>;
  loading: Ref<boolean>;
  error: Ref<string | null>;
  /** Which side the stage shows. Flipped by the segmented control, the space bar and press-and-hold. */
  showEnhanced: Ref<boolean>;
  accepted: Ref<number[]>;
  /** True once every photo has been decided or the review was cancelled. */
  finished: Ref<boolean>;
  start: (files: AlbumFile[]) => Promise<void>;
  accept: () => Promise<void>;
  decline: () => Promise<void>;
  cancel: () => Promise<void>;
  toggle: () => void;
  show: (enhanced: boolean) => void;
}

/** How long one preview may take, worker queue included. A bulk review requests them all up front. */
const PREVIEW_TIMEOUT_MS = 120_000;

/**
 * The accept-or-decline pass over one or more photos (D82). Every preview is requested at the
 * start so the worker can build the later ones while the owner looks at the first; each photo is
 * then waited for, fetched, shown against the current image, and either accepted (collected for
 * `useBulkActions.enhanceMany`, which enqueues the real job) or declined (the preview is deleted).
 * Cancelling declines everything not yet decided. Accepted previews are left for the server: the
 * ENHANCE job removes them when it rewrites the photo.
 */
export function useEnhanceReview(deps: EnhanceReviewDeps): EnhanceReview {
  const revoke = deps.revokeUrl ?? ((url: string) => URL.revokeObjectURL(url));

  const files = ref<AlbumFile[]>([]);
  const index = ref(0);
  const previewUrl = ref<string | null>(null);
  const loading = ref(false);
  const error = ref<string | null>(null);
  const showEnhanced = ref(true);
  const accepted = ref<number[]>([]);
  const finished = ref(false);
  /** Ids whose preview request was refused; they can only be skipped. */
  const refused = new Map<number, string>();
  /** Bumped by every start/advance so a slow load for a previous photo cannot land on this one. */
  let generation = 0;

  const current = computed(() => files.value[index.value] ?? null);

  function dropPreviewUrl() {
    if (previewUrl.value) revoke(previewUrl.value);
    previewUrl.value = null;
  }

  async function loadCurrent(): Promise<void> {
    const file = current.value;
    if (!file) return;
    const myGeneration = ++generation;
    dropPreviewUrl();
    error.value = null;
    showEnhanced.value = true;
    const refusal = refused.get(file.id);
    if (refusal) {
      error.value = refusal;
      loading.value = false;
      return;
    }
    loading.value = true;
    try {
      const failures = await deps.waitForProcessing([file.id], PREVIEW_TIMEOUT_MS);
      if (myGeneration !== generation) return;
      if (failures.length > 0) throw new Error(failures[0].message);
      const url = await deps.loadPreview(file.id);
      if (myGeneration !== generation) {
        revoke(url);
        return;
      }
      previewUrl.value = url;
    } catch (err) {
      if (myGeneration !== generation) return;
      error.value = err instanceof Error ? err.message : "Could not load the preview.";
    } finally {
      if (myGeneration === generation) loading.value = false;
    }
  }

  async function start(list: AlbumFile[]): Promise<void> {
    files.value = [...list];
    index.value = 0;
    accepted.value = [];
    finished.value = list.length === 0;
    refused.clear();
    dropPreviewUrl();
    if (list.length === 0) return;
    // Show the first photo as soon as its own request is in; the rest queue behind it.
    const [first, ...rest] = list;
    try {
      await deps.requestPreview(first.id);
    } catch (err) {
      refused.set(first.id, err instanceof Error ? err.message : "Could not request the preview.");
    }
    const loadingFirst = loadCurrent();
    for (const file of rest) {
      try {
        await deps.requestPreview(file.id);
      } catch (err) {
        refused.set(file.id, err instanceof Error ? err.message : "Could not request the preview.");
      }
    }
    await loadingFirst;
  }

  async function advance(): Promise<void> {
    dropPreviewUrl();
    if (index.value + 1 >= files.value.length) {
      generation++;
      loading.value = false;
      finished.value = true;
      return;
    }
    index.value += 1;
    await loadCurrent();
  }

  async function discardQuietly(fileId: number): Promise<void> {
    if (refused.has(fileId)) return;
    try {
      await deps.discardPreview(fileId);
    } catch {
      // A preview left behind costs a few hundred KB and the ENHANCE job or a delete removes it.
    }
  }

  async function accept(): Promise<void> {
    const file = current.value;
    if (!file || finished.value || loading.value || error.value) return;
    accepted.value = [...accepted.value, file.id];
    await advance();
  }

  async function decline(): Promise<void> {
    const file = current.value;
    if (!file || finished.value) return;
    void discardQuietly(file.id);
    await advance();
  }

  async function cancel(): Promise<void> {
    if (finished.value) return;
    const remaining = files.value.slice(index.value);
    generation++;
    dropPreviewUrl();
    loading.value = false;
    finished.value = true;
    await Promise.all(remaining.map((f) => discardQuietly(f.id)));
  }

  function toggle() {
    if (previewUrl.value) showEnhanced.value = !showEnhanced.value;
  }

  function show(enhanced: boolean) {
    if (previewUrl.value) showEnhanced.value = enhanced;
  }

  return {
    files,
    index,
    current,
    previewUrl,
    loading,
    error,
    showEnhanced,
    accepted,
    finished,
    start,
    accept,
    decline,
    cancel,
    toggle,
    show,
  };
}
