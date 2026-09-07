import { computed, ref, type ComputedRef, type Ref } from "vue";
import { useNotifications } from "../useNotifications";
import { backgroundPhotoFor, isTextCard } from "@/utils/format";
import type { AlbumFile } from "@/types";

export interface TextCardsDeps {
  albumId: Ref<number> | ComputedRef<number>;
  files: Ref<AlbumFile[]>;
  createTextCard: (albumId: number, headline: string, bodyText: string) => Promise<AlbumFile>;
  updateTextCard: (fileId: number, headline: string, bodyText: string) => Promise<void>;
}

export interface TextCards {
  open: Ref<boolean>;
  mode: Ref<"create" | "edit">;
  saving: Ref<boolean>;
  headline: Ref<string>;
  bodyText: Ref<string>;
  openCreate: () => void;
  openEdit: (fileId: number) => void;
  close: () => void;
  save: (headline: string, bodyText: string) => Promise<void>;
  /** The photo one card borrows its blurred background from, or null when there is none. */
  backgroundFor: (file: AlbumFile) => AlbumFile | null;
}

/**
 * Writing and editing text cards from the gallery (D86).
 *
 * A card is a chapter heading standing in the album's order where a photo would stand. It carries
 * no pixels of its own, so each card is drawn over the next actual picture after it, blurred — and
 * that neighbour is worked out here, from the list the reader is looking at, because only the list
 * knows what "next" means and it changes on every reorder and every tag filter.
 */
export function useTextCards(deps: TextCardsDeps): TextCards {
  const { success, error } = useNotifications();

  const open = ref(false);
  const mode = ref<"create" | "edit">("create");
  const saving = ref(false);
  const headline = ref("");
  const bodyText = ref("");
  const editingId = ref<number | null>(null);

  /**
   * Card id → the photo behind it, rebuilt whenever the list changes. A map rather than a scan
   * per tile: an album of several hundred entries would otherwise walk the tail of the list once
   * for every card on screen.
   */
  const backgrounds = computed(() => {
    const map = new Map<number, AlbumFile>();
    deps.files.value.forEach((file, index) => {
      if (!isTextCard(file)) return;
      const behind = backgroundPhotoFor(deps.files.value, index);
      if (behind) map.set(file.id, behind);
    });
    return map;
  });

  function backgroundFor(file: AlbumFile): AlbumFile | null {
    if (!isTextCard(file)) return null;
    return backgrounds.value.get(file.id) ?? null;
  }

  function openCreate(): void {
    mode.value = "create";
    editingId.value = null;
    headline.value = "";
    bodyText.value = "";
    open.value = true;
  }

  function openEdit(fileId: number): void {
    const card = deps.files.value.find((f) => f.id === fileId);
    if (!card) return;
    mode.value = "edit";
    editingId.value = fileId;
    headline.value = card.headline ?? card.originalName ?? "";
    bodyText.value = card.bodyText ?? "";
    open.value = true;
  }

  function close(): void {
    if (saving.value) return;
    open.value = false;
  }

  async function save(newHeadline: string, newBodyText: string): Promise<void> {
    saving.value = true;
    try {
      if (mode.value === "edit" && editingId.value !== null) {
        await deps.updateTextCard(editingId.value, newHeadline, newBodyText);
        success("Card updated.");
      } else {
        await deps.createTextCard(deps.albumId.value, newHeadline, newBodyText);
        // Said out loud because the card lands at the *end* of the album, which is rarely where
        // the chapter it names begins — the next move is a drag, and the user has to know that.
        success("Card added at the end of the album — drag it where the chapter starts.");
      }
      open.value = false;
    } catch (err) {
      error(
        "Could not save the card: " + (err instanceof Error ? err.message : "Unknown error"),
      );
    } finally {
      saving.value = false;
    }
  }

  return {
    open,
    mode,
    saving,
    headline,
    bodyText,
    openCreate,
    openEdit,
    close,
    save,
    backgroundFor,
  };
}
