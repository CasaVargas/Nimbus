# File Provider Complete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the File Provider extension production-ready with change tracking, lifecycle UI, error recovery, and thumbnails.

**Architecture:** Four independent sub-projects touching the Swift extension, Rust backend, and React frontend. Change tracking adds polling + diffing to the enumerator. Error recovery adds retry logic to RcloneClient. Lifecycle UI surfaces domain status in the mount list. Thumbnails use ImageIO to generate previews from downloaded images.

**Tech Stack:** Swift 6 (FileProvider, ImageIO, UniformTypeIdentifiers), Rust (Tauri commands), React (mount UI hooks/components), rclone RC API

---

## File Map

| Action | File | Sub-project |
|--------|------|-------------|
| Modify | `src-tauri/FileProviderExtension/RcloneClient.swift` | 3, 5, 6 |
| Modify | `src-tauri/FileProviderExtension/FileProviderEnumerator.swift` | 3 |
| Modify | `src-tauri/FileProviderExtension/FileProviderExtension.swift` | 6 |
| Modify | `src-tauri/FileProviderExtension/FileProviderItem.swift` | 6 |
| Modify | `src-tauri/src/commands/file_provider.rs` | 5 |
| Modify | `src-tauri/src/lib.rs` | 5 |
| Modify | `src/lib/tauri/file-provider.ts` | 5 |
| Modify | `src/hooks/use-file-provider-sync.ts` | 5 |
| Modify | `src/features/mount/components/mount-item.tsx` | 4 |

---

### Task 1: Add retry logic to RcloneClient (Sub-project 5)

This goes first because sub-projects 3 and 6 depend on a reliable RcloneClient.

**Files:**
- Modify: `src-tauri/FileProviderExtension/RcloneClient.swift`

- [ ] **Step 1: Add retry wrapper and port re-read**

Replace the existing `rcCall` method with a version that retries with exponential backoff and re-reads the port from SharedState on each retry:

```swift
    private func rcCall(method: String, params: [String: Any]) async throws -> [String: Any] {
        var lastError: Error = RcloneError.serverNotRunning
        let maxRetries = 3
        let delays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000] // 1s, 2s, 4s

        for attempt in 0..<maxRetries {
            // Re-read port on each attempt (main app may have restarted rclone)
            guard let port = sharedState.rclonePort else {
                lastError = RcloneError.serverNotRunning
                if attempt < maxRetries - 1 {
                    try await Task.sleep(nanoseconds: delays[attempt])
                }
                continue
            }

            do {
                return try await performRcCall(port: port, method: method, params: params)
            } catch {
                lastError = error
                logger.warning("rcCall attempt \(attempt + 1) failed: \(error.localizedDescription)")
                if attempt < maxRetries - 1 {
                    try await Task.sleep(nanoseconds: delays[attempt])
                }
            }
        }

        throw lastError
    }

    private func performRcCall(port: UInt16, method: String, params: [String: Any]) async throws -> [String: Any] {
        let url = URL(string: "http://127.0.0.1:\(port)/\(method)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RcloneError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw RcloneError.requestFailed(body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RcloneError.invalidResponse
        }

        return json
    }
```

- [ ] **Step 2: Add `listDirectoryRaw` for change tracking**

Add this method after the existing `listDirectory`:

```swift
    /// Returns raw rclone list entries for snapshot comparison
    func listDirectoryRaw(remotePath: String) async throws -> [[String: Any]] {
        let params: [String: Any] = [
            "fs": "\(remoteName):",
            "remote": remotePath,
            "opt": ["recurse": false, "noModTime": false]
        ]

        let result = try await rcCall(method: "operations/list", params: params)
        return result["list"] as? [[String: Any]] ?? []
    }
```

- [ ] **Step 3: Add `downloadFileToTemp` for thumbnails**

Add this method after `downloadFile`:

