import { ref, type Ref } from "vue";
import { useConfirm } from "../useConfirm";
import { useNotifications } from "../useNotifications";
import type { GroupPayload } from "../usePresentationGroups";
import type { Album, PresentationGroup } from "@/types";

export interface GroupEditingDeps {
  album: Ref<Album | null>;
  selectedTag: Ref<string>;
  createGroup: (
    albumId: number,
    tag: string,
    startFileId: number,
    payload: GroupPayload,
  ) => Promise<PresentationGroup>;
  updateGroup: (groupId: number, payload: GroupPayload) => Promise<PresentationGroup>;
  deleteGroup: (groupId: number) => Promise<void>;
  setGroupEnd: (groupId: number, endFileId: number | null) => Promise<PresentationGroup>;
}

export interface GroupEditing {
  dialogOpen: Ref<boolean>;
  dialogMode: Ref<"create" | "edit">;
  dialogSaving: Ref<boolean>;
  dialogTarget: Ref<PresentationGroup | null>;
  openCreate: (fileId: number) => void;
  openEdit: (group: PresentationGroup) => void;
  save: (label: string, text: string | null) => Promise<void>;
  remove: (group: PresentationGroup) => Promise<void>;
  toggleEnd: (group: PresentationGroup | null, fileId: number) => Promise<void>;
}

/** Creating, renaming, ending and removing presentation image groups from the gallery. */
export function useGroupEditing(deps: GroupEditingDeps): GroupEditing {
  const { success, warning, error } = useNotifications();
  const { confirm } = useConfirm();

  const dialogOpen = ref(false);
  const dialogMode = ref<"create" | "edit">("create");
  const dialogSaving = ref(false);
  const dialogTarget = ref<PresentationGroup | null>(null);
  const anchorFileId = ref<number | null>(null);

  function openCreate(fileId: number): void {
    if (!deps.selectedTag.value) {
      warning("Select a tag filter first — groups belong to one tag.");
      return;
    }
    dialogMode.value = "create";
    dialogTarget.value = null;
    anchorFileId.value = fileId;
    dialogOpen.value = true;
  }

  function openEdit(group: PresentationGroup): void {
    dialogMode.value = "edit";
    dialogTarget.value = group;
    anchorFileId.value = null;
    dialogOpen.value = true;
  }

  async function save(label: string, text: string | null): Promise<void> {
    if (!deps.album.value) return;
    dialogSaving.value = true;
    try {
      if (dialogMode.value === "edit" && dialogTarget.value) {
        await deps.updateGroup(dialogTarget.value.id, { label, text });
        success("Group updated.");
      } else if (anchorFileId.value !== null) {
        await deps.createGroup(deps.album.value.id, deps.selectedTag.value, anchorFileId.value, {
          label,
          text,
        });
        success("Group created.");
      }
      dialogOpen.value = false;
    } catch (err) {
      error("Could not save group: " + (err instanceof Error ? err.message : "Unknown error"));
    } finally {
      dialogSaving.value = false;
    }
  }

  async function remove(group: PresentationGroup): Promise<void> {
    const confirmed = await confirm(
      `Remove the group "${group.label}"? The photos stay exactly where they are.`,
      { confirmText: "Remove group", type: "danger" },
    );
    if (!confirmed) return;
    try {
      await deps.deleteGroup(group.id);
      success("Group removed.");
    } catch (err) {
      error("Could not remove group: " + (err instanceof Error ? err.message : "Unknown error"));
    }
  }

  // Ending a group is a toggle on the photo: clicking the photo that already ends it reopens the
  // group, so it runs on to the next one again.
  async function toggleEnd(group: PresentationGroup | null, fileId: number): Promise<void> {
    if (!group) return;
    const reopening = group.endFileId === fileId;
    try {
      await deps.setGroupEnd(group.id, reopening ? null : fileId);
      success(
        reopening
          ? `"${group.label}" runs on until the next group again.`
          : `"${group.label}" ends at this photo.`,
      );
    } catch (err) {
      error("Could not change the group end: " + (err instanceof Error ? err.message : "Unknown error"));
    }
  }

  return { dialogOpen, dialogMode, dialogSaving, dialogTarget, openCreate, openEdit, save, remove, toggleEnd };
}
