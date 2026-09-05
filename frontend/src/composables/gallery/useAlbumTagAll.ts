import { computed, ref, watch, type ComputedRef, type Ref } from "vue";
import { useConfirm } from "../useConfirm";
import { useNotifications } from "../useNotifications";
import { assignableTags } from "@/utils/tags";
import type { Album, AlbumFile, Tag } from "@/types";

export type AlbumTagMode = "add" | "remove";

export interface AlbumTagAllDeps {
  album: Ref<Album | null>;
  files: Ref<AlbumFile[]>;
  selectedTag: Ref<string>;
  enabledAlbumTags: Ref<Tag[]>;
  addTagToAllFiles: (albumId: number, tagName: string) => Promise<number>;
  removeTagFromAllFiles: (albumId: number, tagName: string) => Promise<number>;
  reloadFiles: () => Promise<void>;
}

export interface AlbumTagAll {
  tagName: Ref<string>;
  busy: Ref<AlbumTagMode | null>;
  disabled: ComputedRef<boolean>;
  addTitle: ComputedRef<string>;
  removeTitle: ComputedRef<string>;
  run: (mode: AlbumTagMode) => Promise<void>;
}

/**
 * The "Tag all" menu: add one tag to, or remove it from, every photo in the album. The api's bulk
 * endpoints are per-tag and reject any tag outside the album's enabled list
 * (FileStorageService.addTagToAllFilesInAlbum), which is why the dropdown is fed from
 * `enabledAlbumTags`.
 */
export function useAlbumTagAll(deps: AlbumTagAllDeps): AlbumTagAll {
  const { success, info, error } = useNotifications();
  const { confirm } = useConfirm();
  const tagName = ref("");
  // Holds the mode so the spinner lands on the button that was clicked.
  const busy = ref<AlbumTagMode | null>(null);

  const disabled = computed(
    () =>
      !!busy.value ||
      !tagName.value ||
      (deps.files.value.length === 0 && !deps.selectedTag.value),
  );

  // The bulk endpoints hit every file in the album, so the scope caption must show the
  // album-wide count even when a tag filter is narrowing the grid. With no filter the loaded set
  // *is* the album and stays live across uploads/deletes; with one, fall back to the album's own
  // fileCount (AlbumService.convertToAlbumInfo counts the whole album), which can lag a little.
  const albumFileCount = computed(() =>
    deps.selectedTag.value
      ? (deps.album.value?.fileCount ?? deps.files.value.length)
      : deps.files.value.length,
  );

  // Deliberately avoids the word "all": `all` is itself a tag name here, so "add to all" reads as
  // "add the all tag".
  const scopeText = computed(() => {
    const count = albumFileCount.value;
    return `${count} photo${count !== 1 ? "s" : ""} in this album`;
  });

  const addTitle = computed(() =>
    tagName.value ? `Add "${tagName.value}" to ${scopeText.value}` : "This album has no tags available yet",
  );
  const removeTitle = computed(() =>
    tagName.value
      ? `Remove "${tagName.value}" from ${scopeText.value}`
      : "This album has no tags available yet",
  );

  // Keep the selector on a tag that still exists: the list changes when you switch albums or edit
  // it in the tag picker, and a stale name would silently 404. `hidden` is never a choice — the
  // server derives it (D79) and the dropdown does not list it.
  watch(
    deps.enabledAlbumTags,
    (enabled) => {
      const tags = assignableTags(enabled);
      if (!tags.some((t) => t.name === tagName.value)) {
        tagName.value = tags.length > 0 ? tags[0].name : "";
      }
    },
    { immediate: true },
  );

  async function run(mode: AlbumTagMode): Promise<void> {
    const album = deps.album.value;
    const name = tagName.value;
    if (!album || busy.value || !name) return;
    const removing = mode === "remove";

    // The endpoints sweep the whole album, so spell out the blast radius here.
    const filterNote = deps.selectedTag.value
      ? ` This ignores the active "${deps.selectedTag.value}" filter.`
      : "";
    const confirmed = await confirm(
      (removing ? `Remove "${name}" from ${scopeText.value}?` : `Add "${name}" to ${scopeText.value}?`) +
        filterNote,
      { type: "warning", confirmText: removing ? "Remove everywhere" : "Add everywhere" },
    );
    if (!confirmed) return;

    busy.value = mode;
    try {
      const count = removing
        ? await deps.removeTagFromAllFiles(album.id, name)
        : await deps.addTagToAllFiles(album.id, name);
      await deps.reloadFiles();
      if (count === 0) {
        info(removing ? `No photos had the "${name}" tag.` : `Every photo already has the "${name}" tag.`);
      } else {
        const plural = count !== 1 ? "s" : "";
        success(
          removing ? `Removed "${name}" from ${count} photo${plural}` : `Tagged ${count} photo${plural} with "${name}"`,
        );
      }
    } catch (err) {
      error(`Error updating "${name}": ${err instanceof Error ? err.message : "Unknown error"}`);
    } finally {
      busy.value = null;
    }
  }

  return { tagName, busy, disabled, addTitle, removeTitle, run };
}
