# Tier 1: Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add rclone.conf import, folder bookmarks, and download/evict management to both the Tauri and SwiftUI apps.

**Architecture:** Each feature is a thin UI layer over rclone RC API calls. Bookmarks use a persisted store (Zustand for Tauri, JSON file for SwiftUI). Download/evict extends the existing File Provider extension. Both apps follow their established patterns: React Query + Zustand for Tauri, @Observable ViewModels + environment injection for SwiftUI.

**Tech Stack:** React 19, TypeScript, Zustand, TanStack Query, Tailwind CSS 4, Biome (Tauri); Swift 6, SwiftUI, @Observable, RcloneKit (SwiftUI); NSFileProviderReplicatedExtension (File Provider)

---

## Feature 1: rclone.conf Import

### Task 1: INI Parser Utility (Tauri Frontend)

**Files:**
- Create: `src/lib/rclone/ini-parser.ts`
- Create: `src/lib/rclone/ini-parser.test.ts`

- [ ] **Step 1: Write the failing test for INI parsing**

```typescript
// src/lib/rclone/ini-parser.test.ts
import { describe, it, expect } from "vitest";
import { parseRcloneConf } from "./ini-parser";

describe("parseRcloneConf", () => {
  it("parses a single remote", () => {
    const input = `[myremote]
type = drive
client_id = xxx
client_secret = yyy
`;
    const result = parseRcloneConf(input);
    expect(result).toEqual([
      {
        name: "myremote",
        type: "drive",
        parameters: { client_id: "xxx", client_secret: "yyy" },
      },
    ]);
  });

  it("parses multiple remotes", () => {
    const input = `[gdrive]
type = drive
scope = drive

[s3bucket]
type = s3
provider = AWS
region = us-east-1
`;
    const result = parseRcloneConf(input);
    expect(result).toHaveLength(2);
    expect(result[0].name).toBe("gdrive");
    expect(result[0].type).toBe("drive");
    expect(result[0].parameters).toEqual({ scope: "drive" });
    expect(result[1].name).toBe("s3bucket");
    expect(result[1].type).toBe("s3");
    expect(result[1].parameters).toEqual({ provider: "AWS", region: "us-east-1" });
  });

  it("ignores comments and blank lines", () => {
    const input = `# This is a comment

[myremote]
type = drive
# another comment
token = abc
`;
    const result = parseRcloneConf(input);
    expect(result).toHaveLength(1);
    expect(result[0].parameters).toEqual({ token: "abc" });
  });

  it("returns empty array for empty input", () => {
    expect(parseRcloneConf("")).toEqual([]);
  });

  it("handles values with equals signs", () => {
    const input = `[crypt]
type = crypt
password = obscured=abc123==
`;
    const result = parseRcloneConf(input);
    expect(result[0].parameters.password).toBe("obscured=abc123==");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm run test -- src/lib/rclone/ini-parser.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Implement the INI parser**

```typescript
// src/lib/rclone/ini-parser.ts
export interface ParsedRemote {
  name: string;
  type: string;
  parameters: Record<string, string>;
}

