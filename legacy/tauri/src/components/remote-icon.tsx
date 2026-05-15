import {
  Cloud,
  Database,
  FolderOpen,
  HardDrive,
  type LucideProps,
  Server,
} from "lucide-react";

const cloudTypes = new Set([
  "drive",
  "dropbox",
  "onedrive",
  "box",
  "mega",
  "pcloud",
  "yandex",
  "google cloud storage",
  "googlecloudstorage",
  "googlephotos",
]);

const databaseTypes = new Set([
  "s3",
  "b2",
  "swift",
  "azureblob",
  "gcs",
  "wasabi",
  "storj",
  "r2",
]);

const serverTypes = new Set(["sftp", "ftp", "webdav", "http", "ssh"]);

const localTypes = new Set(["local", "alias", "crypt", "union", "combine"]);

export function RemoteIcon({ type, ...props }: { type: string } & LucideProps) {
  const normalized = type.toLowerCase();

  if (cloudTypes.has(normalized)) return <Cloud {...props} />;
  if (databaseTypes.has(normalized)) return <Database {...props} />;
  if (serverTypes.has(normalized)) return <Server {...props} />;
  if (localTypes.has(normalized)) return <FolderOpen {...props} />;
  return <HardDrive {...props} />;
}
