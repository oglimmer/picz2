import { Upload } from "tus-js-client";
import { formatBytes } from "../utils/format";
import { getApiUrl } from "../utils/api-config";
import { useApi } from "./useApi";
import { useAuth } from "./useAuth";
import { useCapabilities } from "./useCapabilities";

export interface UploadOptions {
  /** Per-file progress in [0, 1]. Called repeatedly during the upload. */
  onProgress?: (fraction: number) => void;
}

export interface UploadResult {
  via: "tus" | "multipart";
  /** Multipart returns the server-side asset id in its 200 body; TUS doesn't surface it back. */
  serverAssetId?: number;
}

/**
 * Phase 5 — single-entry-point file upload that picks TUS vs multipart at runtime.
 *
 * <p>Selection is server-driven (no user-facing toggle): {@code /api/capabilities.tus.enabled}
 * controls which path runs. R1 ships {@code advertised=false} so the multipart path keeps
 * running unchanged; R2 flips advertised and the next page load switches to TUS automatically.
 * If capabilities can't be fetched, we fall back to multipart (see {@link useCapabilities}).
 */
/**
 * Cached across calls: a multi-file upload should cost one token, not one per file.
 *
 * Keyed by the credentials it was minted with, which is what makes it self-invalidating — a
 * logout (or a login as somebody else) changes the key, so the old token is never reused and
 * `useAuth` does not have to know this cache exists. Importing it there would also make the two
 * composables circular.
 */
let cachedUploadToken: { credentials: string; token: Promise<string | null> } | null = null;

export function useUpload() {
  const { fetchWithAuth } = useApi();
  const { authEmail, authPassword } = useAuth();
  const { ensureLoaded } = useCapabilities();

  /**
   * Mints a scoped upload token, or null when the server has no such endpoint (§5.9).
   *
   * A failure here is deliberately not surfaced: it means "fall back to the legacy credential
   * value", which is what an older server still expects.
   */
  function fetchUploadToken(): Promise<string | null> {
    const credentials = `${authEmail.value}:${authPassword.value}`;
    if (cachedUploadToken?.credentials === credentials) return cachedUploadToken.token;

    const token = (async () => {
      try {
        const res = await fetch(`${getApiUrl()}/api/upload-tokens`, {
          method: "POST",
          headers: { Authorization: `Basic ${btoa(credentials)}` },
        });
        if (!res.ok) return null;
        const body = (await res.json()) as { token?: string };
        return body?.token ?? null;
      } catch {
        return null;
      }
    })();
    cachedUploadToken = { credentials, token };
    return token;
  }

  async function uploadFile(
    file: File,
    albumId: number,
    opts: UploadOptions = {},
  ): Promise<UploadResult> {
    const caps = await ensureLoaded();
    if (caps.tus.enabled) {
      // Refuse an oversized file here rather than letting tusd answer the create request with
      // a bare 413. The server knows its own cap and advertises it, so the browser can say
      // which file is too big and by how much — see D43, where the iOS side of the same gap
      // meant real video was never backed up and the only clue was "HTTP 413".
      if (caps.tus.maxSize > 0 && file.size > caps.tus.maxSize) {
        throw new Error(tooLargeMessage(file.size, caps.tus.maxSize));
      }
      const uploadToken = await fetchUploadToken();
      return uploadViaTus(file, albumId, caps.tus.endpoint, opts, caps.tus.maxSize, uploadToken);
    }
    return uploadViaMultipart(file, albumId, opts);
  }

  function uploadViaTus(
    file: File,
    albumId: number,
    endpoint: string,
    opts: UploadOptions,
    maxSize: number,
    uploadToken: string | null,
  ): Promise<UploadResult> {
    return new Promise((resolve, reject) => {
      const apiUrl = getApiUrl();
      const tusUrl = endpoint.startsWith("http")
        ? endpoint
        : `${apiUrl}${endpoint.startsWith("/") ? endpoint : `/${endpoint}`}`;

      const credentials = `${authEmail.value}:${authPassword.value}`;
      const upload = new Upload(file, {
        endpoint: tusUrl,
        retryDelays: [0, 1000, 3000, 5000],
        metadata: {
          filename: file.name,
          filetype: file.type || "application/octet-stream",
          albumId: String(albumId),
          // Scoped upload token when the server offers one, otherwise the legacy plain
          // "email:password" that the api hook splits and validates through the existing
          // AuthenticationManager. tusd persists this metadata to a `.info` object in storage
          // for the life of the upload, which is why sending the account password here is the
          // fallback rather than the default (§5.9). Same convention as iOS.
          auth: uploadToken ?? credentials,
        },
        headers: {
          // Belt-and-braces: tusd forwards Authorization to the hook (per
          // -hooks-http-forward-headers=Authorization). Sending it lets a future server
          // change prefer the standard header without breaking older clients.
          Authorization: `Basic ${btoa(credentials)}`,
        },
        onError(err) {
          // tus.DetailedError exposes the original response status + headers on a real HTTP
          // failure (vs. a network/parse error where they're absent). Translate to friendly
          // copy at the source so the toast/log doesn't leak internals like
          // "tus: unexpected response while creating upload, originated from request..."
          const detailed = err as unknown as {
            originalResponse?: {
              getStatus?: () => number;
              getHeader?: (name: string) => string | null;
            };
            message?: string;
          };
          const status = detailed?.originalResponse?.getStatus?.() ?? null;
          const retryAfter = detailed?.originalResponse?.getHeader?.("Retry-After") ?? null;
          reject(
            new Error(
              translateUploadError(status, retryAfter, detailed.message, {
                fileSize: file.size,
                maxSize,
              }),
            ),
          );
        },
        onProgress(sent, total) {
          if (opts.onProgress && total > 0) {
            opts.onProgress(sent / total);
          }
        },
        onSuccess() {
          resolve({ via: "tus" });
        },
      });
      upload.start();
    });
  }

  async function uploadViaMultipart(
    file: File,
    albumId: number,
    opts: UploadOptions,
  ): Promise<UploadResult> {
    const apiUrl = getApiUrl();
    const formData = new FormData();
    formData.append("file", file);
    formData.append("albumId", String(albumId));

    // Coarse "starting" tick so the caller's per-file UI can flip to in-progress; fetch
    // doesn't expose body upload progress without ReadableStream tricks, and the existing
    // multipart UX has been per-file-granular all along.
    opts.onProgress?.(0);

    const res = await fetchWithAuth(`${apiUrl}/api/upload`, {
      method: "POST",
      body: formData,
    });
    if (!res.ok) {
      const retryAfter = res.headers.get("Retry-After");
      let serverMessage: string | undefined;
      try {
        const body = (await res.json()) as { message?: string };
        serverMessage = body?.message;
      } catch {
        // body not JSON (e.g. Spring Security 401 plain text); fall through to fallback.
      }
      throw new Error(translateUploadError(res.status, retryAfter, serverMessage));
    }
    const data = (await res.json()) as {
      success: boolean;
      message?: string;
      file?: { id?: number };
    };
    if (!data.success) {
      throw new Error(data.message || "Upload failed");
    }
    opts.onProgress?.(1);
    return { via: "multipart", serverAssetId: data.file?.id };
  }

  return { uploadFile };
}

