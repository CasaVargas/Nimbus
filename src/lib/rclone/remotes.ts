import { rclone } from "./client";
import type {
  ListRemotesResponse,
  ConfigDumpResponse,
  ProvidersResponse,
} from "./types";

export async function listRemotes(): Promise<string[]> {
  const res = await rclone.call<ListRemotesResponse>("config/listremotes", {});
  return res.remotes ?? [];
}

export async function configDump(): Promise<ConfigDumpResponse> {
  return rclone.call<ConfigDumpResponse>("config/dump", {});
}

export async function getProviders(): Promise<ProvidersResponse> {
  return rclone.call<ProvidersResponse>("config/providers", {});
}

export async function createRemote(
  name: string,
  type: string,
  parameters: Record<string, string>
): Promise<void> {
  await rclone.call("config/create", { name, type, parameters });
}

export async function updateRemote(
  name: string,
  parameters: Record<string, string>
): Promise<void> {
  await rclone.call("config/update", { name, parameters });
}

export async function deleteRemote(name: string): Promise<void> {
  await rclone.call("config/delete", { name });
}
