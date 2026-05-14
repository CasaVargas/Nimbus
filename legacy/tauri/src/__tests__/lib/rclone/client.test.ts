import { beforeEach, describe, expect, it, vi } from "vitest";
import { RcloneClient } from "../../../lib/rclone/client";

// Mock fetch globally
const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

describe("RcloneClient", () => {
  let client: RcloneClient;

  beforeEach(() => {
    client = new RcloneClient("http://localhost:5572");
    mockFetch.mockReset();
  });

  it("sends POST request with JSON body", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ remotes: ["gdrive:"] }),
    });

    const result = await client.call("config/listremotes", {});
    expect(mockFetch).toHaveBeenCalledWith(
      "http://localhost:5572/config/listremotes",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      },
    );
    expect(result).toEqual({ remotes: ["gdrive:"] });
  });

  it("throws RcloneError on non-ok response", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: () =>
        Promise.resolve({
          error: "something broke",
          input: {},
          path: "",
          status: 500,
        }),
    });

    await expect(client.call("rc/noop", {})).rejects.toThrow("something broke");
  });

  it("throws on network failure", async () => {
    mockFetch.mockRejectedValueOnce(new TypeError("Failed to fetch"));

    await expect(client.call("rc/noop", {})).rejects.toThrow("Failed to fetch");
  });

  it("health check calls rc/noop", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({}),
    });

    const alive = await client.healthCheck();
    expect(alive).toBe(true);
  });

  it("health check returns false on error", async () => {
    mockFetch.mockRejectedValueOnce(new Error("conn refused"));

    const alive = await client.healthCheck();
    expect(alive).toBe(false);
  });
});
