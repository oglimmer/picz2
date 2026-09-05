import { describe, expect, it } from "vitest";
import { tooLargeMessage, translateUploadError } from "../useUpload";

describe("translateUploadError", () => {
  it("maps the statuses users actually meet to plain sentences", () => {
    expect(translateUploadError(401, null)).toMatch(/log out and back in/);
    expect(translateUploadError(403, null)).toMatch(/log out and back in/);
    expect(translateUploadError(409, null)).toBe("This file has already been uploaded.");
    expect(translateUploadError(429, "30")).toBe("Server is busy — try again in 30s.");
    expect(translateUploadError(503, null)).toBe("Server is busy — try again shortly.");
  });

  it("quotes both numbers for a 413 only when the cap is known", () => {
    expect(translateUploadError(413, null, undefined, { fileSize: 3 * 1024 ** 3, maxSize: 2 * 1024 ** 3 })).toBe(
      tooLargeMessage(3 * 1024 ** 3, 2 * 1024 ** 3),
    );
    expect(translateUploadError(413, null)).toBe("File is too large for this server.");
    expect(tooLargeMessage(3 * 1024 ** 3, 2 * 1024 ** 3)).toBe("File is 3 GB — this server accepts up to 2 GB.");
  });

  it("prefers the server's own sentence for a full quota and falls back otherwise", () => {
    expect(translateUploadError(507, null, "You have 10 MB left")).toBe("You have 10 MB left");
    expect(translateUploadError(507, null)).toMatch(/storage on this site is full/);
  });

  it("passes network errors through and labels unknown statuses", () => {
    expect(translateUploadError(null, null, "Failed to fetch")).toBe("Failed to fetch");
    expect(translateUploadError(null, null)).toBe("Upload failed (network error)");
    expect(translateUploadError(500, null)).toBe("Upload failed (HTTP 500)");
    expect(translateUploadError(500, null, "boom")).toBe("boom");
  });
});
