import { ref, computed, watch, type Ref, type ComputedRef } from "vue";
import { useApi } from "./useApi";
import type { AlbumFile, TagCount } from "@/types";

export interface FilesComposable {
  files: Ref<AlbumFile[]>;
  allFilesUnfiltered: Ref<AlbumFile[]>;
  loadingFiles: Ref<boolean>;
  error: Ref<string | null>;
  totalSize: Ref<number>;
  selectedTag: Ref<string>;
  tagsUsedInAlbum: ComputedRef<TagCount[]>;
  loadAlbumFiles: (
    albumId: number,
    isPresentationMode?: boolean,
  ) => Promise<void>;
  deleteFile: (fileId: number) => Promise<void>;
  addTag: (fileId: number, tagName: string) => Promise<void>;
  removeTag: (fileId: number, tagName: string) => Promise<void>;
  reorderFiles: (fileIds: number[]) => Promise<void>;
  reorderByFilename: (albumId: number) => Promise<number>;
  reorderByExif: (albumId: number) => Promise<number>;
}

/**
 * Files composable for managing file data and operations
 */
export function useFiles(): FilesComposable {
  const { apiUrl, fetchWithAuth, shareToken } = useApi();

  const files = ref<AlbumFile[]>([]);
  const allFilesUnfiltered = ref<AlbumFile[]>([]);
  const loadingFiles = ref<boolean>(false);
  const error = ref<string | null>(null);
  const totalSize = ref<number>(0);
  const selectedTag = ref<string>("");

  // Computed: Get tags actually used in files
  const tagsUsedInAlbum = computed<TagCount[]>(() => {
    const sourceFiles =
      allFilesUnfiltered.value.length > 0
        ? allFilesUnfiltered.value
        : files.value;

    if (!sourceFiles || sourceFiles.length === 0) return [];

    const tagCounts = new Map<string, number>();
    sourceFiles.forEach((file) => {
      if (file.tags && Array.isArray(file.tags)) {
        file.tags.forEach((tag) => {
          tagCounts.set(tag, (tagCounts.get(tag) || 0) + 1);
        });
      }
    });

    return Array.from(tagCounts.entries())
      .filter(([name]) => name !== "no_tag")
      .map(([name, count]) => ({ name, count }))
      .sort((a, b) => a.name.localeCompare(b.name));
  });

  // Watch for tag changes in presentation mode and update filtered files
  watch(selectedTag, (newTag) => {
    // Only apply client-side filtering if we have unfiltered data (presentation mode)
    if (allFilesUnfiltered.value.length > 0) {
      if (newTag) {
        files.value = allFilesUnfiltered.value.filter(
          (file) => file.tags && file.tags.includes(newTag),
        );
      } else {
        files.value = allFilesUnfiltered.value;
      }
    }
  });

  /**
   * Load files for an album
   */
  async function loadAlbumFiles(
    albumId: number,
    isPresentationMode: boolean = false,
  ): Promise<void> {
    if (!albumId) return;

    loadingFiles.value = true;
    error.value = null;

    try {
      let url: string;
      let response: Response;

      // In presentation mode, always load all files (no tag filtering on server)
      if (isPresentationMode) {
        if (shareToken.value) {
          // Public presentation mode - use public endpoint
          url = `${apiUrl}/api/albums/public/${shareToken.value}/files`;
          response = await fetch(url);
        } else {
          // Authenticated presentation mode - use regular endpoint without tag
          url = `${apiUrl}/api/files?albumId=${albumId}`;
          response = await fetchWithAuth(url);
        }
      } else {
        // Regular mode - use authenticated endpoint with tag filtering
        url = `${apiUrl}/api/files?albumId=${albumId}`;
        if (selectedTag.value) {
          url += `&tag=${encodeURIComponent(selectedTag.value)}`;
        }
        response = await fetchWithAuth(url);
      }

      const data = await response.json();

      if (data.success) {
        let loadedFiles: AlbumFile[] = data.files || [];

        if (isPresentationMode) {
          // In presentation mode, store all files and do client-side filtering
          allFilesUnfiltered.value = loadedFiles;

          // Filter by tag if needed
          if (selectedTag.value) {
            loadedFiles = loadedFiles.filter(
              (file) => file.tags && file.tags.includes(selectedTag.value),
            );
          }
        }

        files.value = loadedFiles;
        totalSize.value = data.totalSize || 0;

        // Store unfiltered files for tag list in non-presentation mode
        if (!isPresentationMode && !selectedTag.value) {
          allFilesUnfiltered.value = files.value;
        }
      } else {
        throw new Error("Failed to load files");
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      error.value = `Error loading photos: ${errorMessage}`;
      console.error("Error loading files:", err);
    } finally {
      loadingFiles.value = false;
    }
  }

  /**
   * Delete a file
   */
  async function deleteFile(fileId: number): Promise<void> {
    try {
      const response = await fetchWithAuth(`${apiUrl}/api/files/${fileId}`, {
        method: "DELETE",
      });

      const data = await response.json();

      if (response.ok && data.success) {
        const fileIndex = files.value.findIndex((f) => f.id === fileId);
        if (fileIndex !== -1) {
          const deletedFile = files.value[fileIndex];
          files.value.splice(fileIndex, 1);
          totalSize.value -= deletedFile.size;
        }
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error deleting file:", err);
      throw err;
    }
  }

  /**
   * Add tag to file
   */
  async function addTag(fileId: number, tagName: string): Promise<void> {
    if (!tagName) return;

    try {
      const response = await fetchWithAuth(
        `${apiUrl}/api/files/${fileId}/tags`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ tagName }),
        },
      );

      const data = await response.json();

      if (response.ok && data.success) {
        const file = files.value.find((f) => f.id === fileId);
        if (file && data.tags) {
          // Update with the tags returned from the backend
          // (backend automatically manages no_tag)
          file.tags = data.tags;
        }
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error adding tag:", err);
      throw err;
    }
  }

  /**
   * Remove tag from file
   */
  async function removeTag(fileId: number, tagName: string): Promise<void> {
    try {
      const response = await fetchWithAuth(
        `${apiUrl}/api/files/${fileId}/tags/${encodeURIComponent(tagName)}`,
        {
          method: "DELETE",
        },
      );

      const data = await response.json();

      if (response.ok && data.success) {
        const file = files.value.find((f) => f.id === fileId);
        if (file && data.tags) {
          // Update with the tags returned from the backend
          // (backend automatically manages no_tag)
          file.tags = data.tags;
        }
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error removing tag:", err);
      throw err;
    }
  }

  /**
   * Reorder files
   */
  async function reorderFiles(fileIds: number[]): Promise<void> {
    try {
      const response = await fetchWithAuth(`${apiUrl}/api/files/reorder`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ fileIds }),
      });

      const data = await response.json();

      if (!response.ok || !data.success) {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error reordering files:", err);
      throw err;
    }
  }

  /**
   * Reorder files by filename
   */
  async function reorderByFilename(albumId: number): Promise<number> {
    try {
      const response = await fetchWithAuth(
        `${apiUrl}/api/albums/${albumId}/reorder-by-filename`,
        {
          method: "POST",
        },
      );

      const data = await response.json();

      if (response.ok && data.success) {
        return data.updatedCount || 0;
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error reordering files:", err);
      throw err;
    }
  }

  /**
   * Reorder files by EXIF date
   */
  async function reorderByExif(albumId: number): Promise<number> {
    try {
      const response = await fetchWithAuth(
        `${apiUrl}/api/albums/${albumId}/reorder-by-exif`,
        {
          method: "POST",
        },
      );

      const data = await response.json();

      if (response.ok && data.success) {
        return data.updatedCount || 0;
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error reordering files by EXIF:", err);
      throw err;
    }
  }

  return {
    // State
    files,
    allFilesUnfiltered,
    loadingFiles,
    error,
    totalSize,
    selectedTag,
    tagsUsedInAlbum,

    // Methods
    loadAlbumFiles,
    deleteFile,
    addTag,
    removeTag,
    reorderFiles,
    reorderByFilename,
    reorderByExif,
  };
}
