import { rclone } from "./client";
import type { AsyncJobResponse } from "./types";

interface SyncOptions {
  srcFs: string;
  dstFs: string;
  _async?: boolean;
  _filter?: Record<string, unknown>;
  [key: string]: unknown;
}

export async function copy(opts: SyncOptions): Promise<AsyncJobResponse> {
  return rclone.call<AsyncJobResponse>("sync/copy", {
    ...opts,
    _async: opts._async ?? true,
  });
}

export async function sync(opts: SyncOptions): Promise<AsyncJobResponse> {
  return rclone.call<AsyncJobResponse>("sync/sync", {
    ...opts,
    _async: opts._async ?? true,
  });
}
