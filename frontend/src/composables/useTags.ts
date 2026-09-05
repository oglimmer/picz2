import { ref, type Ref } from "vue";
import { useApi, jsonBody } from "./useApi";
import type { Tag } from "@/types";

interface TagsResponse {
  tags?: Tag[];
}

interface TagResponse {
  tag?: Tag;
}

// Module singleton (see README.md): the tag list is one app-wide fact, read by the albums page,
// the gallery and the tag manager at the same time.
const availableTags = ref<Tag[]>([]);
const enabledAlbumTags = ref<Tag[]>([]);
const loading = ref<boolean>(false);
const error = ref<string | null>(null);

export interface TagsComposable {
  availableTags: Ref<Tag[]>;
  enabledAlbumTags: Ref<Tag[]>;
  loading: Ref<boolean>;
  error: Ref<string | null>;
  loadTags: () => Promise<void>;
  createTag: (tagName: string) => Promise<Tag>;
  updateTag: (tagId: number, newTagName: string) => Promise<Tag | undefined>;
  deleteTag: (tagId: number) => Promise<void>;
  loadEnabledAlbumTags: (albumId: number) => Promise<void>;
  setEnabledAlbumTags: (albumId: number, tagIds: number[]) => Promise<void>;
  clearEnabledAlbumTags: () => void;
}

export function useTags(): TagsComposable {
  const { apiUrl, requestJson } = useApi();

  async function loadTags(): Promise<void> {
    loading.value = true;
    error.value = null;
    try {
      const data = await requestJson<TagsResponse>(`${apiUrl}/api/tags`);
      availableTags.value = data.tags || [];
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      error.value = `Error loading tags: ${errorMessage}`;
    } finally {
      loading.value = false;
    }
  }

  async function createTag(tagName: string): Promise<Tag> {
    if (!tagName || tagName.trim() === "") {
      throw new Error("Tag name is required");
    }
    const data = await requestJson<TagResponse>(
      `${apiUrl}/api/tags`,
      jsonBody("POST", { tagName: tagName.trim() }),
    );
    if (!data.tag) throw new Error("The server returned no tag");
    availableTags.value.push(data.tag);
    return data.tag;
  }

  async function updateTag(tagId: number, newTagName: string): Promise<Tag | undefined> {
    if (!newTagName || newTagName.trim() === "") {
      throw new Error("Tag name is required");
    }
    await requestJson(`${apiUrl}/api/tags/${tagId}`, jsonBody("PUT", { tagName: newTagName.trim() }));
    const tag = availableTags.value.find((t) => t.id === tagId);
    if (tag) tag.name = newTagName.trim();
    return tag;
  }

  async function deleteTag(tagId: number): Promise<void> {
    await requestJson(`${apiUrl}/api/tags/${tagId}`, { method: "DELETE" });
    const tagIndex = availableTags.value.findIndex((t) => t.id === tagId);
    if (tagIndex !== -1) availableTags.value.splice(tagIndex, 1);
  }

  /** Non-fatal: an album with no readable enabled-tag list simply shows none. */
  async function loadEnabledAlbumTags(albumId: number): Promise<void> {
    try {
      const data = await requestJson<TagsResponse>(`${apiUrl}/api/albums/${albumId}/enabled-tags`);
      enabledAlbumTags.value = data.tags || [];
    } catch {
      enabledAlbumTags.value = [];
    }
  }

  async function setEnabledAlbumTags(albumId: number, tagIds: number[]): Promise<void> {
    const data = await requestJson<TagsResponse>(
      `${apiUrl}/api/albums/${albumId}/enabled-tags`,
      jsonBody("PUT", { tagIds }),
    );
    enabledAlbumTags.value = data.tags || [];
  }

  function clearEnabledAlbumTags(): void {
    enabledAlbumTags.value = [];
  }

  return {
    availableTags,
    enabledAlbumTags,
    loading,
    error,
    loadTags,
    createTag,
    updateTag,
    deleteTag,
    loadEnabledAlbumTags,
    setEnabledAlbumTags,
    clearEnabledAlbumTags,
  };
}
