import { computed, ref, type ComputedRef, type Ref } from "vue";
import type { AlbumFile } from "@/types";

export interface DuplicateModeDeps {
  files: Ref<AlbumFile[]>;
  deleteMany: (fileIds: number[]) => Promise<number[] | null>;
  onActivate?: () => void;
}

export interface DuplicateMode {
  active: Ref<boolean>;
  selected: Ref<Set<number>>;
  /** The files to show: everything, or only those sharing a name with another, while active. */
  displayedFiles: ComputedRef<AlbumFile[]>;
  toggleMode: () => void;
  toggleSelection: (fileId: number) => void;
  deleteSelected: () => Promise<void>;
}

/**
 * iOS exports every edited Live Photo as "FullSizeRender.heic", so that name is never a duplicate
 * worth flagging.
 */
const EXCLUDED_DUPLICATE_NAME = "fullsizerender.heic";

function nameOf(file: AlbumFile): string {
  return file.originalName || file.filename || "";
}

function isExcluded(file: AlbumFile): boolean {
  return nameOf(file).toLowerCase() === EXCLUDED_DUPLICATE_NAME;
}

/**
 * "Find duplicate names": narrows the grid to files whose name another file also carries, and
 * pre-selects every copy but the first so one click removes the extras.
 */
export function useDuplicateMode(deps: DuplicateModeDeps): DuplicateMode {
  const active = ref(false);
  const selected = ref<Set<number>>(new Set());

  const displayedFiles = computed(() => {
    if (!active.value) return deps.files.value;
    const counts = new Map<string, number>();
    for (const file of deps.files.value) {
      if (isExcluded(file)) continue;
      counts.set(nameOf(file), (counts.get(nameOf(file)) || 0) + 1);
    }
    return deps.files.value.filter((f) => !isExcluded(f) && (counts.get(nameOf(f)) || 0) > 1);
  });

  function toggleMode(): void {
    if (active.value) {
      active.value = false;
      selected.value = new Set();
      return;
    }
    deps.onActivate?.();
    active.value = true;
    const seen = new Set<string>();
    const toSelect = new Set<number>();
    for (const file of deps.files.value) {
      if (isExcluded(file)) continue;
      const key = nameOf(file);
      if (seen.has(key)) toSelect.add(file.id);
      else seen.add(key);
    }
    selected.value = toSelect;
  }

  function toggleSelection(fileId: number): void {
    const next = new Set(selected.value);
    if (next.has(fileId)) next.delete(fileId);
    else next.add(fileId);
    selected.value = next;
  }

  async function deleteSelected(): Promise<void> {
    const failed = await deps.deleteMany([...selected.value]);
    if (failed === null) return; // cancelled
    selected.value = new Set(failed);
    if (displayedFiles.value.length === 0) active.value = false;
  }

  return { active, selected, displayedFiles, toggleMode, toggleSelection, deleteSelected };
}