/**
 * One sentence for the file that cannot be uploaded, naming both numbers. "Too large" on its
 * own leaves the user unable to tell a file that is slightly over the cap from one that never
 * had a chance, which is the difference between trimming a clip and giving up.
 */
function tooLargeMessage(fileSize: number, maxSize: number): string {
  return `File is ${formatBytes(fileSize)} — this server accepts up to ${formatBytes(maxSize)}.`;
}

/**
 * Translate HTTP status + optional server message into user-facing copy. Shared by both
 * upload paths so the user sees the same text regardless of which protocol surfaced the
 * failure. Status `null` means a network / parse / library error with no HTTP response —
 * fall through to the original message (e.g. "Failed to fetch").
 */
function translateUploadError(
  status: number | null,
  retryAfter: string | null,
  fallbackMessage?: string,
  size?: { fileSize: number; maxSize: number },
): string {
  switch (status) {
    case 401:
    case 403:
      return "Authentication failed — please log out and back in.";
    case 409:
      return "This file has already been uploaded.";
    case 413:
      // Reached when the cap was lowered since the page loaded, or on the multipart path where
      // the limit is not advertised. With numbers when we have them, without when we don't —
      // never with a guessed limit, which would send the user off trimming to the wrong size.
      return size && size.maxSize > 0
        ? tooLargeMessage(size.fileSize, size.maxSize)
        : "File is too large for this server.";
    case 507:
      // Out of storage, not a broken request. The server's own message names both numbers, so
      // prefer it; the fallback matters because the TUS path only sees the reject body.
      return (
        fallbackMessage ||
        "Your storage on this site is full. Delete something, or add your own storage in settings."
      );
    case 429:
    case 503:
      return retryAfter
        ? `Server is busy — try again in ${retryAfter}s.`
        : "Server is busy — try again shortly.";
    case null:
      return fallbackMessage || "Upload failed (network error)";
    default:
      return fallbackMessage || `Upload failed (HTTP ${status})`;
  }
}
