import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ref } from "vue";
import { useProcessingPoller } from "../useProcessingPoller";
import type { AlbumFile } from "@/types";

const file = (id: number, status?: AlbumFile["processingStatus"]): AlbumFile =>
  ({ id, albumId: 1, filename: "", path: "", size: 1, uploadedAt: "", tags: [], processingStatus: status }) as AlbumFile;

function statusServer(answers: Record<number, Array<{ processingStatus?: string; error?: string } | 404>>) {
  return vi.fn(async (url: string) => {
    const id = Number(url.match(/assets\/(\d+)\/status/)![1]);
    const queue = answers[id];
    const next = queue.length > 1 ? queue.shift()! : queue[0];
    if (next === 404) return new Response("", { status: 404 });
    return new Response(JSON.stringify(next), { status: 200, headers: { "Content-Type": "application/json" } });
  });
}

describe("useProcessingPoller", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("polls a queued file until it is DONE and patches the file in place", async () => {
    const files = ref([file(1, "QUEUED")]);
    vi.stubGlobal("fetch", statusServer({ 1: [{ processingStatus: "PROCESSING" }, { processingStatus: "DONE" }] }));
    const poller = useProcessingPoller(files);

    poller.watchFiles(files.value);
    expect(poller.pending.value.has(1)).toBe(true);

    await vi.advanceTimersByTimeAsync(1000); // first poll → PROCESSING
    expect(files.value[0].processingStatus).toBe("PROCESSING");
    await vi.advanceTimersByTimeAsync(2000); // second poll → DONE
    expect(files.value[0].processingStatus).toBe("DONE");
    expect(poller.pending.value.size).toBe(0);
  });

  it("waitFor resolves with the ids that did not end in DONE", async () => {
    const files = ref([file(1, "QUEUED"), file(2, "QUEUED"), file(3, "QUEUED")]);
    vi.stubGlobal(
      "fetch",
      statusServer({
        1: [{ processingStatus: "DONE" }],
        2: [{ processingStatus: "DEAD_LETTER", error: "ffmpeg exploded" }],
        3: [404],
      }),
    );
    const poller = useProcessingPoller(files);

    const done = poller.waitFor([1, 2, 3], 60_000);
    await vi.advanceTimersByTimeAsync(1000);
    const failures = await done;

    expect(failures.map((f) => f.fileId).sort()).toEqual([2, 3]);
    expect(failures.find((f) => f.fileId === 2)?.message).toBe("ffmpeg exploded");
    expect(failures.find((f) => f.fileId === 3)?.message).toMatch(/no longer exists/);
  });

  it("waitFor gives up at its timeout and reports the stragglers", async () => {
    const files = ref([file(1, "QUEUED")]);
    vi.stubGlobal("fetch", statusServer({ 1: [{ processingStatus: "PROCESSING" }] }));
    const poller = useProcessingPoller(files);

    const done = poller.waitFor([1], 5000);
    await vi.advanceTimersByTimeAsync(5000);
    const failures = await done;
    expect(failures).toEqual([{ fileId: 1, message: "Timed out waiting for the worker" }]);
  });

  it("stopAll clears timers and settles every waiter", async () => {
    const files = ref([file(1, "QUEUED")]);
    const fetchMock = statusServer({ 1: [{ processingStatus: "PROCESSING" }] });
    vi.stubGlobal("fetch", fetchMock);
    const poller = useProcessingPoller(files);

    const done = poller.waitFor([1], 60_000);
    poller.stopAll();
    await expect(done).resolves.toEqual([]);
    await vi.advanceTimersByTimeAsync(10_000);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
