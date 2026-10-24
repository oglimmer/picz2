import { describe, expect, it, vi } from "vitest";
import { createImageViewBatcher } from "../useImageViewBeacon";
import type { AlbumFile } from "@/types";

const f = (id: number): AlbumFile =>
  ({ id, albumId: 1, filename: "", path: "", size: 1, uploadedAt: "", tags: [] }) as AlbumFile;

const card = (id: number): AlbumFile => ({ ...f(id), kind: "TEXT_CARD" }) as AlbumFile;

describe("createImageViewBatcher", () => {
  it("adds up looks per photo and sends them as one batch", () => {
    const send = vi.fn();
    const batcher = createImageViewBatcher(send);

    batcher.recordOpen(f(1));
    batcher.recordWalkIn(f(2));
    batcher.recordWalkIn(f(1));
    batcher.recordWalkIn(f(1));
    expect(send).not.toHaveBeenCalled();

    batcher.flush();
    expect(send).toHaveBeenCalledOnce();
    expect(send.mock.calls[0][0]).toEqual([
      { fileId: 1, opens: 1, walkIns: 2 },
      { fileId: 2, opens: 0, walkIns: 1 },
    ]);
  });

  it("starts a fresh pile after a send and sends nothing when empty", () => {
    const send = vi.fn();
    const batcher = createImageViewBatcher(send);

    batcher.flush();
    expect(send).not.toHaveBeenCalled();

    batcher.recordOpen(f(1));
    batcher.flush();
    batcher.flush();
    expect(send).toHaveBeenCalledOnce();
    expect(batcher.size()).toBe(0);
  });

  /** D86: a card is a chapter page with no picture, so looking at it is not looking at a photo. */
  it("never counts a text card", () => {
    const send = vi.fn();
    const batcher = createImageViewBatcher(send);

    batcher.recordOpen(card(5));
    batcher.recordWalkIn(card(5));
    batcher.flush();

    expect(send).not.toHaveBeenCalled();
  });

  it("sends early once the pile reaches the cap", () => {
    const send = vi.fn();
    const batcher = createImageViewBatcher(send, 3);

    batcher.recordWalkIn(f(1));
    batcher.recordWalkIn(f(2));
    batcher.recordWalkIn(f(1));
    expect(send).not.toHaveBeenCalled();

    batcher.recordWalkIn(f(3));
    expect(send).toHaveBeenCalledOnce();
    expect(send.mock.calls[0][0]).toHaveLength(3);
    expect(batcher.size()).toBe(0);
  });
});