```swift
    /// Download a file to temp directory, returning just the URL (for thumbnail generation)
    func downloadFileToTemp(identifier: NSFileProviderItemIdentifier, maxSize: Int64 = 10_485_760) async throws -> URL {
        let item = try await fetchItem(identifier: identifier)

        // Skip files larger than maxSize
        if item.fileSize > maxSize {
            throw RcloneError.requestFailed("File too large for thumbnail: \(item.fileSize) bytes")
        }

        let remotePath = extractPath(from: identifier)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.nimbus.fileprovider.thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let localURL = tempDir.appendingPathComponent(item.filename)

        try? FileManager.default.removeItem(at: localURL)

        let params: [String: Any] = [
            "srcFs": "\(remoteName):",
            "srcRemote": remotePath,
            "dstFs": "/",
            "dstRemote": localURL.path,
        ]

        _ = try await rcCall(method: "operations/copyfile", params: params)
        return localURL
    }
```

- [ ] **Step 4: Update the temp directory name in `downloadFile`**

In the existing `downloadFile` method, change the temp directory from `com.streamcloned.fileprovider` to `com.nimbus.fileprovider`:

```swift
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.nimbus.fileprovider", isDirectory: true)
```

- [ ] **Step 5: Build and verify**

```bash
cd src-tauri/FileProviderExtension && xcodegen generate --quiet && xcodebuild \
    -project FileProviderExtension.xcodeproj \
    -scheme FileProviderExtension \
    -configuration Debug \
    -derivedDataPath ../target/extension-build \
    -allowProvisioningUpdates \
    -quiet || true
```

