import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { backgroundPhotoFor, formatBytes, formatDate, isTextCard, isVideo } from "../format";

describe("formatBytes", () => {
  it("scales through the units and clamps at PB", () => {
    expect(formatBytes(0)).toBe("0 Bytes");
    expect(formatBytes(512)).toBe("512 Bytes");
    expect(formatBytes(1536)).toBe("1.5 KB");
    expect(formatBytes(5 * 1024 ** 3)).toBe("5 GB");
    expect(formatBytes(1024 ** 5)).toBe("1 PB");
    // Past the table: still readable, never "undefined".
    expect(formatBytes(1024 ** 6)).toBe("1024 PB");
  });

  it("treats garbage as nothing", () => {
    expect(formatBytes(NaN)).toBe("0 Bytes");
    expect(formatBytes(-3)).toBe("0 Bytes");
  });
});

describe("formatDate", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    // A Wednesday, mid-afternoon local time.
    vi.setSystemTime(new Date(2026, 8, 9, 15, 0, 0));
  });
  afterEach(() => vi.useRealTimers());

  const at = (dayOffset: number, hour: number) =>
    new Date(2026, 8, 9 + dayOffset, hour, 0, 0).toISOString();

  it("counts calendar days, not 24-hour blocks", () => {
    expect(formatDate(at(0, 0))).toBe("Today");
    // 23:50 yesterday is yesterday even though it is under 24 h ago.
    expect(formatDate(new Date(2026, 8, 8, 23, 50).toISOString())).toBe("Yesterday");
    expect(formatDate(at(-3, 12))).toBe("3 days ago");
    expect(formatDate(at(-6, 12))).toBe("6 days ago");
  });

  it("falls back to the plain date at a week and for the future", () => {
    const week = new Date(2026, 8, 2, 12);
    expect(formatDate(week.toISOString())).toBe(week.toLocaleDateString());
    // A camera with a wrong clock must not read as "Today".
    const future = new Date(2026, 8, 11, 12);
    expect(formatDate(future.toISOString())).toBe(future.toLocaleDateString());
  });

  it("renders nothing for an unparseable timestamp", () => {
    expect(formatDate("nope")).toBe("");
  });
});

describe("isTextCard", () => {
  it("reads the server's `kind`, never the mime type", () => {
    expect(isTextCard({ kind: "TEXT_CARD" })).toBe(true);
    expect(isTextCard({ kind: "PHOTO" })).toBe(false);
    // A row from an older server has no `kind`. It has to read as a photo: mistaking a photo for
    // a card would draw text over a picture that then never gets rendered.
    expect(isTextCard({})).toBe(false);
    expect(isTextCard(null)).toBe(false);
    expect(isTextCard(undefined)).toBe(false);
  });
});

describe("backgroundPhotoFor", () => {
  const card = (id: number) => ({ id, kind: "TEXT_CARD", publicToken: `c${id}` });
  const photo = (id: number) => ({ id, kind: "PHOTO", publicToken: `p${id}` });

  it("takes the next actual picture after the card", () => {
    const files = [card(1), photo(2), photo(3)];
    expect(backgroundPhotoFor(files, 0)?.id).toBe(2);
  });

  it("skips over other cards to reach a picture", () => {
    const files = [card(1), card(2), photo(3)];
    expect(backgroundPhotoFor(files, 0)?.id).toBe(3);
  });

  it("gives nothing back for a card at the end of the album", () => {
    expect(backgroundPhotoFor([photo(1), card(2)], 1)).toBeNull();
  });

  it("gives nothing back when only cards follow", () => {
    expect(backgroundPhotoFor([card(1), card(2)], 0)).toBeNull();
  });

  /**
   * A photo whose derivatives are not written yet has no token to fetch, so it cannot serve as a
   * background — the card would show a broken image instead of a blur.
   */
  it("passes over a picture that has no public token yet", () => {
    const files = [card(1), { id: 2, kind: "PHOTO" }, photo(3)];
    expect(backgroundPhotoFor(files, 0)?.id).toBe(3);
  });
});

describe("isVideo", () => {
  it("looks at the wire field `mimetype` only", () => {
    expect(isVideo({ mimetype: "video/mp4" })).toBe(true);
    expect(isVideo({ mimetype: "image/jpeg" })).toBe(false);
    expect(isVideo({})).toBe(false);
  });
});
