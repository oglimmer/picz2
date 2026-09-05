import { computed, ref, type ComputedRef, type Ref } from "vue";
import type { AlbumFile } from "@/types";

export interface Selection {
  selectedFileIds: Ref<Set<number>>;
  selectionActive: ComputedRef<boolean>;
  toggle: (fileId: number, index: number, shiftKey?: boolean) => void;
  clear: () => void;
  selectAll: () => void;
  /** Escape clears, Ctrl/Cmd+A selects everything. Returns true when it consumed the key. */
  handleKeydown: (event: KeyboardEvent) => boolean;
}

/**
 * The multi-select that feeds the bulk bar: click toggles, shift-click extends a range over the
 * album order. `index` is the file's position in `files`, or -1 when the caller cannot place it (a
 * stale grouped section, say) — a range from an unknown anchor would grab the wrong photos.
 */
export function useSelection(files: Ref<AlbumFile[]>): Selection {
  const selectedFileIds = ref<Set<number>>(new Set());
  const lastSelectedIndex = ref<number | null>(null);
  const selectionActive = computed(() => selectedFileIds.value.size > 0);

  function toggle(fileId: number, index: number, shiftKey = false): void {
    const ids = new Set(selectedFileIds.value);
    if (shiftKey && lastSelectedIndex.value !== null && index >= 0) {
      const lo = Math.min(lastSelectedIndex.value, index);
      const hi = Math.max(lastSelectedIndex.value, index);
      for (let i = lo; i <= hi; i++) ids.add(files.value[i].id);
    } else {
      if (ids.has(fileId)) ids.delete(fileId);
      else ids.add(fileId);
      lastSelectedIndex.value = index;
    }
    selectedFileIds.value = ids;
  }

  function clear(): void {
    selectedFileIds.value = new Set();
    lastSelectedIndex.value = null;
  }

  function selectAll(): void {
    selectedFileIds.value = new Set(files.value.map((f) => f.id));
  }

  function handleKeydown(event: KeyboardEvent): boolean {
    if (event.key === "Escape" && selectionActive.value) {
      clear();
      return true;
    }
    if ((event.key === "a" || event.key === "A") && (event.ctrlKey || event.metaKey)) {
      selectAll();
      return true;
    }
    return false;
  }

  return { selectedFileIds, selectionActive, toggle, clear, selectAll, handleKeydown };
}