Check that compilation succeeds (codesign may fail due to xattrs — that's OK).

- [ ] **Step 6: Commit**

```bash
git add src-tauri/FileProviderExtension/RcloneClient.swift
git commit -m "feat(fileprovider): add retry logic, raw listing, and thumbnail download to RcloneClient"
```

---

### Task 2: Implement change tracking in enumerator (Sub-project 3)

**Files:**
- Modify: `src-tauri/FileProviderExtension/FileProviderEnumerator.swift`

- [ ] **Step 1: Replace the entire file**

```swift
import FileProvider
import os.log

// @unchecked Sendable: all stored properties are set at init and never mutated
// (cachedItems is only accessed from Task blocks serialized by the FP daemon);
// NSFileProviderEnumerator is called from the File Provider daemon which manages
// its own concurrency guarantees.
class FileProviderEnumerator: NSObject, NSFileProviderEnumerator, @unchecked Sendable {

    private let containerIdentifier: NSFileProviderItemIdentifier
    private let rclone: RcloneClient
    private let domain: NSFileProviderDomain

    /// Cached snapshot of the last enumeration for change diffing
    /// Key: item identifier raw value, Value: raw rclone entry
    private var cachedEntries: [String: [String: Any]] = [:]
    private var lastEnumerationDate: Date = .distantPast

    init(containerIdentifier: NSFileProviderItemIdentifier,
         rclone: RcloneClient,
         domain: NSFileProviderDomain) {
        self.containerIdentifier = containerIdentifier
        self.rclone = rclone
        self.domain = domain
        super.init()
    }

    func invalidate() {
        // No-op: no long-running state to clean up
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        nonisolated(unsafe) let observer = observer
        Task {
            do {
                let remotePath = self.remotePath(for: containerIdentifier)
                let rawEntries = try await rclone.listDirectoryRaw(remotePath: remotePath)

                // Build cache and items
                var newCache: [String: [String: Any]] = [:]
                var items: [NSFileProviderItem] = []

                for entry in rawEntries {
                    guard let item = FileProviderItem.from(
                        rcloneEntry: entry,
                        parentIdentifier: containerIdentifier,
                        remoteName: rclone.remoteName
                    ) else { continue }

                    newCache[item.itemIdentifier.rawValue] = entry
                    items.append(item)
                }

                self.cachedEntries = newCache
                self.lastEnumerationDate = Date()

                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
            } catch {
                logger.error("enumerateItems failed: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        nonisolated(unsafe) let observer = observer
        Task {
            do {
                let remotePath = self.remotePath(for: containerIdentifier)
                let rawEntries = try await rclone.listDirectoryRaw(remotePath: remotePath)

                var newCache: [String: [String: Any]] = [:]
                var updatedItems: [NSFileProviderItem] = []
                var newIdentifiers = Set<String>()

                for entry in rawEntries {
                    guard let item = FileProviderItem.from(
                        rcloneEntry: entry,
                        parentIdentifier: containerIdentifier,
                        remoteName: rclone.remoteName
                    ) else { continue }

                    let key = item.itemIdentifier.rawValue
                    newIdentifiers.insert(key)
                    newCache[key] = entry

                    // Check if this item is new or modified
                    if let oldEntry = self.cachedEntries[key] {
                        let oldModTime = oldEntry["ModTime"] as? String ?? ""
                        let newModTime = entry["ModTime"] as? String ?? ""
                        let oldSize = oldEntry["Size"] as? Int64 ?? 0
                        let newSize = entry["Size"] as? Int64 ?? 0

                        if oldModTime != newModTime || oldSize != newSize {
                            updatedItems.append(item)
                        }
                    } else {
                        // New item
                        updatedItems.append(item)
                    }
                }

                // Find deleted items
                let deletedIdentifiers = Set(self.cachedEntries.keys).subtracting(newIdentifiers)
                let deletedIds = deletedIdentifiers.map { NSFileProviderItemIdentifier($0) }

                self.cachedEntries = newCache
                self.lastEnumerationDate = Date()

                if !updatedItems.isEmpty {
                    observer.didUpdate(updatedItems)
                }
                if !deletedIds.isEmpty {
                    observer.didDeleteItems(withIdentifiers: deletedIds)
                }

                let anchorData = "\(Date().timeIntervalSince1970)".data(using: .utf8)!
                observer.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(anchorData), moreComing: false)
            } catch {
                logger.error("enumerateChanges failed: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let anchorData = "\(lastEnumerationDate.timeIntervalSince1970)".data(using: .utf8)!
        completionHandler(NSFileProviderSyncAnchor(anchorData))
    }

    // MARK: - Helpers

    private func remotePath(for identifier: NSFileProviderItemIdentifier) -> String {
        if identifier == .rootContainer {
            return ""
        }
        let raw = identifier.rawValue
        if let colonIndex = raw.firstIndex(of: ":") {
            return String(raw[raw.index(after: colonIndex)...])
        }
        return raw
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
cd src-tauri/FileProviderExtension && xcodegen generate --quiet && xcodebuild \
    -project FileProviderExtension.xcodeproj \
    -scheme FileProviderExtension \
    -configuration Debug \
    -derivedDataPath ../target/extension-build \
    -allowProvisioningUpdates \
    -quiet || true
```

- [ ] **Step 3: Commit**

```bash
git add src-tauri/FileProviderExtension/FileProviderEnumerator.swift
git commit -m "feat(fileprovider): implement real change tracking with snapshot diffing"
```

---

### Task 3: Add thumbnail support (Sub-project 6)

**Files:**
- Modify: `src-tauri/FileProviderExtension/FileProviderExtension.swift`
- Modify: `src-tauri/FileProviderExtension/FileProviderItem.swift`

- [ ] **Step 1: Add NSFileProviderThumbnailing conformance to FileProviderExtension.swift**

Add `import ImageIO` at the top of the file (after `import os.log`).

Add `, NSFileProviderThumbnailing` to the class declaration:

```swift
class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension, NSFileProviderThumbnailing, @unchecked Sendable {
```

Add this method before the closing `}` of the class:

```swift
    // MARK: - Thumbnails

    func fetchThumbnails(for itemIdentifiers: [NSFileProviderItemIdentifier],
                         requestedSize size: CGSize,
                         perThumbnailCompletionHandler: @escaping (NSFileProviderItemIdentifier, Data?, Error?) -> Void,
                         completionHandler: @escaping (Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: Int64(itemIdentifiers.count))
        nonisolated(unsafe) let perThumbnailCompletionHandler = perThumbnailCompletionHandler
        nonisolated(unsafe) let completionHandler = completionHandler

        Task {
            for identifier in itemIdentifiers {
                do {
                    let item = try await rclone.fetchItem(identifier: identifier)

                    // Only generate thumbnails for images
                    guard !item.isFolder, item.contentType.conforms(to: .image) else {
                        perThumbnailCompletionHandler(identifier, nil, nil)
                        progress.completedUnitCount += 1
                        continue
                    }

                    let fileURL = try await rclone.downloadFileToTemp(identifier: identifier)
                    defer { try? FileManager.default.removeItem(at: fileURL) }

                    // Generate thumbnail using ImageIO
                    let options: [CFString: Any] = [
                        kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                    ]

                    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                        perThumbnailCompletionHandler(identifier, nil, nil)
                        progress.completedUnitCount += 1
                        continue
                    }

                    // Convert CGImage to JPEG data
                    let mutableData = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
                        perThumbnailCompletionHandler(identifier, nil, nil)
                        progress.completedUnitCount += 1
                        continue
                    }
                    CGImageDestinationAddImage(destination, thumbnail, nil)
                    CGImageDestinationFinalize(destination)

                    perThumbnailCompletionHandler(identifier, mutableData as Data, nil)
                } catch {
                    logger.warning("Thumbnail generation failed for \(identifier.rawValue): \(error.localizedDescription)")
                    perThumbnailCompletionHandler(identifier, nil, nil)
                }
                progress.completedUnitCount += 1
            }
            completionHandler(nil)
        }

        return progress
    }
```

- [ ] **Step 2: Update FileProviderItem capabilities**

In `FileProviderItem.swift`, update the `capabilities` property to include thumbnails for non-folder items:

Replace the existing `capabilities` computed property:

```swift
    var capabilities: NSFileProviderItemCapabilities {
        if isFolder {
            return [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems, .allowsRenaming, .allowsDeleting]
        }
        return [.allowsReading, .allowsWriting, .allowsRenaming, .allowsDeleting, .allowsThumbnails]
    }
```

- [ ] **Step 3: Build and verify**

```bash
cd src-tauri/FileProviderExtension && xcodegen generate --quiet && xcodebuild \
    -project FileProviderExtension.xcodeproj \
    -scheme FileProviderExtension \
    -configuration Debug \
    -derivedDataPath ../target/extension-build \
    -allowProvisioningUpdates \
    -quiet || true
```

- [ ] **Step 4: Commit**

```bash
git add src-tauri/FileProviderExtension/FileProviderExtension.swift src-tauri/FileProviderExtension/FileProviderItem.swift
git commit -m "feat(fileprovider): add thumbnail support for image files via ImageIO"
```

---

### Task 4: Add stale domain cleanup command (Sub-project 5)

**Files:**
- Modify: `src-tauri/src/commands/file_provider.rs`
- Modify: `src-tauri/src/lib.rs`
- Modify: `src/lib/tauri/file-provider.ts`
- Modify: `src/hooks/use-file-provider-sync.ts`

- [ ] **Step 1: Add `fp_cleanup_stale_domains` Rust command**

Add this command after `fp_is_supported` in `file_provider.rs`:

```rust
#[tauri::command]
pub async fn fp_cleanup_stale_domains(
    active_remotes: Vec<String>,
) -> Result<Vec<String>, String> {
    let domains = fp_list_domains().await?;
    let mut removed = Vec::new();

    for domain in &domains {
        if !active_remotes.contains(&domain.identifier) {
            match run_domain_manager(&["remove", &domain.identifier]) {
                Ok(_) => {
                    removed.push(domain.identifier.clone());
                    log::info!("Cleaned up stale domain: {}", domain.identifier);
                }
                Err(e) => {
                    log::warn!("Failed to remove stale domain {}: {}", domain.identifier, e);
                }
            }
        }
    }

    Ok(removed)
}
```

- [ ] **Step 2: Register the command in lib.rs**

Add `fp_cleanup_stale_domains` to the invoke_handler list. Find the existing `fp_is_supported` in the handler and add the new command next to it.

- [ ] **Step 3: Add TypeScript wrapper**

Add to `src/lib/tauri/file-provider.ts`:

```typescript
export async function fpCleanupStaleDomains(activeRemotes: string[]): Promise<string[]> {
  return invoke<string[]>("fp_cleanup_stale_domains", { activeRemotes });
}
```

- [ ] **Step 4: Call cleanup on app startup**

Update `src/hooks/use-file-provider-sync.ts` to call cleanup on first sync:

```typescript
import { useEffect, useRef } from "react";
import { fpCleanupStaleDomains, fpSyncState } from "@/lib/tauri/file-provider";
import { getPlatform } from "@/lib/platform";

/**
 * Syncs File Provider shared state when the rclone daemon connects.
 * Writes rclone port and remote names to the App Group container
 * so the File Provider extension can discover the daemon.
 */
export function useFileProviderSync(daemonConnected: boolean, remotes: string[]) {
  const lastSyncRef = useRef<string>("");
  const cleanedUpRef = useRef(false);

  useEffect(() => {
    if (!daemonConnected || getPlatform() !== "macos") return;

    // Only sync when remotes actually change
    const key = remotes.sort().join(",");
    if (key === lastSyncRef.current) return;

    fpSyncState(remotes)
      .then(() => {
        lastSyncRef.current = key;
        console.log("File Provider state synced:", remotes);

        // Clean up stale domains on first sync
        if (!cleanedUpRef.current) {
          cleanedUpRef.current = true;
          fpCleanupStaleDomains(remotes)
            .then((removed) => {
              if (removed.length > 0) {
                console.log("Cleaned up stale File Provider domains:", removed);
              }
            })
            .catch((e) => console.error("Failed to cleanup stale domains:", e));
        }
      })
      .catch((e) => {
        console.error("Failed to sync File Provider state:", e);
      });
  }, [daemonConnected, remotes]);
}
```

- [ ] **Step 5: Verify TypeScript compiles**

```bash
npx tsc --noEmit
```

- [ ] **Step 6: Verify Rust compiles**

```bash
cd src-tauri && cargo check
```

- [ ] **Step 7: Commit**

```bash
git add src-tauri/src/commands/file_provider.rs src-tauri/src/lib.rs \
  src/lib/tauri/file-provider.ts src/hooks/use-file-provider-sync.ts
git commit -m "feat(fileprovider): add stale domain cleanup on app startup"
```

---

### Task 5: Mount lifecycle UI for fileprovider (Sub-project 4)

**Files:**
- Modify: `src/features/mount/components/mount-item.tsx`

- [ ] **Step 1: Update MountItem to show registration status and re-register button**

Replace the entire file:

```typescript
import { CircleIcon, Loader2Icon, RefreshCwIcon } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { fpAddDomain } from "@/lib/tauri/file-provider";
import type { MountConfig } from "@/stores/mount-store";
import { useMountStore } from "@/stores/mount-store";
import { useMountRemote, useUnmountRemote } from "../hooks/use-mounts";
import { fpRemoveDomain } from "@/lib/tauri/file-provider";

interface MountItemProps {
  config: MountConfig;
  isActive: boolean;
}

export function MountItem({ config, isActive }: MountItemProps) {
  const toggleAutoMount = useMountStore((s) => s.toggleAutoMount);
  const removeConfig = useMountStore((s) => s.removeConfig);
  const mountMutation = useMountRemote();
  const unmountMutation = useUnmountRemote();
  const [isReregistering, setIsReregistering] = useState(false);

  const isLoading = mountMutation.isPending || unmountMutation.isPending;
  const isFileProvider = config.backend === "fileprovider";

  function handleToggleMount() {
    if (isActive) {
      unmountMutation.mutate(
        { mountPoint: config.mountPoint, backend: config.backend },
        { onError: (e) => toast.error(`Unmount failed: ${e.message || e}`) },
      );
    } else {
      mountMutation.mutate(
        {
          fs: config.remote,
          mountPoint: config.mountPoint,
          vfsOpt: config.vfsMode === "read-only" ? { readOnly: true } : undefined,
          backend: config.backend,
        },
        { onError: (e) => toast.error(`Mount failed: ${e.message || e}`) },
      );
    }
  }

  async function handleRemove() {
    if (isFileProvider) {
      const remoteName = config.remote.replace(/:$/, "");
      try {
        await fpRemoveDomain(remoteName);
        toast.success(`Removed ${config.mountPoint} from Finder`);
      } catch (err) {
        toast.error(
          `Failed to remove from Finder: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }
    removeConfig(config.mountPoint);
  }

  async function handleReregister() {
    const remoteName = config.remote.replace(/:$/, "");
    setIsReregistering(true);
    try {
      await fpAddDomain(remoteName, config.mountPoint);
      toast.success(`Re-registered ${config.mountPoint} in Finder`);
    } catch (err) {
      toast.error(
        `Failed to re-register: ${err instanceof Error ? err.message : String(err)}`,
      );
    } finally {
      setIsReregistering(false);
    }
  }

  const isRegistered = isFileProvider && isActive;
  const needsReregister = isFileProvider && !isActive;

  return (
    <div className="flex items-center gap-4 rounded-lg border p-4">
      <CircleIcon
        className={`size-3 shrink-0 ${
          isRegistered || (!isFileProvider && isActive)
            ? "fill-green-500 text-green-500"
            : needsReregister
              ? "fill-red-500 text-red-500"
              : "fill-muted text-muted"
        }`}
      />

      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate">{config.remote}</p>
        <p className="text-xs text-muted-foreground font-mono truncate">
          {isFileProvider
            ? isRegistered
              ? `Finder — ${config.mountPoint}`
              : `Not registered — ${config.mountPoint}`
            : config.mountPoint}
        </p>
      </div>

      {!isFileProvider && (
        <label className="flex items-center gap-2 text-xs text-muted-foreground cursor-pointer select-none">
          <input
            type="checkbox"
            checked={config.autoMount}
            onChange={() => toggleAutoMount(config.mountPoint)}
            className="rounded"
          />
          Auto
        </label>
      )}

      {!isFileProvider && (
        <Button
          variant={isActive ? "destructive" : "outline"}
          size="sm"
          onClick={handleToggleMount}
          disabled={isLoading}
        >
          {isLoading ? (
            <Loader2Icon className="size-3.5 animate-spin" />
          ) : isActive ? (
            "Unmount"
          ) : (
            "Mount"
          )}
        </Button>
      )}

      {needsReregister && (
        <Button
          variant="outline"
          size="sm"
          onClick={handleReregister}
          disabled={isReregistering}
        >
          {isReregistering ? (
            <Loader2Icon className="size-3.5 animate-spin" />
          ) : (
            <>
              <RefreshCwIcon className="size-3.5" />
              Re-register
            </>
          )}
        </Button>
      )}

      <Button
        variant="ghost"
        size="sm"
        onClick={handleRemove}
        disabled={!isFileProvider && isActive}
      >
        Remove
      </Button>
    </div>
  );
}
```

Key changes:
- `isRegistered` = fileprovider + isActive (domain found in fpListDomains)
- `needsReregister` = fileprovider + not isActive (domain missing)
- Red dot when not registered, green when registered
- "Re-register" button with spinner when domain is missing
- Status text shows "Finder — name" when registered, "Not registered — name" when not

- [ ] **Step 2: Verify it compiles**

```bash
npx tsc --noEmit
```

- [ ] **Step 3: Commit**

```bash
git add src/features/mount/components/mount-item.tsx
git commit -m "feat(fileprovider): show registration status and re-register button in mount UI"
```

---

### Task 6: Build extension and final verification

- [ ] **Step 1: Full extension build**

```bash
bash src-tauri/build-extension.sh 2>&1
```

Expected: `File Provider build complete.`

- [ ] **Step 2: Verify all TypeScript compiles**

```bash
npx tsc --noEmit
```

- [ ] **Step 3: Verify Rust compiles**

```bash
cd src-tauri && cargo check
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(fileprovider): complete File Provider implementation — change tracking, thumbnails, error recovery, lifecycle UI"
```
