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
    endFileId?: number | null,
  ) => Promise<PresentationGroup>;
  updateGroup: (
    groupId: number,
    payload: GroupPayload,
  ) => Promise<PresentationGroup>;
  deleteGroup: (groupId: number) => Promise<void>;
  setGroupEnd: (
    groupId: number,
    endFileId: number | null,
  ) => Promise<PresentationGroup>;
  groupStartingAt: (
    fileId: number,
    tag: string,
  ) => PresentationGroup | undefined;
  groupEndingAt: (fileId: number, tag: string) => PresentationGroup | undefined;
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
 *
 * A group may also carry an end marker (`endFileId`) — the last image that still belongs to it.
 * That is how a section stops without the next one starting: the images after it fall back into a
 * headingless run. An end that is missing from the list, or that has drifted in front of its own
 * start, is never reached by the walk, so the group just stays open-ended.
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
    endFileId: number | null = null,
  ): Promise<PresentationGroup> {
    const response = await fetchWithAuth(
      `${apiUrl}/api/albums/${albumId}/presentation-groups`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          tag,
          startFileId,
          endFileId,
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

  /**
   * Moves or clears the image a group stops at. Its own endpoint rather than a field on the
   * update body, so a client that never sends the field cannot silently wipe an end marker.
   */
  async function setGroupEnd(
    groupId: number,
    endFileId: number | null,
  ): Promise<PresentationGroup> {
    const response = await fetchWithAuth(
      `${apiUrl}/api/presentation-groups/${groupId}/end`,
      {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ endFileId }),
      },
    );

    const data = await response.json();

    if (!response.ok || !data.success) {
      throw new Error(data.message || "Unknown error");
    }

    groups.value = groups.value.map((g) => (g.id === groupId ? data.group : g));
    return data.group;
  }

  function groupStartingAt(
    fileId: number,
    tag: string,
  ): PresentationGroup | undefined {
    if (!tag) return undefined;
    return groups.value.find((g) => g.tag === tag && g.startFileId === fileId);
  }

  function groupEndingAt(
    fileId: number,
    tag: string,
  ): PresentationGroup | undefined {
    if (!tag) return undefined;
    return groups.value.find((g) => g.tag === tag && g.endFileId === fileId);
  }

  function buildSections(
    files: AlbumFile[],
    tag: string,
  ): PresentationSection[] {
    const tagGroups = tag ? groups.value.filter((g) => g.tag === tag) : [];

    if (tagGroups.length === 0) {
      return files.length > 0 ? [{ group: null, files, closed: false }] : [];
    }

    const byStartFile = new Map<number, PresentationGroup>(
      tagGroups.map((g) => [g.startFileId, g]),
    );

    const sections: PresentationSection[] = [];
    let current: PresentationSection = { group: null, files: [], closed: false };

    for (const file of files) {
      const starting = byStartFile.get(file.id);
      if (starting) {
        // Drop the leading section when the very first image already starts a group.
        if (current.group || current.files.length > 0) {
          sections.push(current);
        }
        current = { group: starting, files: [], closed: false };
      }
      current.files.push(file);

      // A group that names this image as its end closes here, and what follows falls back into a
      // headingless run. Only the open group's own end counts, so an end belonging to some other
      // group — or one sitting in front of its own start — is simply never reached.
      if (current.group && current.group.endFileId === file.id) {
        current.closed = true;
        sections.push(current);
        current = { group: null, files: [], closed: false };
      }
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
    setGroupEnd,
    groupStartingAt,
    groupEndingAt,
    buildSections,
    groupContextFor,
  };
}
