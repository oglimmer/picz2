import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("../useAuth", () => ({
  useAuth: () => ({
    isLoggedIn: { value: true },
    getAuthHeaders: () => ({ Authorization: "Bearer zst_test" }),
  }),
}));

import { useStorageUsage, STORAGE_USAGE_POLL_MS } from "../useStorageUsage";

function answer(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * The banner's contract: up exactly while the server says `full`, never decided from the two
 * numbers client-side, and never taken down by a failed fetch.
 */
describe("useStorageUsage", () => {
  const fetchMock = vi.fn<typeof fetch>();

  beforeEach(() => {
    vi.useFakeTimers();
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockReset();
  });

  afterEach(() => {
    useStorageUsage().stopPolling();
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  it("shows the banner exactly when the server says full", async () => {
    const { storageFull, refresh } = useStorageUsage();
    expect(storageFull.value).toBe(false);

    fetchMock.mockResolvedValueOnce(
      answer({ usedBytes: 100, quotaBytes: 100, remainingBytes: 0, full: true }),
    );
    await refresh();
    expect(storageFull.value).toBe(true);
    expect(fetchMock.mock.calls[0][0]).toMatch(/\/api\/storage-usage$/);

    fetchMock.mockResolvedValueOnce(
      answer({ usedBytes: 10, quotaBytes: 100, remainingBytes: 90, full: false }),
    );
    await refresh();
    expect(storageFull.value).toBe(false);
  });

  it("trusts the server's verdict, not its own arithmetic", async () => {
    const { storageFull, refresh } = useStorageUsage();
    // Numbers that look full but a server that says otherwise: the server wins, so the rule
    // cannot drift between what is shown and what the upload path enforces.
    fetchMock.mockResolvedValueOnce(
      answer({ usedBytes: 100, quotaBytes: 100, remainingBytes: 0, full: false }),
    );
    await refresh();
    expect(storageFull.value).toBe(false);
  });

  it("keeps the last answer when a fetch fails", async () => {
    const { storageFull, refresh } = useStorageUsage();
    fetchMock.mockResolvedValueOnce(
      answer({ usedBytes: 100, quotaBytes: 100, remainingBytes: 0, full: true }),
    );
    await refresh();
    expect(storageFull.value).toBe(true);

    fetchMock.mockRejectedValueOnce(new Error("Failed to fetch"));
    await refresh();
    expect(storageFull.value).toBe(true);

    fetchMock.mockResolvedValueOnce(answer({ message: "nope" }, 500));
    await refresh();
    expect(storageFull.value).toBe(true);
  });

  it("polls while started and clears the banner on stop", async () => {
    const { storageFull, startPolling, stopPolling } = useStorageUsage();
    fetchMock.mockResolvedValue(
      answer({ usedBytes: 100, quotaBytes: 100, remainingBytes: 0, full: true }),
    );

    startPolling();
    await vi.advanceTimersByTimeAsync(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(storageFull.value).toBe(true);

    await vi.advanceTimersByTimeAsync(STORAGE_USAGE_POLL_MS);
    expect(fetchMock).toHaveBeenCalledTimes(2);

    // Starting twice must not double the traffic.
    startPolling();
    await vi.advanceTimersByTimeAsync(STORAGE_USAGE_POLL_MS);
    expect(fetchMock).toHaveBeenCalledTimes(3);

    stopPolling();
    expect(storageFull.value).toBe(false);
    await vi.advanceTimersByTimeAsync(STORAGE_USAGE_POLL_MS * 2);
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it("coalesces overlapping refreshes into one request", async () => {
    const { refresh } = useStorageUsage();
    fetchMock.mockResolvedValueOnce(
      answer({ usedBytes: 0, quotaBytes: 100, remainingBytes: 100, full: false }),
    );
    await Promise.all([refresh(), refresh(), refresh()]);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});
