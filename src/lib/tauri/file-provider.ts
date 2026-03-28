import { invoke } from "@tauri-apps/api/core";

export interface FileProviderDomainInfo {
  identifier: string;
  display_name: string;
}

export async function fpSyncState(remotes: string[]): Promise<void> {
  return invoke<void>("fp_sync_state", { remotes });
}

export async function fpAddDomain(identifier: string, displayName: string): Promise<void> {
  return invoke<void>("fp_add_domain", { identifier, displayName });
}

export async function fpRemoveDomain(identifier: string): Promise<void> {
  return invoke<void>("fp_remove_domain", { identifier });
}

export async function fpListDomains(): Promise<FileProviderDomainInfo[]> {
  return invoke<FileProviderDomainInfo[]>("fp_list_domains");
}

export async function fpIsSupported(): Promise<boolean> {
  return invoke<boolean>("fp_is_supported");
}
