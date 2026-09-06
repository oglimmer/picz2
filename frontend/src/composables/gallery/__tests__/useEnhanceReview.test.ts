import { describe, expect, it, vi } from "vitest";
import { useEnhanceReview } from "../useEnhanceReview";
import type { AlbumFile } from "@/types";

const file = (id: number): AlbumFile =>
  ({ id, albumId: 1, filename: `${id}.jpg`, path: "", size: 1, uploadedAt: "", tags: [] }) as AlbumFile;

function deps(overrides: Partial<Parameters<typeof useEnhanceReview>[0]> = {}) {
  return {
    requestPreview: vi.fn(async () => {}),
    waitForProcessing: vi.fn(async () => []),
    loadPreview: vi.fn(async (id: number) => `blob:${id}`),
    discardPreview: vi.fn(async () => {}),
    revokeUrl: vi.fn(),
    ...overrides,
  };
}

const flush = () => new Promise((r) => setTimeout(r, 0));

describe("useEnhanceReview", () => {
  it("requests every preview up front, shows the first, and collects what was accepted", async () => {
    const d = deps();
    const review = useEnhanceReview(d);
    await review.start([file(1), file(2), file(3)]);

    expect(vi.mocked(d.requestPreview).mock.calls.map((c) => c[0])).toEqual([1, 2, 3]);
    expect(d.waitForProcessing).toHaveBeenCalledWith([1], 120_000);
    expect(review.previewUrl.value).toBe("blob:1");
    expect(review.showEnhanced.value).toBe(true);
    expect(review.finished.value).toBe(false);

    await review.accept();
    expect(review.index.value).toBe(1);
    expect(d.revokeUrl).toHaveBeenCalledWith("blob:1");
    expect(review.previewUrl.value).toBe("blob:2");

    await review.decline();
    expect(d.discardPreview).toHaveBeenCalledWith(2);
    expect(review.previewUrl.value).toBe("blob:3");

    await review.accept();
    expect(review.finished.value).toBe(true);
    expect(review.accepted.value).toEqual([1, 3]);
    // Accepted previews are the ENHANCE job's to remove, not the client's.
    expect(d.discardPreview).toHaveBeenCalledTimes(1);
  });

  it("a worker failure blocks accept and turns the decline into a skip that discards nothing", async () => {
    const d = deps({
      waitForProcessing: vi.fn(async (ids: number[]) =>
        ids[0] === 1 ? [{ fileId: 1, message: "convert died" }] : [],
      ),
    });
    const review = useEnhanceReview(d);
    await review.start([file(1), file(2)]);

    expect(review.error.value).toBe("convert died");
    expect(review.previewUrl.value).toBeNull();
    await review.accept();
    expect(review.index.value).toBe(0);

    await review.decline();
    expect(review.index.value).toBe(1);
    expect(review.previewUrl.value).toBe("blob:2");
    // The failed one still had a key request in flight on the server, so its discard goes out.
    expect(d.discardPreview).toHaveBeenCalledWith(1);
  });

  it("a refused request is remembered and never waited for or discarded", async () => {
    const d = deps({
      requestPreview: vi.fn(async (id: number) => {
        if (id === 2) throw new Error("Only image files can be enhanced");
      }),
    });
    const review = useEnhanceReview(d);
    await review.start([file(1), file(2)]);
    await review.accept();

    expect(review.error.value).toBe("Only image files can be enhanced");
    expect(d.waitForProcessing).toHaveBeenCalledTimes(1);
    await review.decline();
    expect(d.discardPreview).not.toHaveBeenCalled();
    expect(review.finished.value).toBe(true);
    expect(review.accepted.value).toEqual([1]);
  });

  it("cancel discards everything not yet decided and finishes", async () => {
    const d = deps();
    const review = useEnhanceReview(d);
    await review.start([file(1), file(2), file(3)]);
    await review.accept();

    await review.cancel();
    expect(review.finished.value).toBe(true);
    expect(review.accepted.value).toEqual([1]);
    expect(vi.mocked(d.discardPreview).mock.calls.map((c) => c[0]).sort()).toEqual([2, 3]);
    expect(d.revokeUrl).toHaveBeenCalledWith("blob:2");
  });

  it("a slow preview for a photo already left behind is dropped, not shown", async () => {
    let releaseFirst: (v: PollFailure[]) => void = () => {};
    const d = deps({
      waitForProcessing: vi.fn((ids: number[]) =>
        ids[0] === 1
          ? new Promise<PollFailure[]>((r) => {
              releaseFirst = r;
            })
          : Promise.resolve([]),
      ),
    });
    const review = useEnhanceReview(d);
    const started = review.start([file(1), file(2)]);
    await flush();
    expect(review.loading.value).toBe(true);

    await review.decline();
    expect(review.previewUrl.value).toBe("blob:2");
    releaseFirst([]);
    await started;
    await flush();
    expect(review.previewUrl.value).toBe("blob:2");
    expect(d.loadPreview).not.toHaveBeenCalledWith(1);
  });

  it("toggle only flips once there is something to flip to", async () => {
    const review = useEnhanceReview(deps({ loadPreview: vi.fn(async () => "blob:x") }));
    review.toggle();
    expect(review.showEnhanced.value).toBe(true);
    await review.start([file(1)]);
    review.toggle();
    expect(review.showEnhanced.value).toBe(false);
  });
});

type PollFailure = { fileId: number; message: string };
