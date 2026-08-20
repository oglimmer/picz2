import { ref, type Ref } from "vue";
import { useApi } from "./useApi";
import type { Album, MapView } from "@/types";

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
  createAlbum: (name: string, description?: string) => Promise<Album | null>;
  deleteAlbum: (albumId: number) => Promise<void>;
  updateAlbum: (albumId: number, updates: Partial<Album>) => Promise<void>;
  saveMapView: (albumId: number, view: MapView | null) => Promise<void>;
  duplicateAlbum: (albumId: number) => Promise<Album | null>;
}

/**
 * Albums composable for managing album data and operations
 */
export function useAlbums(): AlbumsComposable {
  const { apiUrl, fetchWithAuth } = useApi();

  const albums = ref<Album[]>([]);
  const currentAlbum = ref<Album | null>(null);
  const loading = ref<boolean>(false);
  const error = ref<string | null>(null);

  /**
   * Load all albums
   */
  async function loadAlbums(): Promise<void> {
    loading.value = true;
    error.value = null;

    try {
      const response = await fetchWithAuth(`${apiUrl}/api/albums`);
      const data = await response.json();

      if (data.success) {
        albums.value = data.albums || [];
      } else {
        throw new Error("Failed to load albums");
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      error.value = `Error loading albums: ${errorMessage}`;
      console.error("Error loading albums:", err);
    } finally {
      loading.value = false;
    }
  }

  /**
   * Load a specific album by ID
   */
  async function loadAlbumById(
    albumId: number,
    startPresentation: boolean = false,
  ): Promise<Album | null> {
    try {
      const { shareToken } = useApi();

      // If we have a shareToken and starting presentation mode, fetch via public endpoint
      if (shareToken.value && startPresentation) {
        const response = await fetch(
          `${apiUrl}/api/albums/public/${shareToken.value}`,
        );
        const data = await response.json();

        if (data.success && data.album) {
          currentAlbum.value = data.album;
        } else {
          // Fallback to minimal info
          currentAlbum.value = {
            id: albumId,
            name: "Presentation",
            shareToken: shareToken.value,
          };
        }
      } else {
        // Regular authenticated mode
        const response = await fetchWithAuth(`${apiUrl}/api/albums/${albumId}`);
        const data = await response.json();

        if (data.success) {
          currentAlbum.value = data.album;
        }
      }
      return currentAlbum.value;
    } catch (err) {
      console.error("Error loading album:", err);
      return null;
    }
  }

  /**
   * Create a new album
   */
  async function createAlbum(
    name: string,
    description: string = "",
  ): Promise<Album | null> {
    if (!name || name.trim() === "") {
      throw new Error("Album name is required");
    }

    try {
      const response = await fetchWithAuth(`${apiUrl}/api/albums`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ name, description }),
      });

      const data = await response.json();

      if (response.ok && data.success) {
        if (data.album) {
          albums.value.push(data.album);
        }
        return data.album;
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error creating album:", err);
      throw err;
    }
  }

  /**
   * Delete an album
   */
  async function deleteAlbum(albumId: number): Promise<void> {
    try {
      const response = await fetchWithAuth(`${apiUrl}/api/albums/${albumId}`, {
        method: "DELETE",
      });

      const data = await response.json();

      if (response.ok && data.success) {
        const albumIndex = albums.value.findIndex((a) => a.id === albumId);
        if (albumIndex !== -1) {
          albums.value.splice(albumIndex, 1);
        }
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error deleting album:", err);
      throw err;
    }
  }

  /**
   * Update album details
   */
  async function updateAlbum(
    albumId: number,
    updates: Partial<Album>,
  ): Promise<void> {
    try {
      const response = await fetchWithAuth(`${apiUrl}/api/albums/${albumId}`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(updates),
      });

      const data = await response.json();

      if (response.ok && data.success) {
        // Update current album if it matches
        if (currentAlbum.value && currentAlbum.value.id === albumId) {
          currentAlbum.value = { ...currentAlbum.value, ...updates };
        }

        // Update in albums list
        const albumIndex = albums.value.findIndex((a) => a.id === albumId);
        if (albumIndex !== -1) {
          albums.value[albumIndex] = {
            ...albums.value[albumIndex],
            ...updates,
          };
        }
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error updating album:", err);
      throw err;
    }
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
  async function saveMapView(
    albumId: number,
    view: MapView | null,
  ): Promise<void> {
    const response = await fetchWithAuth(
      `${apiUrl}/api/albums/${albumId}/map-view`,
      view
        ? {
            method: "PUT",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(view),
          }
        : { method: "DELETE" },
    );

    const data = await response.json();
    if (!response.ok || !data.success) {
      throw new Error(data.message || "Could not save the map view");
    }

    const patch: Partial<Album> = {
      mapCenterLat: data.album?.mapCenterLat ?? null,
      mapCenterLng: data.album?.mapCenterLng ?? null,
      mapSpanLat: data.album?.mapSpanLat ?? null,
      mapSpanLng: data.album?.mapSpanLng ?? null,
    };

    if (currentAlbum.value && currentAlbum.value.id === albumId) {
      currentAlbum.value = { ...currentAlbum.value, ...patch };
    }
    const albumIndex = albums.value.findIndex((a) => a.id === albumId);
    if (albumIndex !== -1) {
      albums.value[albumIndex] = { ...albums.value[albumIndex], ...patch };
    }
  }

  async function duplicateAlbum(albumId: number): Promise<Album | null> {
    try {
      const response = await fetchWithAuth(
        `${apiUrl}/api/albums/${albumId}/duplicate`,
        {
          method: "POST",
        },
      );

      const data = await response.json();

      if (response.ok && data.success) {
        if (data.album) {
          albums.value.push(data.album);
        }
        return data.album;
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error duplicating album:", err);
      throw err;
    }
  }

  return {
    // State
    albums,
    currentAlbum,
    loading,
    error,

    // Methods
    loadAlbums,
    loadAlbumById,
    createAlbum,
    deleteAlbum,
    updateAlbum,
    saveMapView,
    duplicateAlbum,
  };
}
