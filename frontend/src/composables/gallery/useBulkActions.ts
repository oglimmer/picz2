import { useConfirm } from "../useConfirm";
import { useNotifications } from "../useNotifications";
import type { PollFailure } from "../useProcessingPoller";

export interface BulkActionDeps {
  deleteFile: (fileId: number) => Promise<void>;
  rotateFile: (fileId: number) => Promise<void>;
  enhanceFile: (fileId: number) => Promise<void>;
  addTag: (fileId: number, tagName: string) => Promise<void>;
  waitForProcessing: (fileIds: number[], timeoutMs: number) => Promise<PollFailure[]>;
  reloadFiles: () => Promise<void>;
}

export interface BulkActions {
  /** Confirms, deletes one by one, toasts the tally. Returns the ids that failed. */
  deleteMany: (fileIds: number[]) => Promise<number[] | null>;
  /** Enqueues every rotate, waits on the batch through the poller, reloads, toasts the tally. */
  rotateMany: (fileIds: number[]) => Promise<void>;
  /** Same flow for the one-tap auto-enhance (D81). */
  enhanceMany: (fileIds: number[]) => Promise<void>;
  tagMany: (fileIds: number[], tagName: string) => Promise<void>;
}

const plural = (n: number, word: string) => `${n} ${word}${n !== 1 ? "s" : ""}`;

/**
 * The operations that act on a set of photos, shared by the bulk bar, the duplicate-names mode and
 * the single-photo buttons (a set of one). Each reports success, partial success and failure with
 * one toast rather than one per photo.
 */
export function useBulkActions(deps: BulkActionDeps): BulkActions {
  const { success, warning, error } = useNotifications();
  const { confirm } = useConfirm();

  async function deleteMany(fileIds: number[]): Promise<number[] | null> {
    if (fileIds.length === 0) return [];
    const confirmed = await confirm(
      `Delete ${plural(fileIds.length, "selected file")}? This action cannot be undone.`,
      { type: "danger", confirmText: "Delete" },
    );
    if (!confirmed) return null;

    const failedIds: number[] = [];
    for (const id of fileIds) {
      try {
        await deps.deleteFile(id);
      } catch {
        failedIds.push(id);
      }
    }
    const deleted = fileIds.length - failedIds.length;
    if (failedIds.length === 0) success(`Deleted ${plural(deleted, "file")}.`);
    else if (deleted > 0) warning(`Deleted ${plural(deleted, "file")}, ${failedIds.length} failed.`);
    else error("Failed to delete the selected files.");
    return failedIds;
  }

  /**
   * Rotation and enhancement are asynchronous (Phase 4.5, D81): the api answers 202 and the worker
   * rewrites the derivatives later. Everything is enqueued first so the worker can chew through
   * the jobs in parallel, then the whole batch is awaited on the shared poller — polling one image
   * at a time would serialise the wait. 60 s per image like a single job, capped so a large
   * selection cannot hang the bar for the rest of the session.
   *
   * `past` and `gerund` are the two word forms the toasts need ("Rotated" / "rotating").
   */
  async function rewriteMany(
    fileIds: number[],
    enqueue: (fileId: number) => Promise<void>,
    past: string,
    gerund: string,
  ): Promise<void> {
    if (fileIds.length === 0) return;
    const enqueued: number[] = [];
    const failures: PollFailure[] = [];
    for (const id of fileIds) {
      try {
        await enqueue(id);
        enqueued.push(id);
      } catch (err) {
        failures.push({ fileId: id, message: err instanceof Error ? err.message : "Unknown error" });
      }
    }
    if (enqueued.length > 0) {
      const timeoutMs = Math.min(60_000 * enqueued.length, 600_000);
      failures.push(...(await deps.waitForProcessing(enqueued, timeoutMs)));
    }
    // A rewrite swaps the public token, so the tiles need the new URLs.
    await deps.reloadFiles();

    const done = fileIds.length - failures.length;
    if (failures.length === 0) {
      success(fileIds.length === 1 ? `Image ${past.toLowerCase()}.` : `${past} ${plural(done, "image")}.`);
    } else if (done > 0) {
      warning(`${past} ${plural(done, "image")}, ${failures.length} failed.`);
    } else {
      error(`Error ${gerund}: ${failures[0].message}`);
    }
  }

  const rotateMany = (fileIds: number[]) => rewriteMany(fileIds, deps.rotateFile, "Rotated", "rotating");
  const enhanceMany = (fileIds: number[]) =>
    rewriteMany(fileIds, deps.enhanceFile, "Enhanced", "enhancing");

  async function tagMany(fileIds: number[], tagName: string): Promise<void> {
    if (!tagName || fileIds.length === 0) return;
    let count = 0;
    for (const id of fileIds) {
      try {
        await deps.addTag(id, tagName);
        count++;
      } catch {
        // counted below
      }
    }
    if (count > 0) success(`Tagged ${plural(count, "photo")} with "${tagName}"`);
    if (count < fileIds.length) warning(`${fileIds.length - count} could not be tagged.`);
  }

  return { deleteMany, rotateMany, enhanceMany, tagMany };
}
