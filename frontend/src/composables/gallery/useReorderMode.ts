import { ref, type Ref } from "vue";
import { useNotifications } from "../useNotifications";
import type { AlbumFile } from "@/types";

export interface ReorderModeDeps {
  files: Ref<AlbumFile[]>;
  reorderFiles: (fileIds: number[]) => Promise<void>;
  reloadFiles: () => Promise<void>;
  /** Called when the mode switches on, so a competing mode can switch off. */
  onActivate?: () => void;
}

export interface ReorderMode {
  active: Ref<boolean>;
  selected: Ref<Set<number>>;
  toggleMode: () => void;
  toggleSelection: (fileId: number) => void;
  moveSelectedAfter: (targetFileId: number) => Promise<void>;
  moveSelectedToTop: () => Promise<void>;
  // Drag and drop in the plain grid.
  draggingIndex: Ref<number | null>;
  dragOverIndex: Ref<number | null>;
  onDragStart: (event: DragEvent, index: number) => void;
  onDragOver: (event: DragEvent, index: number) => void;
  onDragEnter: (event: DragEvent, index: number) => void;
  onDrop: (event: DragEvent, dropIndex: number) => Promise<void>;
  onDragEnd: () => void;
}

/**
 * Two ways to put photos in a new order: drag one tile onto another, or "arrange by hand" — pick
 * several, then click the gap they should go to. Both write the new order locally first, send it,
 * and reload from the server if it was refused, so the grid never shows an order that did not
 * stick.
 */
export function useReorderMode(deps: ReorderModeDeps): ReorderMode {
  const { success, error } = useNotifications();
  const active = ref(false);
  const selected = ref<Set<number>>(new Set());
  const draggingIndex = ref<number | null>(null);
  const dragOverIndex = ref<number | null>(null);

  function toggleMode(): void {
    if (active.value) {
      active.value = false;
      selected.value = new Set();
      return;
    }
    deps.onActivate?.();
    active.value = true;
    selected.value = new Set();
  }

  function toggleSelection(fileId: number): void {
    const next = new Set(selected.value);
    if (next.has(fileId)) next.delete(fileId);
    else next.add(fileId);
    selected.value = next;
  }

  async function persist(newFiles: AlbumFile[], successMessage?: string): Promise<void> {
    deps.files.value = newFiles;
    selected.value = new Set();
    try {
      await deps.reorderFiles(newFiles.map((f) => f.id));
      if (successMessage) success(successMessage);
    } catch (err) {
      await deps.reloadFiles();
      error(`Error reordering files: ${err instanceof Error ? err.message : "Unknown error"}`);
    }
  }

  function split(): { chosen: AlbumFile[]; rest: AlbumFile[] } {
    const ids = selected.value;
    return {
      chosen: deps.files.value.filter((f) => ids.has(f.id)),
      rest: deps.files.value.filter((f) => !ids.has(f.id)),
    };
  }

  const moved = (n: number, suffix = "") => `Moved ${n} file${n !== 1 ? "s" : ""}${suffix}.`;

  async function moveSelectedAfter(targetFileId: number): Promise<void> {
    if (selected.value.size === 0 || selected.value.has(targetFileId)) return;
    const { chosen, rest } = split();
    const targetIndex = rest.findIndex((f) => f.id === targetFileId);
    if (targetIndex === -1) return;
    await persist(
      [...rest.slice(0, targetIndex + 1), ...chosen, ...rest.slice(targetIndex + 1)],
      moved(chosen.length),
    );
  }

  async function moveSelectedToTop(): Promise<void> {
    if (selected.value.size === 0) return;
    const { chosen, rest } = split();
    await persist([...chosen, ...rest], moved(chosen.length, " to top"));
  }

  function onDragStart(event: DragEvent, index: number): void {
    draggingIndex.value = index;
    if (event.dataTransfer) event.dataTransfer.effectAllowed = "move";
  }

  function onDragOver(event: DragEvent, index: number): void {
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = "move";
    dragOverIndex.value = index;
  }

  function onDragEnter(event: DragEvent, index: number): void {
    event.preventDefault();
    dragOverIndex.value = index;
  }

  async function onDrop(event: DragEvent, dropIndex: number): Promise<void> {
    event.preventDefault();
    event.stopPropagation();
    const dragIndex = draggingIndex.value;
    onDragEnd();
    if (dragIndex === null || dragIndex === dropIndex) return;

    const newFiles = [...deps.files.value];
    const [dragged] = newFiles.splice(dragIndex, 1);
    newFiles.splice(dropIndex, 0, dragged);
    await persist(newFiles);
  }

  function onDragEnd(): void {
    draggingIndex.value = null;
    dragOverIndex.value = null;
  }

  return {
    active,
    selected,
    toggleMode,
    toggleSelection,
    moveSelectedAfter,
    moveSelectedToTop,
    draggingIndex,
    dragOverIndex,
    onDragStart,
    onDragOver,
    onDragEnter,
    onDrop,
    onDragEnd,
  };
}
