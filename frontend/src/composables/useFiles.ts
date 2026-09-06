import { ref, computed, watch, type Ref, type ComputedRef } from "vue";
import { useApi, jsonBody } from "./useApi";
import { useStorageUsage } from "./useStorageUsage";
import { countTags } from "../utils/tags";
import type { AlbumFile, TagCount } from "@/types";

interface FilesResponse {
  files?: AlbumFile[];
  totalSize?: number;
}

interface TagsResponse {
  tags?: string[];
}

interface CountResponse {
  updatedCount?: number;
}

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
  rotateFile: (fileId: number) => Promise<void>;
  enhanceFile: (fileId: number) => Promise<void>;
  requestEnhancePreview: (fileId: number) => Promise<void>;
  loadEnhancePreview: (fileId: number) => Promise<string>;
  discardEnhancePreview: (fileId: number) => Promise<void>;
  addTag: (fileId: number, tagName: string) => Promise<void>;
  removeTag: (fileId: number, tagName: string) => Promise<void>;
  updateCaption: (fileId: number, caption: string) => Promise<void>;
  addTagToAllFiles: (albumId: number, tagName: string) => Promise<number>;
  removeTagFromAllFiles: (albumId: number, tagName: string) => Promise<number>;
  reorderFiles: (fileIds: number[]) => Promise<void>;
  reorderByFilename: (albumId: number) => Promise<number>;
  reorderByExif: (albumId: number) => Promise<number>;
}

/**
 * The files of one album and everything that changes them. Per-instance state (see README.md):
 * the gallery view calls this once and owns the list.
 */
