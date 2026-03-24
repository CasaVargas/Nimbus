import { rclone } from "./client";
import type { BwLimitResponse, StatsResponse } from "./types";

export async function getStats(group?: string): Promise<StatsResponse> {
  return rclone.call<StatsResponse>("core/stats", group ? { group } : {});
}

export async function setBandwidthLimit(
  rate: string,
): Promise<BwLimitResponse> {
  return rclone.call<BwLimitResponse>("core/bwlimit", { rate });
}

export async function getBandwidthLimit(): Promise<BwLimitResponse> {
  return rclone.call<BwLimitResponse>("core/bwlimit", {});
}
