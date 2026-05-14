// --- Error ---
export interface RcloneErrorResponse {
  error: string;
  input: Record<string, unknown>;
  path: string;
  status: number;
}

export class RcloneError extends Error {
  status: number;
  path: string;

  constructor(response: RcloneErrorResponse) {
    super(response.error);
    this.name = "RcloneError";
    this.status = response.status;
    this.path = response.path;
  }
}

// --- Remotes ---
export interface RcloneRemote {
  name: string;
  type: string;
  [key: string]: unknown;
}

export interface ListRemotesResponse {
  remotes: string[];
}

export interface ConfigDumpResponse {
  [remoteName: string]: Record<string, string>;
}

export interface ProviderOption {
  Name: string;
  Help: string;
  Default: unknown;
  Value: unknown;
  Type: string;
  Required: boolean;
  IsPassword: boolean;
  Advanced: boolean;
  Examples?: { Value: string; Help: string }[];
}

export interface Provider {
  Name: string;
  Description: string;
  Prefix: string;
  Options: ProviderOption[];
}

export interface ProvidersResponse {
  providers: Provider[];
}

// --- File Operations ---
export interface FileItem {
  Path: string;
  Name: string;
  Size: number;
  MimeType: string;
  ModTime: string;
  IsDir: boolean;
  ID?: string;
}

export interface ListResponse {
  list: FileItem[];
}

export interface StatResponse {
  item: FileItem;
}

export interface AboutResponse {
  total?: number;
  used?: number;
  trashed?: number;
  free?: number;
}

// --- Jobs ---
export interface Job {
  id: number;
  group: string;
  startTime: string;
  endTime: string;
  error: string;
  finished: boolean;
  success: boolean;
  duration: number;
  output: Record<string, unknown>;
}

export interface JobListResponse {
  jobids: number[];
}

export interface JobStatusResponse extends Job {}

// --- Stats ---
export interface TransferringFile {
  name: string;
  size: number;
  bytes: number;
  percentage: number;
  speed: number;
  speedAvg: number;
  eta: number;
  group: string;
}

export interface StatsResponse {
  speed: number;
  bytes: number;
  errors: number;
  fatalError: boolean;
  retryError: boolean;
  checks: number;
  transfers: number;
  deletes: number;
  renames: number;
  transferTime: number;
  elapsedTime: number;
  lastError: string;
  transferring?: TransferringFile[];
  checking?: string[];
  totalBytes: number;
  totalChecks: number;
  totalTransfers: number;
}

export interface BwLimitResponse {
  bytesPerSecond: number;
  bytesPerSecondTx: number;
  bytesPerSecondRx: number;
  rate: string;
}

// --- Mounts ---
export interface MountInfo {
  Fs: string;
  MountPoint: string;
  MountedOn: string;
}

export interface ListMountsResponse {
  mountPoints: MountInfo[];
}

// --- Async ---
export interface AsyncJobResponse {
  jobid: number;
}
