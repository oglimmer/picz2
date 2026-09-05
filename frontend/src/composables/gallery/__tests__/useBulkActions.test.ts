import { describe, expect, it, vi } from "vitest";
import { useBulkActions } from "../useBulkActions";
import { useConfirm } from "../../useConfirm";
import { useNotifications } from "../../useNotifications";

function deps(overrides: Partial<Parameters<typeof useBulkActions>[0]> = {}) {
  return {
    deleteFile: vi.fn(async () => {}),
    rotateFile: vi.fn(async () => {}),
    addTag: vi.fn(async () => {}),
    waitForProcessing: vi.fn(async () => []),
    reloadFiles: vi.fn(async () => {}),
    ...overrides,
  };
}

/** Lets the pending confirm dialog settle with `answer`. */
async function answerConfirm(answer: boolean) {
  await Promise.resolve();
  useConfirm().resolveDialog(answer);
}

const lastToast = () => useNotifications().notifications.value.at(-1);

describe("useBulkActions", () => {
  it("deleteMany asks first, deletes each, and reports the ids that failed", async () => {
    const d = deps({
      deleteFile: vi.fn(async (id: number) => {
        if (id === 2) throw new Error("nope");
      }),
    });
    const bulk = useBulkActions(d);
    const result = bulk.deleteMany([1, 2, 3]);
    await answerConfirm(true);
    expect(await result).toEqual([2]);
    expect(d.deleteFile).toHaveBeenCalledTimes(3);
    expect(lastToast()?.type).toBe("warning");
    expect(lastToast()?.message).toBe("Deleted 2 files, 1 failed.");
  });

  it("deleteMany returns null and touches nothing when the user cancels", async () => {
    const d = deps();
    const result = useBulkActions(d).deleteMany([1]);
    await answerConfirm(false);
    expect(await result).toBeNull();
    expect(d.deleteFile).not.toHaveBeenCalled();
  });

  it("rotateMany enqueues everything, waits on the batch once, then reloads", async () => {
    const d = deps({
      waitForProcessing: vi.fn(async () => [{ fileId: 2, message: "worker died" }]),
    });
    const bulk = useBulkActions(d);
    await bulk.rotateMany([1, 2]);
    expect(d.rotateFile).toHaveBeenCalledTimes(2);
    expect(d.waitForProcessing).toHaveBeenCalledWith([1, 2], 120_000);
    expect(d.reloadFiles).toHaveBeenCalledTimes(1);
    expect(lastToast()?.message).toBe("Rotated 1 image, 1 failed.");
  });

  it("rotateMany caps the wait for a huge selection and reads as singular for one", async () => {
    const d = deps();
    const bulk = useBulkActions(d);
    await bulk.rotateMany(Array.from({ length: 50 }, (_, i) => i + 1));
    expect(d.waitForProcessing).toHaveBeenCalledWith(expect.any(Array), 600_000);
    await bulk.rotateMany([7]);
    expect(lastToast()?.message).toBe("Image rotated.");
  });

  it("tagMany counts what stuck", async () => {
    const d = deps({
      addTag: vi.fn(async (id: number) => {
        if (id === 3) throw new Error("no");
      }),
    });
    await useBulkActions(d).tagMany([1, 2, 3], "trip");
    const messages = useNotifications().notifications.value.slice(-2).map((n) => n.message);
    expect(messages).toEqual(['Tagged 2 photos with "trip"', "1 could not be tagged."]);
  });
});