export function parseRcloneConf(content: string): ParsedRemote[] {
  const remotes: ParsedRemote[] = [];
  let current: { name: string; params: Record<string, string> } | null = null;

  for (const rawLine of content.split("\n")) {
    const line = rawLine.trim();

    if (line === "" || line.startsWith("#") || line.startsWith(";")) {
      continue;
    }

    const sectionMatch = line.match(/^\[(.+)\]$/);
    if (sectionMatch) {
      if (current) {
        remotes.push({
          name: current.name,
          type: current.params.type ?? "unknown",
          parameters: Object.fromEntries(
            Object.entries(current.params).filter(([k]) => k !== "type"),
          ),
        });
      }
      current = { name: sectionMatch[1], params: {} };
      continue;
    }

    if (current) {
      const eqIndex = line.indexOf("=");
      if (eqIndex !== -1) {
        const key = line.slice(0, eqIndex).trim();
        const value = line.slice(eqIndex + 1).trim();
        current.params[key] = value;
      }
    }
  }

  if (current) {
    remotes.push({
      name: current.name,
      type: current.params.type ?? "unknown",
      parameters: Object.fromEntries(
        Object.entries(current.params).filter(([k]) => k !== "type"),
      ),
    });
  }

  return remotes;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm run test -- src/lib/rclone/ini-parser.test.ts`
Expected: All 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/lib/rclone/ini-parser.ts src/lib/rclone/ini-parser.test.ts
git commit -m "feat: add rclone.conf INI parser utility with tests"
```

---

### Task 2: Import Config Dialog (Tauri Frontend)

**Files:**
- Create: `src/features/remotes/components/import-config-dialog.tsx`
- Modify: `src/features/remotes/pages/remotes-page.tsx` (add Import button)

- [ ] **Step 1: Create the ImportConfigDialog component**

```tsx
// src/features/remotes/components/import-config-dialog.tsx
import { useState, useCallback } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { open } from "@tauri-apps/plugin-dialog";
import { readTextFile } from "@tauri-apps/plugin-fs";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { parseRcloneConf, type ParsedRemote } from "@/lib/rclone/ini-parser";
import { createRemote } from "@/lib/rclone/remotes";
import { useRemotes } from "../hooks/use-remotes";

interface ImportConfigDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

interface ImportCandidate extends ParsedRemote {
  selected: boolean;
  conflict: boolean;
  renamedTo: string;
}

export function ImportConfigDialog({
  open: isOpen,
  onOpenChange,
}: ImportConfigDialogProps) {
  const [step, setStep] = useState<"pick" | "review">("pick");
  const [candidates, setCandidates] = useState<ImportCandidate[]>([]);
  const [importing, setImporting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [importedCount, setImportedCount] = useState(0);

  const { data: existingRemotes } = useRemotes();
  const queryClient = useQueryClient();

  const existingNames = new Set(existingRemotes?.map((r) => r.name) ?? []);

  const handlePickFile = useCallback(async () => {
    try {
      const selected = await open({
        multiple: false,
        filters: [
          { name: "rclone config", extensions: ["conf"] },
          { name: "All files", extensions: ["*"] },
        ],
      });
      if (!selected) return;

      const content = await readTextFile(selected);
      const parsed = parseRcloneConf(content);

      if (parsed.length === 0) {
        setError("No remotes found in this file.");
        return;
      }

      setCandidates(
        parsed.map((r) => ({
          ...r,
          selected: true,
          conflict: existingNames.has(r.name),
          renamedTo: r.name,
        })),
      );
      setError(null);
      setStep("review");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to read file");
    }
  }, [existingNames]);

  const handleImport = useCallback(async () => {
    const toImport = candidates.filter((c) => c.selected);
    if (toImport.length === 0) return;

    setImporting(true);
    setError(null);
    let count = 0;

    try {
      for (const candidate of toImport) {
        const name = candidate.conflict
          ? candidate.renamedTo
          : candidate.name;
        await createRemote(name, candidate.type, candidate.parameters);
        count++;
      }
      setImportedCount(count);
      queryClient.invalidateQueries({ queryKey: ["remotes"] });
      onOpenChange(false);
    } catch (e) {
      setError(
        `Imported ${count}/${toImport.length}. Error: ${e instanceof Error ? e.message : "Unknown error"}`,
      );
    } finally {
      setImporting(false);
    }
  }, [candidates, queryClient, onOpenChange]);

  const handleClose = useCallback(
    (open: boolean) => {
      if (!open) {
        setTimeout(() => {
          setStep("pick");
          setCandidates([]);
          setError(null);
          setImportedCount(0);
        }, 200);
      }
      onOpenChange(open);
    },
    [onOpenChange],
  );

  const toggleCandidate = (index: number) => {
    setCandidates((prev) =>
      prev.map((c, i) => (i === index ? { ...c, selected: !c.selected } : c)),
    );
  };

  const renameCandidate = (index: number, newName: string) => {
    setCandidates((prev) =>
      prev.map((c, i) => (i === index ? { ...c, renamedTo: newName } : c)),
    );
  };

  const selectedCount = candidates.filter((c) => c.selected).length;

  return (
    <Dialog open={isOpen} onOpenChange={handleClose}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Import rclone Config</DialogTitle>
          <DialogDescription>
            {step === "pick"
              ? "Select an rclone.conf file to import remotes from."
              : `Found ${candidates.length} remote${candidates.length !== 1 ? "s" : ""}. Select which to import.`}
          </DialogDescription>
        </DialogHeader>

        {step === "pick" && (
          <div className="flex flex-col items-center gap-4 py-6">
            <Button onClick={handlePickFile}>Choose File...</Button>
          </div>
        )}

        {step === "review" && (
          <div className="max-h-64 space-y-3 overflow-y-auto">
            {candidates.map((candidate, index) => (
              <div
                key={candidate.name}
                className="flex items-center gap-3 rounded-md border p-3"
              >
                <Checkbox
                  checked={candidate.selected}
                  onCheckedChange={() => toggleCandidate(index)}
                />
                <div className="flex-1">
                  {candidate.conflict ? (
                    <div className="space-y-1">
                      <p className="text-sm text-destructive">
                        "{candidate.name}" already exists — rename:
                      </p>
                      <Input
                        value={candidate.renamedTo}
                        onChange={(e) =>
                          renameCandidate(index, e.target.value)
                        }
                        className="h-8"
                      />
                    </div>
                  ) : (
                    <p className="text-sm font-medium">{candidate.name}</p>
                  )}
                  <p className="text-xs text-muted-foreground">
                    {candidate.type}
                  </p>
                </div>
              </div>
            ))}
          </div>
        )}

        {error && <p className="text-sm text-destructive">{error}</p>}

        {step === "review" && (
          <DialogFooter>
            <Button variant="outline" onClick={() => handleClose(false)}>
              Cancel
            </Button>
            <Button
              onClick={handleImport}
              disabled={importing || selectedCount === 0}
            >
              {importing
                ? "Importing..."
                : `Import ${selectedCount} Remote${selectedCount !== 1 ? "s" : ""}`}
            </Button>
          </DialogFooter>
        )}
      </DialogContent>
    </Dialog>
  );
}
```

- [ ] **Step 2: Add the Import button to the Remotes page**

In `src/features/remotes/pages/remotes-page.tsx`, add an "Import Config" button next to the existing "Add Remote" button. Import the dialog and wire up `showImportDialog` state:

```tsx
// Add to existing imports
import { ImportConfigDialog } from "../components/import-config-dialog";
import { Upload } from "lucide-react";

// Add state alongside existing showAddRemote state
const [showImportDialog, setShowImportDialog] = useState(false);

// Add button next to the existing Add Remote button in the header
<Button variant="outline" onClick={() => setShowImportDialog(true)}>
  <Upload className="mr-2 h-4 w-4" />
  Import Config
</Button>

// Add dialog alongside existing dialogs
<ImportConfigDialog
  open={showImportDialog}
  onOpenChange={setShowImportDialog}
/>
```

- [ ] **Step 3: Verify the build compiles**

Run: `npm run build`
Expected: Build succeeds with no TypeScript errors

- [ ] **Step 4: Commit**

```bash
git add src/features/remotes/components/import-config-dialog.tsx src/features/remotes/pages/remotes-page.tsx
git commit -m "feat: add rclone.conf import dialog to Tauri remotes page"
```

---

### Task 3: rclone.conf Import (SwiftUI)

**Files:**
- Create: `Nimbus/Nimbus/Utilities/RcloneConfParser.swift`
- Create: `Nimbus/Nimbus/Views/Remotes/ImportConfigSheet.swift`
- Modify: `Nimbus/Nimbus/Views/Remotes/RemotesView.swift` (add Import button)
- Create: `Nimbus/NimbusTests/RcloneConfParserTests.swift` (if test target exists)

- [ ] **Step 1: Create the INI parser**

```swift
// Nimbus/Nimbus/Utilities/RcloneConfParser.swift
import Foundation

struct ParsedRemote: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let type: String
    let parameters: [String: String]
}

enum RcloneConfParser {
    static func parse(_ content: String) -> [ParsedRemote] {
        var remotes: [ParsedRemote] = []
        var currentName: String?
        var currentParams: [String: String] = [:]

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }

            if line.hasPrefix("["), line.hasSuffix("]") {
                if let name = currentName {
                    let type = currentParams.removeValue(forKey: "type") ?? "unknown"
                    remotes.append(ParsedRemote(name: name, type: type, parameters: currentParams))
                }
                currentName = String(line.dropFirst().dropLast())
                currentParams = [:]
                continue
            }

            if currentName != nil, let eqIndex = line.firstIndex(of: "=") {
                let key = line[line.startIndex..<eqIndex].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
                currentParams[key] = value
            }
        }

        if let name = currentName {
            let type = currentParams.removeValue(forKey: "type") ?? "unknown"
            remotes.append(ParsedRemote(name: name, type: type, parameters: currentParams))
        }

        return remotes
    }
}
```

- [ ] **Step 2: Create the ImportConfigSheet view**

```swift
// Nimbus/Nimbus/Views/Remotes/ImportConfigSheet.swift
import SwiftUI

struct ImportConfigSheet: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [ImportCandidate] = []
    @State private var importing = false
    @State private var error: String?
    @State private var existingNames: Set<String> = []

    struct ImportCandidate: Identifiable {
        let id = UUID()
        let parsed: ParsedRemote
        var selected: Bool = true
        var conflict: Bool
        var renamedTo: String
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Import rclone Config")
                .font(.headline)

            if candidates.isEmpty {
                pickFileView
            } else {
                reviewView
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .task {
            if daemon.status == .connected {
                do {
                    let names = try await daemon.client.listRemotes()
                    existingNames = Set(names)
                } catch {}
            }
        }
    }

    private var pickFileView: some View {
        VStack(spacing: 12) {
            Text("Select an rclone.conf file to import remotes from.")
                .foregroundStyle(.secondary)

            Button("Choose File...") {
                pickFile()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }

    private var reviewView: some View {
        VStack(spacing: 12) {
            Text("Found \(candidates.count) remote\(candidates.count == 1 ? "" : "s"). Select which to import.")
                .foregroundStyle(.secondary)

            List($candidates) { $candidate in
                HStack {
                    Toggle("", isOn: $candidate.selected)
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                    VStack(alignment: .leading) {
                        if candidate.conflict {
                            Text("\"\(candidate.parsed.name)\" already exists — rename:")
                                .font(.caption)
                                .foregroundStyle(.red)
                            TextField("New name", text: $candidate.renamedTo)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        } else {
                            Text(candidate.parsed.name)
                                .font(.body)
                        }
                        Text(candidate.parsed.type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .frame(maxHeight: 200)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(importing ? "Importing..." : "Import \(selectedCount) Remote\(selectedCount == 1 ? "" : "s")") {
                    Task { await importSelected() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(importing || selectedCount == 0)
            }
        }
    }

    private var selectedCount: Int {
        candidates.filter(\.selected).count
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "conf")!, .plainText]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let parsed = RcloneConfParser.parse(content)

            if parsed.isEmpty {
                error = "No remotes found in this file."
                return
            }

            candidates = parsed.map { remote in
                ImportCandidate(
                    parsed: remote,
                    conflict: existingNames.contains(remote.name),
                    renamedTo: remote.name
                )
            }
            error = nil
        } catch {
            self.error = "Failed to read file: \(error.localizedDescription)"
        }
    }

    private func importSelected() async {
        let toImport = candidates.filter(\.selected)
        guard !toImport.isEmpty else { return }

        importing = true
        error = nil
        var count = 0

        do {
            for candidate in toImport {
                let name = candidate.conflict ? candidate.renamedTo : candidate.parsed.name
                try await daemon.client.createRemote(
                    name: name,
                    type: candidate.parsed.type,
                    parameters: candidate.parsed.parameters
                )
                count += 1
            }
            dismiss()
        } catch {
            self.error = "Imported \(count)/\(toImport.count). Error: \(error.localizedDescription)"
        }

        importing = false
    }
}
```

- [ ] **Step 3: Add Import button to RemotesView**

In `Nimbus/Nimbus/Views/Remotes/RemotesView.swift`, add state and toolbar button:

```swift
// Add state
@State private var showImportConfig = false

// Add toolbar button (next to existing Add Remote button)
.toolbar {
    ToolbarItem {
        Button {
            showImportConfig = true
        } label: {
            Label("Import Config", systemImage: "square.and.arrow.down")
        }
    }
}

// Add sheet
.sheet(isPresented: $showImportConfig) {
    ImportConfigSheet()
}
```

- [ ] **Step 4: Verify the build compiles**

Run: `cd Nimbus && xcodegen generate && xcodebuild -scheme Nimbus build`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Nimbus/Nimbus/Utilities/RcloneConfParser.swift Nimbus/Nimbus/Views/Remotes/ImportConfigSheet.swift Nimbus/Nimbus/Views/Remotes/RemotesView.swift
git commit -m "feat: add rclone.conf import to SwiftUI remotes view"
```

---

## Feature 2: Folder Bookmarks

### Task 4: Bookmark Store (Tauri Frontend)

**Files:**
- Create: `src/stores/bookmark-store.ts`
- Create: `src/stores/bookmark-store.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// src/stores/bookmark-store.test.ts
import { describe, it, expect, beforeEach } from "vitest";
import { useBookmarkStore } from "./bookmark-store";

describe("bookmarkStore", () => {
  beforeEach(() => {
    useBookmarkStore.setState({ bookmarks: [] });
  });

  it("adds a bookmark", () => {
    const { addBookmark } = useBookmarkStore.getState();
    addBookmark("gdrive", "Documents/Work", "Work Docs");

    const { bookmarks } = useBookmarkStore.getState();
    expect(bookmarks).toHaveLength(1);
    expect(bookmarks[0]).toMatchObject({
      remoteName: "gdrive",
      path: "Documents/Work",
      label: "Work Docs",
      order: 0,
    });
    expect(bookmarks[0].id).toBeDefined();
  });

  it("removes a bookmark", () => {
    const { addBookmark } = useBookmarkStore.getState();
    addBookmark("gdrive", "path1", "Bookmark 1");
    addBookmark("s3", "path2", "Bookmark 2");

    const id = useBookmarkStore.getState().bookmarks[0].id;
    useBookmarkStore.getState().removeBookmark(id);

    const { bookmarks } = useBookmarkStore.getState();
    expect(bookmarks).toHaveLength(1);
    expect(bookmarks[0].label).toBe("Bookmark 2");
  });

  it("renames a bookmark", () => {
    const { addBookmark } = useBookmarkStore.getState();
    addBookmark("gdrive", "path", "Old Name");

    const id = useBookmarkStore.getState().bookmarks[0].id;
    useBookmarkStore.getState().renameBookmark(id, "New Name");

    expect(useBookmarkStore.getState().bookmarks[0].label).toBe("New Name");
  });

  it("reorders bookmarks", () => {
    const { addBookmark } = useBookmarkStore.getState();
    addBookmark("a", "p1", "First");
    addBookmark("b", "p2", "Second");
    addBookmark("c", "p3", "Third");

    const ids = useBookmarkStore.getState().bookmarks.map((b) => b.id);
    useBookmarkStore.getState().reorderBookmarks([ids[2], ids[0], ids[1]]);

    const labels = useBookmarkStore.getState().bookmarks.map((b) => b.label);
    expect(labels).toEqual(["Third", "First", "Second"]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm run test -- src/stores/bookmark-store.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Implement the bookmark store**

```typescript
// src/stores/bookmark-store.ts
import { create } from "zustand";
import { persist } from "zustand/middleware";

export interface Bookmark {
  id: string;
  remoteName: string;
  path: string;
  label: string;
  order: number;
}

interface BookmarkState {
  bookmarks: Bookmark[];
  addBookmark: (remoteName: string, path: string, label: string) => void;
  removeBookmark: (id: string) => void;
  renameBookmark: (id: string, label: string) => void;
  reorderBookmarks: (orderedIds: string[]) => void;
}

export const useBookmarkStore = create<BookmarkState>()(
  persist(
    (set) => ({
      bookmarks: [],

      addBookmark: (remoteName, path, label) =>
        set((state) => ({
          bookmarks: [
            ...state.bookmarks,
            {
              id: crypto.randomUUID(),
              remoteName,
              path,
              label,
              order: state.bookmarks.length,
            },
          ],
        })),

      removeBookmark: (id) =>
        set((state) => ({
          bookmarks: state.bookmarks
            .filter((b) => b.id !== id)
            .map((b, i) => ({ ...b, order: i })),
        })),

      renameBookmark: (id, label) =>
        set((state) => ({
          bookmarks: state.bookmarks.map((b) =>
            b.id === id ? { ...b, label } : b,
          ),
        })),

      reorderBookmarks: (orderedIds) =>
        set((state) => {
          const byId = new Map(state.bookmarks.map((b) => [b.id, b]));
          return {
            bookmarks: orderedIds
              .map((id, i) => {
                const b = byId.get(id);
                return b ? { ...b, order: i } : null;
              })
              .filter((b): b is Bookmark => b !== null),
          };
        }),
    }),
    { name: "nimbus-bookmarks" },
  ),
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm run test -- src/stores/bookmark-store.test.ts`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/stores/bookmark-store.ts src/stores/bookmark-store.test.ts
git commit -m "feat: add bookmark Zustand store with persistence"
```

---

### Task 5: Sidebar Bookmarks Section (Tauri Frontend)

**Files:**
- Modify: `src/components/sidebar.tsx` (add Bookmarks section below nav items)

- [ ] **Step 1: Add the Bookmarks section to the sidebar**

In `src/components/sidebar.tsx`, add imports and a Bookmarks section after the existing nav items loop:

```tsx
// Add to imports
import { useBookmarkStore, type Bookmark } from "@/stores/bookmark-store";
import { useNavigate } from "react-router-dom";
import { FolderHeart, X } from "lucide-react";

// Inside the sidebar component, after the nav items map and before the bottom section:
// Add this after the closing </nav> of the main nav items

const bookmarks = useBookmarkStore((s) => s.bookmarks);
const removeBookmark = useBookmarkStore((s) => s.removeBookmark);
const navigate = useNavigate();

// Render bookmarks section (only if there are bookmarks)
{bookmarks.length > 0 && (
  <div className="mt-4 border-t pt-4">
    {!collapsed && (
      <p className="mb-2 px-3 text-xs font-medium text-muted-foreground">
        Bookmarks
      </p>
    )}
    <div className="space-y-1 px-2">
      {bookmarks.map((bookmark) => (
        <Tooltip key={bookmark.id}>
          <TooltipTrigger asChild>
            <button
              type="button"
              onClick={() =>
                navigate(
                  `/browser?remote=${encodeURIComponent(bookmark.remoteName)}&path=${encodeURIComponent(bookmark.path)}`,
                )
              }
              className="group flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground"
            >
              <FolderHeart className="h-4 w-4 shrink-0" />
              {!collapsed && (
                <>
                  <span className="truncate">{bookmark.label}</span>
                  <X
                    className="ml-auto h-3 w-3 shrink-0 opacity-0 transition-opacity group-hover:opacity-100"
                    onClick={(e) => {
                      e.stopPropagation();
                      removeBookmark(bookmark.id);
                    }}
                  />
                </>
              )}
            </button>
          </TooltipTrigger>
          <TooltipContent side="right">
            {bookmark.label} ({bookmark.remoteName}:{bookmark.path})
          </TooltipContent>
        </Tooltip>
      ))}
    </div>
  </div>
)}
```

- [ ] **Step 2: Verify the build compiles**

Run: `npm run build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add src/components/sidebar.tsx
git commit -m "feat: display bookmarks section in Tauri sidebar"
```

---

### Task 6: "Add to Bookmarks" Context Menu Action (Tauri Frontend)

**Files:**
- Modify: `src/features/browser/components/file-context-menu.tsx` (add bookmark action for folders)

- [ ] **Step 1: Add the bookmark action to the context menu**

In `src/features/browser/components/file-context-menu.tsx`, add the bookmark option for directories:

```tsx
// Add to imports
import { useBookmarkStore } from "@/stores/bookmark-store";
import { FolderHeart } from "lucide-react";

// Inside the component, add store access
const addBookmark = useBookmarkStore((s) => s.addBookmark);

// Add this menu item inside the context menu, after existing items,
// only when the item is a directory:
{file.isDir && (
  <>
    <ContextMenuSeparator />
    <ContextMenuItem
      onClick={() => {
        const fullPath = currentPath
          ? `${currentPath}/${file.name}`
          : file.name;
        addBookmark(remote, fullPath, file.name);
      }}
    >
      <FolderHeart className="mr-2 h-4 w-4" />
      Add to Bookmarks
    </ContextMenuItem>
  </>
)}
```

Note: The `remote` and `currentPath` props need to be passed to the context menu component from the browser page. Add them to the component's props interface if not already available.

- [ ] **Step 2: Verify the build compiles**

Run: `npm run build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add src/features/browser/components/file-context-menu.tsx
git commit -m "feat: add 'Add to Bookmarks' to folder context menu"
```

---

### Task 7: Bookmark Store (SwiftUI)

**Files:**
- Create: `Nimbus/Nimbus/State/BookmarkStore.swift`

- [ ] **Step 1: Create the BookmarkStore**

```swift
// Nimbus/Nimbus/State/BookmarkStore.swift
import Foundation

struct FolderBookmark: Codable, Identifiable, Sendable {
    let id: UUID
    var remoteName: String
    var path: String
    var label: String
    var order: Int

    init(remoteName: String, path: String, label: String, order: Int) {
        self.id = UUID()
        self.remoteName = remoteName
        self.path = path
        self.label = label
        self.order = order
    }
}

@Observable
@MainActor
final class BookmarkStore {
    private(set) var bookmarks: [FolderBookmark] = []
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let nimbus = appSupport.appendingPathComponent("Nimbus", isDirectory: true)
        try? FileManager.default.createDirectory(at: nimbus, withIntermediateDirectories: true)
        fileURL = nimbus.appendingPathComponent("bookmarks.json")
        load()
    }

    func addBookmark(remoteName: String, path: String, label: String) {
        let bookmark = FolderBookmark(
            remoteName: remoteName,
            path: path,
            label: label,
            order: bookmarks.count
        )
        bookmarks.append(bookmark)
        save()
        syncToAppGroup()
    }

    func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        for i in bookmarks.indices {
            bookmarks[i].order = i
        }
        save()
        syncToAppGroup()
    }

    func renameBookmark(id: UUID, label: String) {
        if let index = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks[index].label = label
            save()
        }
    }

    func reorder(fromOffsets: IndexSet, toOffset: Int) {
        bookmarks.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for i in bookmarks.indices {
            bookmarks[i].order = i
        }
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            bookmarks = try JSONDecoder().decode([FolderBookmark].self, from: data)
                .sorted { $0.order < $1.order }
        } catch {
            bookmarks = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            try data.write(to: fileURL, options: .atomic)
        } catch {}
    }

    private func syncToAppGroup() {
        guard let defaults = UserDefaults(suiteName: "group.app.casavargas.nimbus") else { return }
        let simplified = bookmarks.map { ["remote": $0.remoteName, "path": $0.path, "label": $0.label] }
        defaults.set(simplified, forKey: "bookmarks")
    }
}
```

- [ ] **Step 2: Register BookmarkStore in NimbusApp.swift**

In `Nimbus/Nimbus/NimbusApp.swift`:

```swift
// Add state property alongside existing stores
@State private var bookmarkStore = BookmarkStore()

// Add environment modifier alongside existing ones
.environment(bookmarkStore)
```

- [ ] **Step 3: Verify the build compiles**

Run: `cd Nimbus && xcodegen generate && xcodebuild -scheme Nimbus build`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Nimbus/Nimbus/State/BookmarkStore.swift Nimbus/Nimbus/NimbusApp.swift
git commit -m "feat: add BookmarkStore with JSON persistence and app group sync"
```

---

### Task 8: Sidebar Bookmarks Section (SwiftUI)

**Files:**
- Modify: `Nimbus/Nimbus/Views/Sidebar.swift` (add Bookmarks section)

- [ ] **Step 1: Add bookmarks to the sidebar**

In `Nimbus/Nimbus/Views/Sidebar.swift`, add a bookmarks section below the existing list:

```swift
// Add environment access at top of Sidebar struct
@Environment(BookmarkStore.self) private var bookmarkStore

// After the existing List(SidebarItem.allCases, selection: $selection) block,
// add a bookmarks section inside the same List or as a separate Section:

if !bookmarkStore.bookmarks.isEmpty {
    Section("Bookmarks") {
        ForEach(bookmarkStore.bookmarks) { bookmark in
            Button {
                onBookmarkSelected?(bookmark.remoteName, bookmark.path)
            } label: {
                Label {
                    VStack(alignment: .leading) {
                        Text(bookmark.label)
                            .lineLimit(1)
                        Text("\(bookmark.remoteName):\(bookmark.path)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } icon: {
                    Image(systemName: "folder.badge.star")
                }
            }
            .contextMenu {
                Button("Remove Bookmark", role: .destructive) {
                    bookmarkStore.removeBookmark(id: bookmark.id)
                }
            }
        }
        .onMove { from, to in
            bookmarkStore.reorder(fromOffsets: from, toOffset: to)
        }
    }
}
```

Add a callback property to the Sidebar struct:

```swift
var onBookmarkSelected: ((String, String) -> Void)?
```

Wire this up in ContentView to navigate to the browser with the bookmark's remote and path.

- [ ] **Step 2: Verify the build compiles**

Run: `cd Nimbus && xcodegen generate && xcodebuild -scheme Nimbus build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Nimbus/Nimbus/Views/Sidebar.swift Nimbus/Nimbus/Views/ContentView.swift
git commit -m "feat: display bookmarks in SwiftUI sidebar with reorder and remove"
```

---

### Task 9: "Add to Bookmarks" Context Menu (SwiftUI)

**Files:**
- Modify: `Nimbus/Nimbus/Views/Browser/FileContextMenu.swift` (add bookmark action)

- [ ] **Step 1: Add the bookmark action to the context menu**

In the `FileContextMenu` view, add the bookmark action for directories:

```swift
// Add environment access
@Environment(BookmarkStore.self) private var bookmarkStore

// Add to the FileAction enum
case bookmark

// Add menu item (only for directories):
if file.isDir {
    Divider()
    Button {
        onAction(.bookmark)
    } label: {
        Label("Add to Bookmarks", systemImage: "folder.badge.star")
    }
}
```

In the parent view that handles `FileAction`, handle `.bookmark`:

```swift
case .bookmark:
    let fullPath = currentPath.isEmpty ? file.name : "\(currentPath)/\(file.name)"
    bookmarkStore.addBookmark(remoteName: remote, path: fullPath, label: file.name)
```

- [ ] **Step 2: Verify the build compiles**

Run: `cd Nimbus && xcodegen generate && xcodebuild -scheme Nimbus build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Nimbus/Nimbus/Views/Browser/FileContextMenu.swift Nimbus/Nimbus/Views/Browser/BrowserView.swift
git commit -m "feat: add 'Add to Bookmarks' to SwiftUI file context menu"
```

---

## Feature 3: Download/Evict Management

### Task 10: File Provider Eviction Support

**Files:**
- Modify: `src-tauri/FileProviderExtension/FileProviderItem.swift` (add evictable capability)
- Modify: `Nimbus/FileProviderExtension/FileProviderItem.swift` (same change)

- [ ] **Step 1: Add evictable capability to FileProviderItem**

In both `FileProviderItem.swift` files, ensure the `capabilities` property includes `.evictable` for materialized items:

```swift
// In the capabilities computed property, add .evictable to the set:
var capabilities: NSFileProviderItemCapabilities {
    if isDirectory {
        return [.allowsReading, .allowsContentEnumerating]
    }
    // Add .allowsEvicting so the system can evict downloaded items
    return [.allowsReading, .allowsEvicting]
}
```

This enables the Finder "Remove Download" action on materialized files and allows the system to automatically evict files when disk space is low.

- [ ] **Step 2: Verify both extensions compile**

Run: `bash src-tauri/build-extension.sh` (Tauri extension)
Run: `cd Nimbus && xcodegen generate && xcodebuild -scheme Nimbus build` (SwiftUI extension)
Expected: Both builds succeed

- [ ] **Step 3: Commit**

```bash
git add src-tauri/FileProviderExtension/FileProviderItem.swift Nimbus/FileProviderExtension/FileProviderItem.swift
git commit -m "feat: enable evictable capability in File Provider items"
```

---

### Task 11: Cloud Status Column in Browser (Tauri Frontend)

**Files:**
- Create: `src/lib/rclone/file-provider-status.ts`
- Modify: `src/features/browser/components/file-list.tsx` (add cloud status column)
- Modify: `src/features/browser/components/file-context-menu.tsx` (add Download/Evict actions)

- [ ] **Step 1: Create the file provider status utility**

```typescript
// src/lib/rclone/file-provider-status.ts
import { invoke } from "@tauri-apps/api/core";

export type CloudStatus = "local" | "cloud" | "downloading" | "unknown";

export async function getCloudStatus(
  remoteName: string,
  path: string,
): Promise<CloudStatus> {
  try {
    return await invoke<CloudStatus>("get_cloud_status", {
      remoteName,
      path,
    });
  } catch {
    return "unknown";
  }
}

export async function evictFile(
  remoteName: string,
  path: string,
): Promise<void> {
  await invoke("evict_file", { remoteName, path });
}

export async function materializeFile(
  remoteName: string,
  path: string,
): Promise<void> {
  await invoke("materialize_file", { remoteName, path });
}
```

Note: The Tauri commands (`get_cloud_status`, `evict_file`, `materialize_file`) need corresponding Rust implementations that call into the File Provider framework via the `fp-domain-manager` CLI or NSFileProviderManager API. This is a placeholder that can be wired up when the Rust commands are implemented.

- [ ] **Step 2: Add cloud status indicator to the file list**

In `src/features/browser/components/file-list.tsx`, add a status column:

```tsx
// Add to imports
import { Cloud, HardDrive, CloudOff } from "lucide-react";

// Add a cloud status column header (in the table header row):
<th className="w-8 px-2">
  <Cloud className="h-4 w-4 text-muted-foreground" />
</th>

// Add status cell in each row (simplified — full implementation depends
// on whether status is fetched per-file or in batch):
<td className="w-8 px-2">
  <CloudStatusIcon status={file.cloudStatus ?? "unknown"} />
</td>

// Helper component at the bottom of the file:
function CloudStatusIcon({ status }: { status: string }) {
  switch (status) {
    case "local":
      return <HardDrive className="h-3 w-3 text-green-500" title="Downloaded" />;
    case "cloud":
      return <Cloud className="h-3 w-3 text-blue-500" title="Cloud only" />;
    default:
      return <CloudOff className="h-3 w-3 text-muted-foreground" title="Unknown" />;
  }
}
```

- [ ] **Step 3: Add Download/Evict context menu actions**

In `src/features/browser/components/file-context-menu.tsx`, add actions:

```tsx
// Add to imports
import { Download, CloudOff } from "lucide-react";

// Add menu items (after the bookmark section):
<ContextMenuSeparator />
<ContextMenuItem
  onClick={() => {
    // materializeFile(remote, filePath) — wired up when Rust commands exist
  }}
>
  <Download className="mr-2 h-4 w-4" />
  Download Now
</ContextMenuItem>
<ContextMenuItem
  onClick={() => {
    // evictFile(remote, filePath) — wired up when Rust commands exist
  }}
>
  <CloudOff className="mr-2 h-4 w-4" />
  Remove Local Copy
</ContextMenuItem>
```

- [ ] **Step 4: Verify the build compiles**

Run: `npm run build`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add src/lib/rclone/file-provider-status.ts src/features/browser/components/file-list.tsx src/features/browser/components/file-context-menu.tsx
git commit -m "feat: add cloud status column and download/evict actions to Tauri browser"
```

---

### Task 12: Cloud Status in Browser (SwiftUI)

**Files:**
- Modify: `Nimbus/Nimbus/Views/Browser/FileTable.swift` (add cloud status column)
- Modify: `Nimbus/Nimbus/Views/Browser/FileContextMenu.swift` (add Download/Evict actions)

- [ ] **Step 1: Add cloud status column to FileTable**

In `Nimbus/Nimbus/Views/Browser/FileTable.swift`, add a column:

```swift
// Add a new TableColumn for cloud status:
TableColumn("", value: \.path) { file in
    CloudStatusIcon(status: file.cloudStatus ?? .unknown)
}
.width(24)

// Add helper view:
struct CloudStatusIcon: View {
    let status: CloudStatus

    enum CloudStatus {
        case local, cloud, downloading, unknown
    }

    var body: some View {
        switch status {
        case .local:
            Image(systemName: "internaldrive")
                .foregroundStyle(.green)
                .help("Downloaded")
        case .cloud:
            Image(systemName: "cloud")
                .foregroundStyle(.blue)
                .help("Cloud only")
        case .downloading:
            ProgressView()
                .controlSize(.mini)
        case .unknown:
            Image(systemName: "cloud.slash")
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: Add Download/Evict context menu actions**

In `Nimbus/Nimbus/Views/Browser/FileContextMenu.swift`, add:

```swift
// Add to FileAction enum:
case download
case evict

// Add menu items:
Divider()
Button {
    onAction(.download)
} label: {
    Label("Download Now", systemImage: "arrow.down.circle")
}
Button {
    onAction(.evict)
} label: {
    Label("Remove Local Copy", systemImage: "cloud")
}
```

Handle the actions in BrowserView using `NSFileProviderManager`:

```swift
case .download:
    // NSFileProviderManager.default.getUserVisibleURL(for:) triggers materialization
    break
case .evict:
    // NSFileProviderManager.default.evictItem(identifier:) removes local copy
    break
```

- [ ] **Step 3: Verify the build compiles**

Run: `cd Nimbus && xcodegen generate && xcodebuild -scheme Nimbus build`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Nimbus/Nimbus/Views/Browser/FileTable.swift Nimbus/Nimbus/Views/Browser/FileContextMenu.swift Nimbus/Nimbus/Views/Browser/BrowserView.swift
git commit -m "feat: add cloud status column and download/evict to SwiftUI browser"
```

---

### Task 13: Storage Usage Summary in Settings

**Files:**
- Create: `src/features/settings/components/storage-usage.tsx` (Tauri)
- Create: `Nimbus/Nimbus/Views/Settings/StorageUsageView.swift` (SwiftUI)

- [ ] **Step 1: Create the Tauri storage usage component**

```tsx
// src/features/settings/components/storage-usage.tsx
import { useQuery } from "@tanstack/react-query";
import { invoke } from "@tauri-apps/api/core";

interface StorageInfo {
  totalCached: number;
  remotes: { name: string; cached: number }[];
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${(bytes / 1024 ** i).toFixed(1)} ${units[i]}`;
}

export function StorageUsage() {
  const { data } = useQuery<StorageInfo>({
    queryKey: ["storage-usage"],
    queryFn: () => invoke<StorageInfo>("get_storage_usage"),
    staleTime: 30_000,
  });

  if (!data) return null;

  return (
    <div className="space-y-2">
      <h3 className="text-sm font-medium">Local Cache</h3>
      <p className="text-sm text-muted-foreground">
        {formatBytes(data.totalCached)} cached locally across{" "}
        {data.remotes.length} remote{data.remotes.length !== 1 ? "s" : ""}
      </p>
      {data.remotes.map((r) => (
        <div
          key={r.name}
          className="flex items-center justify-between text-sm"
        >
          <span>{r.name}</span>
          <span className="text-muted-foreground">{formatBytes(r.cached)}</span>
        </div>
      ))}
    </div>
  );
}
```

- [ ] **Step 2: Create the SwiftUI storage usage view**

```swift
// Nimbus/Nimbus/Views/Settings/StorageUsageView.swift
import SwiftUI
import FileProvider

struct StorageUsageView: View {
    @State private var totalCached: Int64 = 0
    @State private var isLoading = true

    var body: some View {
        GroupBox("Local Cache") {
            if isLoading {
                ProgressView()
            } else {
                Text("\(ByteCountFormatter.string(fromByteCount: totalCached, countStyle: .file)) cached locally")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await calculateCacheSize()
        }
    }

    private func calculateCacheSize() async {
        defer { isLoading = false }

        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let cacheURL else { return }

        let nimbusCache = cacheURL.appendingPathComponent("app.casavargas.nimbus.FileProvider")
        guard let enumerator = FileManager.default.enumerator(
            at: nimbusCache,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        totalCached = total
    }
}
```

- [ ] **Step 3: Add StorageUsage to the Settings pages**

In the Tauri settings page, add `<StorageUsage />` in the appropriate section.
In the SwiftUI SettingsView, add `StorageUsageView()` as a section.

- [ ] **Step 4: Verify both builds compile**

Run: `npm run build` (Tauri)
Run: `cd Nimbus && xcodegen generate && xcodebuild -scheme Nimbus build` (SwiftUI)
Expected: Both succeed

- [ ] **Step 5: Commit**

```bash
git add src/features/settings/components/storage-usage.tsx Nimbus/Nimbus/Views/Settings/StorageUsageView.swift
git commit -m "feat: add storage usage summary to settings in both apps"
```

---

## Summary

| Task | Feature | Platform | Description |
|------|---------|----------|-------------|
| 1 | Config Import | Tauri | INI parser with tests |
| 2 | Config Import | Tauri | Import dialog + remotes page button |
| 3 | Config Import | SwiftUI | Parser + import sheet + remotes button |
| 4 | Bookmarks | Tauri | Zustand store with tests |
| 5 | Bookmarks | Tauri | Sidebar bookmarks section |
| 6 | Bookmarks | Tauri | Context menu "Add to Bookmarks" |
| 7 | Bookmarks | SwiftUI | BookmarkStore + app registration |
| 8 | Bookmarks | SwiftUI | Sidebar bookmarks section |
| 9 | Bookmarks | SwiftUI | Context menu "Add to Bookmarks" |
| 10 | Download/Evict | Both | File Provider evictable capability |
| 11 | Download/Evict | Tauri | Cloud status column + context menu |
| 12 | Download/Evict | SwiftUI | Cloud status column + context menu |
| 13 | Download/Evict | Both | Storage usage summary in settings |
