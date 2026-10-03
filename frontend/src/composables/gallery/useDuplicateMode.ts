import { computed, ref, type ComputedRef, type Ref } from "vue";
import type { AlbumFile } from "@/types";
import { isTextCard } from "@/utils/format";

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
 * A JPEG and a HEIC of the same shot are the same photo, so these extensions share one key.
 * A video is left out on purpose: a Live Photo's IMG_1.MOV belongs to IMG_1.HEIC and is no copy.
 */
const SAME_PHOTO_EXTENSIONS = new Set(["jpg", "jpeg", "heic", "heif"]);

/**
 * iOS exports every edited Live Photo as "FullSizeRender.heic", so that name is never a duplicate
 * worth flagging.
 */
const EXCLUDED_DUPLICATE_STEM = "fullsizerender";

function nameOf(file: AlbumFile): string {
  return file.originalName || file.filename || "";
}

/** "IMG_1.jpg", "IMG_1.JPEG" and "IMG_1.heic" all give "IMG_1.jpg"; any other name is itself. */
function keyOf(file: AlbumFile): string {
  const name = nameOf(file);
  const dot = name.lastIndexOf(".");
  if (dot <= 0) return name;
  if (!SAME_PHOTO_EXTENSIONS.has(name.slice(dot + 1).toLowerCase())) return name;
  return `${name.slice(0, dot)}.jpg`;
}

/** A text card's name is its headline (D86), and two chapters may well share one. */
function isExcluded(file: AlbumFile): boolean {
  if (isTextCard(file)) return true;
  return keyOf(file).toLowerCase() === `${EXCLUDED_DUPLICATE_STEM}.jpg`;
}

/**
 * "Find duplicate names": narrows the grid to files whose name another file also carries, and
 * pre-selects every copy but the first so one click removes the extras. A JPEG and a HEIC that
 * differ only in the extension count as the same name.
 */
export function useDuplicateMode(deps: DuplicateModeDeps): DuplicateMode {
  const active = ref(false);
  const selected = ref<Set<number>>(new Set());

  const displayedFiles = computed(() => {
    if (!active.value) return deps.files.value;
    const counts = new Map<string, number>();
    for (const file of deps.files.value) {
      if (isExcluded(file)) continue;
      counts.set(keyOf(file), (counts.get(keyOf(file)) || 0) + 1);
    }
    return deps.files.value.filter((f) => !isExcluded(f) && (counts.get(keyOf(f)) || 0) > 1);
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
      const key = keyOf(file);
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