export function useFiles(): FilesComposable {
  const { apiUrl, requestJson, requestPublicJson, fetchWithAuth, shareToken } = useApi();
  const { refresh: refreshStorageUsage } = useStorageUsage();

  const files = ref<AlbumFile[]>([]);
  const allFilesUnfiltered = ref<AlbumFile[]>([]);
  const loadingFiles = ref<boolean>(false);
  const error = ref<string | null>(null);
  const totalSize = ref<number>(0);
  const selectedTag = ref<string>("");
  // Bumped per load; a response for an older load is dropped, so switching albums quickly can
  // never leave the previous album's files on screen.
  let loadSeq = 0;

  // Tags actually carried by the album's files, with counts, for the presentation filter.
  const tagsUsedInAlbum = computed<TagCount[]>(() =>
    countTags(
      allFilesUnfiltered.value.length > 0 ? allFilesUnfiltered.value : files.value,
    ),
  );

  // Presentation mode holds the whole album and filters it here; the logged-in gallery reloads
  // from the server instead (its own watcher), in which case `allFilesUnfiltered` is empty.
  watch(selectedTag, (newTag) => {
    if (allFilesUnfiltered.value.length > 0) {
      files.value = newTag
        ? allFilesUnfiltered.value.filter((file) => file.tags?.includes(newTag))
        : allFilesUnfiltered.value;
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

    const seq = ++loadSeq;
    loadingFiles.value = true;
    error.value = null;

    try {
      let data: FilesResponse;
      if (isPresentationMode) {
        // Presentation mode always loads the whole album and filters client-side.
        data = shareToken.value
          ? await requestPublicJson<FilesResponse>(
              `${apiUrl}/api/albums/public/${shareToken.value}/files`,
            )
          : await requestJson<FilesResponse>(`${apiUrl}/api/files?albumId=${albumId}`);
      } else {
        let url = `${apiUrl}/api/files?albumId=${albumId}`;
        if (selectedTag.value) {
          url += `&tag=${encodeURIComponent(selectedTag.value)}`;
        }
        data = await requestJson<FilesResponse>(url);
      }
      if (seq !== loadSeq) return;

      let loadedFiles: AlbumFile[] = data.files || [];

      if (isPresentationMode) {
        allFilesUnfiltered.value = loadedFiles;
        if (selectedTag.value) {
          loadedFiles = loadedFiles.filter((file) => file.tags?.includes(selectedTag.value));
        }
      }

      files.value = loadedFiles;
      totalSize.value = data.totalSize || 0;

      // Unfiltered copy for the tag list in the logged-in gallery.
      if (!isPresentationMode && !selectedTag.value) {
        allFilesUnfiltered.value = files.value;
      }
    } catch (err) {
      if (seq !== loadSeq) return;
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      error.value = `Error loading photos: ${errorMessage}`;
    } finally {
      if (seq === loadSeq) loadingFiles.value = false;
    }
  }

  /** Patches every copy of a file — both lists can hold it in presentation mode. */
  function patchFile(fileId: number, patch: (file: AlbumFile) => void): void {
    for (const list of [files.value, allFilesUnfiltered.value]) {
      const file = list.find((f) => f.id === fileId);
      if (file) patch(file);
    }
  }

  async function deleteFile(fileId: number): Promise<void> {
    await requestJson(`${apiUrl}/api/files/${fileId}`, { method: "DELETE" });
    // Deleting is the one way a user frees room on the site's storage, so the "storage full"
    // banner is asked to re-check straight away rather than on its next poll.
    void refreshStorageUsage();
    const index = files.value.findIndex((f) => f.id === fileId);
    if (index !== -1) {
      const [deleted] = files.value.splice(index, 1);
      totalSize.value -= deleted.size;
    }
    const unfilteredIndex = allFilesUnfiltered.value.findIndex((f) => f.id === fileId);
    if (unfilteredIndex !== -1) allFilesUnfiltered.value.splice(unfilteredIndex, 1);
  }

  /**
   * Asks the worker to turn the image left by 90° (Phase 4.5: the api answers 202 and the job runs
   * later). The local status flips to QUEUED at once so the tile shows its spinner; the processing
   * poller brings it back to DONE when the derivatives are rewritten.
   */
  async function rotateFile(fileId: number): Promise<void> {
    await requestJson(`${apiUrl}/api/files/${fileId}/rotate`, { method: "POST" });
    patchFile(fileId, (file) => {
      file.processingStatus = "QUEUED";
    });
  }

  /**
   * Applies the enhance (D81): same 202-then-poll contract as a rotate, same local QUEUED flip so
   * the tile shows its spinner until the derivatives are rewritten. Normally reached by accepting
   * a preview (D82), which is why the review flow hands ids to `useBulkActions.enhanceMany`.
   */
  async function enhanceFile(fileId: number): Promise<void> {
    await requestJson(`${apiUrl}/api/files/${fileId}/enhance`, { method: "POST" });
    patchFile(fileId, (file) => {
      file.processingStatus = "QUEUED";
    });
  }

  /**
   * Step one of the enhance review (D82): the worker builds the enhanced image at large size
   * without touching the photo. 202 now; the status poller says when it is there.
   */
  async function requestEnhancePreview(fileId: number): Promise<void> {
    await requestJson(`${apiUrl}/api/files/${fileId}/enhance-preview`, { method: "POST" });
    patchFile(fileId, (file) => {
      file.processingStatus = "QUEUED";
    });
  }

  /**
   * The preview bytes as an object URL for an `<img>`. Owner-only on the server, so it cannot go
   * through the public-token image path like every other picture; it is fetched with the session
   * and handed to the browser as a blob. The caller revokes the URL when the review moves on.
   */
  async function loadEnhancePreview(fileId: number): Promise<string> {
    const response = await fetchWithAuth(`${apiUrl}/api/files/${fileId}/enhance-preview`);
    if (!response.ok) {
      throw new Error(
        response.status === 404 ? "The preview is not there yet." : `Preview failed (${response.status}).`,
      );
    }
    return URL.createObjectURL(await response.blob());
  }

  /** Declining (D82): the server drops the preview. Nothing else changes. */
  async function discardEnhancePreview(fileId: number): Promise<void> {
    const response = await fetchWithAuth(`${apiUrl}/api/files/${fileId}/enhance-preview`, {
      method: "DELETE",
    });
    if (!response.ok) throw new Error(`Discard failed (${response.status}).`);
  }

  async function addTag(fileId: number, tagName: string): Promise<void> {
    if (!tagName) return;
    const data = await requestJson<TagsResponse>(
      `${apiUrl}/api/files/${fileId}/tags`,
      jsonBody("POST", { tagName }),
    );
    if (data.tags) patchFile(fileId, (file) => (file.tags = data.tags!));
  }

  async function removeTag(fileId: number, tagName: string): Promise<void> {
    const data = await requestJson<TagsResponse>(
      `${apiUrl}/api/files/${fileId}/tags/${encodeURIComponent(tagName)}`,
      { method: "DELETE" },
    );
    if (data.tags) patchFile(fileId, (file) => (file.tags = data.tags!));
  }

  /**
   * Set or clear this photo's caption (D69). A blank caption clears it — the server stores null
   * either way, so both lists are patched in place rather than reloaded.
   */
  async function updateCaption(fileId: number, caption: string): Promise<void> {
    const updated = await requestJson<AlbumFile>(
      `${apiUrl}/api/files/${fileId}/caption`,
      jsonBody("PUT", { caption }),
    );
    patchFile(fileId, (file) => (file.caption = updated.caption ?? null));
  }

  /**
   * Add a tag to every file in an album. Returns how many files actually changed
   * (files that already had the tag are skipped by the backend).
   */
  async function addTagToAllFiles(albumId: number, tagName: string): Promise<number> {
    const data = await requestJson<CountResponse>(
      `${apiUrl}/api/albums/${albumId}/files/tags/${encodeURIComponent(tagName)}`,
      { method: "POST" },
    );
    return data.updatedCount || 0;
  }

  /** Remove a tag from every file in an album. Returns how many files actually changed. */
  async function removeTagFromAllFiles(albumId: number, tagName: string): Promise<number> {
    const data = await requestJson<CountResponse>(
      `${apiUrl}/api/albums/${albumId}/files/tags/${encodeURIComponent(tagName)}`,
      { method: "DELETE" },
    );
    return data.updatedCount || 0;
  }

  async function reorderFiles(fileIds: number[]): Promise<void> {
    await requestJson(`${apiUrl}/api/files/reorder`, jsonBody("PUT", { fileIds }));
  }

  async function reorderByFilename(albumId: number): Promise<number> {
    const data = await requestJson<CountResponse>(
      `${apiUrl}/api/albums/${albumId}/reorder-by-filename`,
      { method: "POST" },
    );
    return data.updatedCount || 0;
  }

  async function reorderByExif(albumId: number): Promise<number> {
    const data = await requestJson<CountResponse>(
      `${apiUrl}/api/albums/${albumId}/reorder-by-exif`,
      { method: "POST" },
    );
    return data.updatedCount || 0;
  }

  return {
    files,
    allFilesUnfiltered,
    loadingFiles,
    error,
    totalSize,
    selectedTag,
    tagsUsedInAlbum,
    loadAlbumFiles,
    deleteFile,
    rotateFile,
    enhanceFile,
    requestEnhancePreview,
    loadEnhancePreview,
    discardEnhancePreview,
    addTag,
    removeTag,
    updateCaption,
    addTagToAllFiles,
    removeTagFromAllFiles,
    reorderFiles,
    reorderByFilename,
    reorderByExif,
  };
}
