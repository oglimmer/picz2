import { ref, type Ref } from "vue";
import { useApi, jsonBody } from "./useApi";
import type { Album, MapView } from "@/types";

interface AlbumsResponse {
  albums?: Album[];
}

interface AlbumResponse {
  album?: Album;
}

export interface AlbumsComposable {
  albums: Ref<Album[]>;
  currentAlbum: Ref<Album | null>;
  loading: Ref<boolean>;
  error: Ref<string | null>;
  loadAlbums: () => Promise<void>;
  loadAlbumById: (
    albumId: number,
    startPresentation?: boolean,
  ) => Promise<Album | null>;
  createAlbum: (
    name: string,
    description?: string,
    storageBackendId?: number | null,
  ) => Promise<Album | null>;
  deleteAlbum: (albumId: number) => Promise<void>;
  updateAlbum: (albumId: number, updates: Partial<Album>) => Promise<void>;
  saveMapView: (albumId: number, view: MapView | null) => Promise<void>;
  setPublished: (albumId: number, published: boolean) => Promise<void>;
  duplicateAlbum: (albumId: number) => Promise<Album | null>;
}

/**
 * Albums and the one album a view is looking at. Per-instance state (see README.md).
 */
export function useAlbums(): AlbumsComposable {
  const { apiUrl, requestJson, requestPublicJson, shareToken } = useApi();

  const albums = ref<Album[]>([]);
  const currentAlbum = ref<Album | null>(null);
  const loading = ref<boolean>(false);
  const error = ref<string | null>(null);

  async function loadAlbums(): Promise<void> {
    loading.value = true;
    error.value = null;
    try {
      const data = await requestJson<AlbumsResponse>(`${apiUrl}/api/albums`);
      albums.value = data.albums || [];
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      error.value = `Error loading albums: ${errorMessage}`;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Load a specific album by ID. With a share token and `startPresentation` the public endpoint is
   * used, which needs no login.
   */
  async function loadAlbumById(
    albumId: number,
    startPresentation: boolean = false,
  ): Promise<Album | null> {
    try {
      if (shareToken.value && startPresentation) {
        const data = await requestPublicJson<AlbumResponse>(
          `${apiUrl}/api/albums/public/${shareToken.value}`,
        ).catch(() => null);
        currentAlbum.value = data?.album ?? {
          id: albumId,
          name: "Presentation",
          shareToken: shareToken.value,
        };
      } else {
        const data = await requestJson<AlbumResponse>(`${apiUrl}/api/albums/${albumId}`);
        if (data.album) currentAlbum.value = data.album;
      }
      return currentAlbum.value;
    } catch {
      return null;
    }
  }

  /**
   * `storageBackendId` null/undefined means the instance's own storage. It is only honoured here,
   * at creation — the server refuses to move an album's bytes later.
   */
  async function createAlbum(
    name: string,
    description: string = "",
    storageBackendId: number | null = null,
  ): Promise<Album | null> {
    if (!name || name.trim() === "") {
      throw new Error("Album name is required");
    }
    const data = await requestJson<AlbumResponse>(
      `${apiUrl}/api/albums`,
      jsonBody("POST", { name, description, storageBackendId }),
    );
    if (data.album) albums.value.push(data.album);
    return data.album ?? null;
  }

  async function deleteAlbum(albumId: number): Promise<void> {
    await requestJson(`${apiUrl}/api/albums/${albumId}`, { method: "DELETE" });
    const albumIndex = albums.value.findIndex((a) => a.id === albumId);
    if (albumIndex !== -1) albums.value.splice(albumIndex, 1);
  }

  /** Applies `patch` to the current album and to its entry in the list, wherever it is held. */
  function patchAlbum(albumId: number, patch: Partial<Album>): void {
    if (currentAlbum.value && currentAlbum.value.id === albumId) {
      currentAlbum.value = { ...currentAlbum.value, ...patch };
    }
    const albumIndex = albums.value.findIndex((a) => a.id === albumId);
    if (albumIndex !== -1) {
      albums.value[albumIndex] = { ...albums.value[albumIndex], ...patch };
    }
  }

  async function updateAlbum(albumId: number, updates: Partial<Album>): Promise<void> {
    await requestJson(`${apiUrl}/api/albums/${albumId}`, jsonBody("PUT", updates));
    patchAlbum(albumId, updates);
  }

  /**
   * Save the album's default map view, or clear it by passing null.
   *
   * <p>Separate from `updateAlbum` because that endpoint is name-and-description only, and a
   * PUT there carrying map fields would round-trip the name — enough to trip the duplicate-name
   * check on a rename that had not been saved yet.
   *
   * <p>The local album is patched from the server's response rather than from the value we sent:
   * the server clamps out-of-range spans, so echoing our own input back could leave the UI
   * claiming a view that was not stored.
   */
  async function saveMapView(albumId: number, view: MapView | null): Promise<void> {
    const data = await requestJson<AlbumResponse>(
      `${apiUrl}/api/albums/${albumId}/map-view`,
      view ? jsonBody("PUT", view) : { method: "DELETE" },
    );
    patchAlbum(albumId, {
      mapCenterLat: data.album?.mapCenterLat ?? null,
      mapCenterLng: data.album?.mapCenterLng ?? null,
      mapSpanLat: data.album?.mapSpanLat ?? null,
      mapSpanLng: data.album?.mapSpanLng ?? null,
    });
  }

  /**
   * Opens or closes public access to the album.
   *
   * Separate from `updateAlbum` for the same reason as `saveMapView`: that endpoint round-trips
   * the name, so a toggle would fight an unsaved rename. Patches from the server's answer, so
   * `publishedAt` reflects what was actually stamped on the first publish.
   */
  async function setPublished(albumId: number, published: boolean): Promise<void> {
    const data = await requestJson<AlbumResponse>(
      `${apiUrl}/api/albums/${albumId}/published?published=${published}`,
      { method: "PUT" },
    );
    patchAlbum(albumId, {
      published: data.album?.published ?? published,
      publishedAt: data.album?.publishedAt ?? null,
    });
  }

  async function duplicateAlbum(albumId: number): Promise<Album | null> {
    const data = await requestJson<AlbumResponse>(
      `${apiUrl}/api/albums/${albumId}/duplicate`,
      { method: "POST" },
    );
    if (data.album) albums.value.push(data.album);
    return data.album ?? null;
  }

  return {
    albums,
    currentAlbum,
    loading,
    error,
    loadAlbums,
    loadAlbumById,
    createAlbum,
    deleteAlbum,
    updateAlbum,
    saveMapView,
    setPublished,
    duplicateAlbum,
  };
}
