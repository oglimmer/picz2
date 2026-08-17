import { ref, type Ref } from "vue";
import { useApi } from "./useApi";
import type { AlbumFile, PresentationGroup, PresentationSection } from "@/types";

export interface GroupPayload {
  label: string;
  text?: string | null;
}

// What the lightbox shows for the image currently zoomed in on.
export interface GroupContext {
  id: number;
  label: string;
  text?: string | null;
  position: number;
  total: number;
}

export interface PresentationGroupsComposable {
  groups: Ref<PresentationGroup[]>;
  loadingGroups: Ref<boolean>;
  loadGroups: (albumId: number) => Promise<void>;
  loadPublicGroups: (shareToken: string) => Promise<void>;
  createGroup: (
    albumId: number,
    tag: string,
    startFileId: number,
    payload: GroupPayload,
  ) => Promise<PresentationGroup>;
  updateGroup: (
    groupId: number,
    payload: GroupPayload,
  ) => Promise<PresentationGroup>;
  deleteGroup: (groupId: number) => Promise<void>;
  groupStartingAt: (
    fileId: number,
    tag: string,
  ) => PresentationGroup | undefined;
  hasGroups: (tag: string) => boolean;
  buildSections: (files: AlbumFile[], tag: string) => PresentationSection[];
  groupContextFor: (
    sections: PresentationSection[],
    fileId: number | null | undefined,
  ) => GroupContext | null;
}

/**
 * Presentation image groups — labelled sections inside the presentation view of one tag.
 *
 * A group is a marker on the image it starts at, not a membership list: sections are derived by
 * walking the tag-filtered file list in its existing display order. That means reordering images
 * reshuffles the sections with no extra bookkeeping, and a group whose anchor is missing from the
 * current list (untagged, deleted, filtered out) simply doesn't render.
 */
export function usePresentationGroups(): PresentationGroupsComposable {
  const { apiUrl, fetchWithAuth } = useApi();

  const groups = ref<PresentationGroup[]>([]);
  const loadingGroups = ref<boolean>(false);

  async function loadGroups(albumId: number): Promise<void> {
    if (!albumId) return;

    loadingGroups.value = true;
    try {
      const response = await fetchWithAuth(
        `${apiUrl}/api/albums/${albumId}/presentation-groups`,
      );
      const data = await response.json();

      if (response.ok && data.success) {
        groups.value = data.groups || [];
      }
    } catch (err) {
      // Non-fatal: the presentation still renders, just without sections.
      console.error("Error loading presentation groups:", err);
    } finally {
      loadingGroups.value = false;
    }
  }

  async function loadPublicGroups(shareToken: string): Promise<void> {
    if (!shareToken) return;

    loadingGroups.value = true;
    try {
      const response = await fetch(
        `${apiUrl}/api/albums/public/${shareToken}/presentation-groups`,
      );
      const data = await response.json();

      if (response.ok && data.success) {
        groups.value = data.groups || [];
      }
    } catch (err) {
      console.error("Error loading presentation groups:", err);
    } finally {
      loadingGroups.value = false;
    }
  }

  async function createGroup(
    albumId: number,
    tag: string,
    startFileId: number,
    payload: GroupPayload,
  ): Promise<PresentationGroup> {
    const response = await fetchWithAuth(
      `${apiUrl}/api/albums/${albumId}/presentation-groups`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          tag,
          startFileId,
          label: payload.label,
          text: payload.text ?? null,
        }),
      },
    );

    const data = await response.json();

    if (!response.ok || !data.success) {
      throw new Error(data.message || "Unknown error");
    }

    groups.value = [...groups.value, data.group];
    return data.group;
  }

  async function updateGroup(
    groupId: number,
    payload: GroupPayload,
  ): Promise<PresentationGroup> {
    const response = await fetchWithAuth(
      `${apiUrl}/api/presentation-groups/${groupId}`,
      {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          label: payload.label,
          text: payload.text ?? null,
        }),
      },
    );

    const data = await response.json();

    if (!response.ok || !data.success) {
      throw new Error(data.message || "Unknown error");
    }

    groups.value = groups.value.map((g) => (g.id === groupId ? data.group : g));
    return data.group;
  }

  async function deleteGroup(groupId: number): Promise<void> {
    const response = await fetchWithAuth(
      `${apiUrl}/api/presentation-groups/${groupId}`,
      { method: "DELETE" },
    );

    const data = await response.json();

    if (!response.ok || !data.success) {
      throw new Error(data.message || "Unknown error");
    }

    groups.value = groups.value.filter((g) => g.id !== groupId);
  }

  function groupStartingAt(
    fileId: number,
    tag: string,
  ): PresentationGroup | undefined {
    if (!tag) return undefined;
    return groups.value.find((g) => g.tag === tag && g.startFileId === fileId);
  }

  function hasGroups(tag: string): boolean {
    if (!tag) return false;
    return groups.value.some((g) => g.tag === tag);
  }

  function buildSections(
    files: AlbumFile[],
    tag: string,
  ): PresentationSection[] {
    const tagGroups = tag ? groups.value.filter((g) => g.tag === tag) : [];

    if (tagGroups.length === 0) {
      return files.length > 0 ? [{ group: null, files }] : [];
    }

    const byStartFile = new Map<number, PresentationGroup>(
      tagGroups.map((g) => [g.startFileId, g]),
    );

    const sections: PresentationSection[] = [];
    let current: PresentationSection = { group: null, files: [] };

    for (const file of files) {
      const starting = byStartFile.get(file.id);
      if (starting) {
        // Drop the leading section when the very first image already starts a group.
        if (current.group || current.files.length > 0) {
          sections.push(current);
        }
        current = { group: starting, files: [] };
      }
      current.files.push(file);
    }

    if (current.group || current.files.length > 0) {
      sections.push(current);
    }

    return sections;
  }

  /**
   * Which group the zoomed-in image sits in, plus its place within that group. Returns null for
   * images ahead of the first group — those genuinely belong to no group, and an empty hint would
   * read as a bug.
   */
  function groupContextFor(
    sections: PresentationSection[],
    fileId: number | null | undefined,
  ): GroupContext | null {
    if (fileId == null) return null;

    for (const section of sections) {
      const index = section.files.findIndex((f) => f.id === fileId);
      if (index === -1) continue;
      if (!section.group) return null;

      return {
        id: section.group.id,
        label: section.group.label,
        text: section.group.text ?? null,
        position: index + 1,
        total: section.files.length,
      };
    }

    return null;
  }

  return {
    groups,
    loadingGroups,
    loadGroups,
    loadPublicGroups,
    createGroup,
    updateGroup,
    deleteGroup,
    groupStartingAt,
    hasGroups,
    buildSections,
    groupContextFor,
  };
}
