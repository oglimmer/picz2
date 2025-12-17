import { ref, type Ref } from "vue";
import { getApiUrl } from "../utils/api-config";
import { useAuth } from "./useAuth";
import type { Album, AlbumFile } from "@/types";

const apiUrl = getApiUrl();
const shareToken = ref<string>("");

export interface ApiComposable {
  apiUrl: string;
  shareToken: Ref<string>;
  fetchWithAuth: (url: string, options?: RequestInit) => Promise<Response>;
  getImageUrl: (
    file: AlbumFile | { publicToken?: string },
    size?: string,
  ) => string;
  getAlbumCoverUrl: (album: Album | { coverImageToken?: string }) => string;
}

/**
 * API composable for making authenticated requests
 */
export function useApi(): ApiComposable {
  const { getAuthHeaders, isLoggedIn } = useAuth();

  /**
   * Fetch with authentication headers
   */
  async function fetchWithAuth(
    url: string,
    options: RequestInit = {},
  ): Promise<Response> {
    const opts: RequestInit = { ...(options || {}) };
    opts.headers = { ...(opts.headers || {}) };
    const method = (opts.method || "GET").toUpperCase();

    if (isLoggedIn.value) {
      Object.assign(opts.headers, getAuthHeaders());
    }

    // Append share token for GET requests
    let finalUrl = url;
    try {
      const u = new URL(url);
      if (method === "GET" && shareToken.value) {
        u.searchParams.set("token", shareToken.value);
      }
      finalUrl = u.toString();
    } catch {
      // ignore if url is relative (shouldn't be)
    }

    return fetch(finalUrl, opts);
  }

  /**
   * Get image URL with optional size parameter
   */
  function getImageUrl(
    file: AlbumFile | { publicToken?: string },
    size: string = "original",
  ): string {
    if (!file || !file.publicToken) return "";
    if (size && size !== "original") {
      return `${apiUrl}/api/i/${file.publicToken}?size=${size}`;
    }
    return `${apiUrl}/api/i/${file.publicToken}`;
  }

  /**
   * Get album cover image URL
   */
  function getAlbumCoverUrl(
    album: Album | { coverImageToken?: string },
  ): string {
    if (!album || !album.coverImageToken) return "";
    return `${apiUrl}/api/i/${album.coverImageToken}?size=medium`;
  }

  return {
    apiUrl,
    shareToken,
    fetchWithAuth,
    getImageUrl,
    getAlbumCoverUrl,
  };
}
