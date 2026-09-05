import { ref, type Ref } from "vue";
import { getApiUrl } from "../utils/api-config";
import { useAuth } from "./useAuth";
import type { Album, AlbumFile } from "@/types";

const apiUrl = getApiUrl();
const shareToken = ref<string>("");

/** A request the server refused, with the sentence it gave and the status it sent. */
export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export interface ApiComposable {
  apiUrl: string;
  shareToken: Ref<string>;
  fetchWithAuth: (url: string, options?: RequestInit) => Promise<Response>;
  requestJson: <T = unknown>(url: string, options?: RequestInit) => Promise<T>;
  requestPublicJson: <T = unknown>(url: string, options?: RequestInit) => Promise<T>;
  getImageUrl: (
    file: AlbumFile | { publicToken?: string },
    size?: string,
  ) => string;
  getAlbumCoverUrl: (album: Album | { coverImageToken?: string }) => string;
}

/** `init` with a JSON body and the matching content type. */
export function jsonBody(method: string, body: unknown): RequestInit {
  return {
    method,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

/**
 * Reads a JSON answer, or throws an {@link ApiError} carrying the server's message.
 *
 * <p>Every endpoint here answers one of two shapes: a bare object, or the `{ success, message,
 * … }` envelope. Both are handled: a non-2xx status throws, and so does an envelope that says
 * `success: false` on a 200. A body that is not JSON (Spring's plain-text 401, a gateway's HTML
 * 502) no longer surfaces as "Unexpected token <" — the status is the message then.
 */
async function readJson<T>(response: Response, fallback: string): Promise<T> {
  const body: unknown = await response.json().catch(() => null);
  const envelope = body as { success?: unknown; message?: unknown; error?: unknown } | null;
  // Most endpoints say `message`; the storage-backend ones say `error`. Either is the sentence.
  const said = [envelope?.message, envelope?.error].find(
    (v): v is string => typeof v === "string" && v.length > 0,
  );
  const message = said ?? `${fallback} (HTTP ${response.status})`;
  if (!response.ok || envelope?.success === false) {
    throw new ApiError(message, response.status);
  }
  return body as T;
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

  /** Authenticated request that yields the parsed JSON body or throws an {@link ApiError}. */
  async function requestJson<T = unknown>(
    url: string,
    options: RequestInit = {},
  ): Promise<T> {
    const response = await fetchWithAuth(url, options);
    return readJson<T>(response, "Request failed");
  }

  /**
   * Same, without credentials — for the public share-link endpoints, where sending a logged-in
   * owner's token would be pointless and a stale one would turn a public page into a 401.
   */
  async function requestPublicJson<T = unknown>(
    url: string,
    options: RequestInit = {},
  ): Promise<T> {
    const response = await fetch(url, options);
    return readJson<T>(response, "Request failed");
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
    requestJson,
    requestPublicJson,
    getImageUrl,
    getAlbumCoverUrl,
  };
}
