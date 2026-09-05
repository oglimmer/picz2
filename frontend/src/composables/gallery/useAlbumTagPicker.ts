import { computed, ref, type ComputedRef, type Ref } from "vue";
import { useNotifications } from "../useNotifications";
import type { Album, Tag } from "@/types";

export const ALL_TAG = "all";
export const HIDDEN_TAG = "hidden";
/**
 * Neither can be renamed, deleted, or switched off per album — the server always enables both, so
 * they are dropped from the album's tag picker rather than shown as permanently ticked. They stay
 * ordinary tags everywhere else: `hidden` in particular has to be filterable and bulk-removable,
 * because taking it off is how the owner publishes a photo (D70).
 */
export const SYSTEM_TAGS: ReadonlySet<string> = new Set([ALL_TAG, HIDDEN_TAG]);

export interface AlbumTagPickerDeps {
  album: Ref<Album | null>;
  availableTags: Ref<Tag[]>;
  enabledAlbumTags: Ref<Tag[]>;
  setEnabledAlbumTags: (albumId: number, tagIds: number[]) => Promise<void>;
}

export interface AlbumTagPicker {
  open: Ref<boolean>;
  selectedTagIds: Ref<Set<number>>;
  saving: Ref<boolean>;
  togglableTags: ComputedRef<Tag[]>;
  toggleOpen: () => void;
  close: () => void;
  toggleTag: (tagId: number) => void;
  save: () => Promise<void>;
}

/** The "Album tags" panel: which of the user's tags this album may use. */
export function useAlbumTagPicker(deps: AlbumTagPickerDeps): AlbumTagPicker {
  const { success, error } = useNotifications();
  const open = ref(false);
  const selectedTagIds = ref<Set<number>>(new Set());
  const saving = ref(false);

  const togglableTags = computed(() =>
    deps.availableTags.value.filter((t) => !SYSTEM_TAGS.has(t.name)),
  );

  function toggleOpen(): void {
    if (open.value) {
      close();
      return;
    }
    // Seed from currently enabled tags, minus the system ones — they can't be toggled.
    selectedTagIds.value = new Set(
      deps.enabledAlbumTags.value.filter((t) => !SYSTEM_TAGS.has(t.name)).map((t) => t.id),
    );
    open.value = true;
  }

  function close(): void {
    open.value = false;
    selectedTagIds.value = new Set();
  }

  function toggleTag(tagId: number): void {
    const next = new Set(selectedTagIds.value);
    if (next.has(tagId)) next.delete(tagId);
    else next.add(tagId);
    selectedTagIds.value = next;
  }

  async function save(): Promise<void> {
    if (!deps.album.value) return;
    saving.value = true;
    try {
      await deps.setEnabledAlbumTags(deps.album.value.id, [...selectedTagIds.value]);
      success("Album tags updated.");
      close();
    } catch (err) {
      error(`Error saving enabled tags: ${err instanceof Error ? err.message : "Unknown error"}`);
    } finally {
      saving.value = false;
    }
  }

  return { open, selectedTagIds, saving, togglableTags, toggleOpen, close, toggleTag, save };
}
