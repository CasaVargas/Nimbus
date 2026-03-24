import { rclone } from "./client";
import type {
  ListResponse,
  StatResponse,
  AboutResponse,
  FileItem,
} from "./types";

export async function listFiles(
  fs: string,
  remote: string
): Promise<FileItem[]> {
  const res = await rclone.call<ListResponse>("operations/list", {
    fs,
    remote,
  });
  return res.list ?? [];
}

export async function stat(fs: string, remote: string): Promise<FileItem> {
  const res = await rclone.call<StatResponse>("operations/stat", {
    fs,
    remote,
  });
  return res.item;
}

export async function mkdir(fs: string, remote: string): Promise<void> {
  await rclone.call("operations/mkdir", { fs, remote });
}

export async function deleteFile(fs: string, remote: string): Promise<void> {
  await rclone.call("operations/deletefile", { fs, remote });
}

export async function purge(fs: string, remote: string): Promise<void> {
  await rclone.call("operations/purge", { fs, remote });
}

export async function moveFile(
  srcFs: string,
  srcRemote: string,
  dstFs: string,
  dstRemote: string
): Promise<void> {
  await rclone.call("operations/movefile", {
    srcFs,
    srcRemote,
    dstFs,
    dstRemote,
  });
}

export async function copyFile(
  srcFs: string,
  srcRemote: string,
  dstFs: string,
  dstRemote: string
): Promise<void> {
  await rclone.call("operations/copyfile", {
    srcFs,
    srcRemote,
    dstFs,
    dstRemote,
  });
}

export async function about(fs: string): Promise<AboutResponse> {
  return rclone.call<AboutResponse>("operations/about", { fs });
}
