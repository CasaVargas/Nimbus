import { rclone } from "./client";
import type { JobListResponse, JobStatusResponse } from "./types";

export async function listJobs(): Promise<number[]> {
  const res = await rclone.call<JobListResponse>("job/list", {});
  return res.jobids ?? [];
}

export async function jobStatus(jobid: number): Promise<JobStatusResponse> {
  return rclone.call<JobStatusResponse>("job/status", { jobid });
}

export async function stopJob(jobid: number): Promise<void> {
  await rclone.call("job/stop", { jobid });
}
