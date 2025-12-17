import { ref, type Ref } from "vue";
import { useApi } from "./useApi";
import type { Tag } from "@/types";

// Shared tags state across the app
const availableTags = ref<Tag[]>([]);
const loading = ref<boolean>(false);
const error = ref<string | null>(null);

export interface TagsComposable {
  availableTags: Ref<Tag[]>;
  loading: Ref<boolean>;
  error: Ref<string | null>;
  loadTags: () => Promise<void>;
  createTag: (tagName: string) => Promise<Tag>;
  updateTag: (tagId: number, newTagName: string) => Promise<Tag | undefined>;
  deleteTag: (tagId: number) => Promise<void>;
}

/**
 * Tags composable for managing tags
 */
export function useTags(): TagsComposable {
  const { apiUrl, fetchWithAuth } = useApi();

  /**
   * Load all tags
   */
  async function loadTags(): Promise<void> {
    loading.value = true;
    error.value = null;

    try {
      const response = await fetchWithAuth(`${apiUrl}/api/tags`);
      const data = await response.json();

      if (data.success) {
        availableTags.value = data.tags || [];
      } else {
        throw new Error("Failed to load tags");
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      error.value = `Error loading tags: ${errorMessage}`;
      console.error("Error loading tags:", err);
    } finally {
      loading.value = false;
    }
  }

  /**
   * Create a new tag
   */
  async function createTag(tagName: string): Promise<Tag> {
    if (!tagName || tagName.trim() === "") {
      throw new Error("Tag name is required");
    }

    try {
      const response = await fetchWithAuth(`${apiUrl}/api/tags`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ tagName: tagName.trim() }),
      });

      const data = await response.json();

      if (response.ok && data.success) {
        if (data.tag) {
          availableTags.value.push(data.tag);
        }
        return data.tag;
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error creating tag:", err);
      throw err;
    }
  }

  /**
   * Update a tag
   */
  async function updateTag(
    tagId: number,
    newTagName: string,
  ): Promise<Tag | undefined> {
    if (!newTagName || newTagName.trim() === "") {
      throw new Error("Tag name is required");
    }

    try {
      const response = await fetchWithAuth(`${apiUrl}/api/tags/${tagId}`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ tagName: newTagName.trim() }),
      });

      const data = await response.json();

      if (response.ok && data.success) {
        const tag = availableTags.value.find((t) => t.id === tagId);
        if (tag) {
          tag.name = newTagName.trim();
        }
        return tag;
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error updating tag:", err);
      throw err;
    }
  }

  /**
   * Delete a tag
   */
  async function deleteTag(tagId: number): Promise<void> {
    try {
      const response = await fetchWithAuth(`${apiUrl}/api/tags/${tagId}`, {
        method: "DELETE",
      });

      const data = await response.json();

      if (response.ok && data.success) {
        const tagIndex = availableTags.value.findIndex((t) => t.id === tagId);
        if (tagIndex !== -1) {
          availableTags.value.splice(tagIndex, 1);
        }
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error deleting tag:", err);
      throw err;
    }
  }

  return {
    // State
    availableTags,
    loading,
    error,

    // Methods
    loadTags,
    createTag,
    updateTag,
    deleteTag,
  };
}
