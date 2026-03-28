# File Browser Completions — Design Spec

**Goal:** Make the Nimbus file browser feel complete and premium by adding download, rename, open-with-system-app, context menus, and hover actions.

**Parent initiative:** Nimbus premium v1 launch (sub-project 1 of 7)

---

## Scope

### In scope
1. Right-click context menu (Open, Download, Rename, Delete)
2. Hover action buttons on file rows — both list and grid views
3. Download to ~/Downloads with toast notification
4. Inline rename (click filename → editable field → Enter to confirm)
5. Fix "open with system app" bug (copyFile "is a directory" error)
6. Multi-select context menu (right-click with selection → bulk Download, Delete)

### Out of scope
- Drag & drop (sub-project later)
- Cross-remote search (sub-project later)
- Keyboard shortcuts (sub-project later)
- Configurable download directory (v1.1 settings addition)

---

## Component Architecture

### New files

- **`src/features/browser/components/file-context-menu.tsx`** — Right-click menu using the existing `DropdownMenu` component from `@base-ui/react`. Renders different items based on whether the target is a file, folder, or multi-selection.

- **`src/features/browser/components/file-actions.tsx`** — Hover action buttons (Open, Download icons). Renders as a small icon row on the far right of list rows, or as an overlay bar at the bottom of grid cards. Fades in on hover (~150ms transition).

- **`src/features/browser/components/inline-rename.tsx`** — Editable filename field. Renders as a controlled `<input>` pre-filled with the current name, fully selected on mount. Enter confirms, Escape cancels. Empty or unchanged name cancels silently.

### Modified files

- **`src/features/browser/components/file-list.tsx`** — Wrap rows with context menu trigger, add hover actions on the right, support inline rename mode per-row.

- **`src/features/browser/components/file-grid.tsx`** — Same treatment: context menu on cards, hover action overlay, inline rename support.

- **`src/features/browser/hooks/use-file-operations.ts`** — Add `useRenameFile` hook. Fix `useOpenFile` bug (validate source is a file, use `join()` for temp path).

- **`src/features/browser/pages/browser-page.tsx`** — Wire up `handleDownload`, `handleRename` handlers. Pass context menu and hover action callbacks to FileList/FileGrid.

---

## Interaction Details

### Context menu (right-click)

| Target | Menu items |
|--------|-----------|
| File | Open, Download, Rename, —, Delete (red) |
| Folder | Open, Rename, —, Delete (red) |
| Multi-selection | Download All, —, Delete All (red) |

Uses the existing `DropdownMenu` primitive from `@base-ui/react` (already in codebase at `src/components/ui/dropdown-menu.tsx`, currently unused).

### Hover actions

- **List view:** Icons appear on the far right of the row on hover. Two icons for files: Open (external link arrow), Download (down arrow). One icon for folders: Open only.
- **Grid view:** Small overlay bar appears at the bottom of the card on hover, same icons.
- **Transition:** ~150ms fade-in/out.
- **No hover actions in multi-select mode** — context menu handles bulk actions.

### Inline rename

- **Trigger:** Select "Rename" from context menu. (Double-click still opens files/folders — not used for rename to avoid conflict.)
- **Behavior:** Filename text becomes an `<input>`, pre-filled and fully selected. Enter confirms, Escape cancels. Empty or unchanged name cancels silently.
- **Implementation:** Uses rclone's `moveFile` operation (already in `operations.ts`) with same source and dest remote, different filename.
- **On success:** Invalidate file list query, show success toast.

### Download

- **Destination:** `~/Downloads` (hardcoded for now, configurable dir is a v1.1 settings item).
- **Hook:** Uses existing `useDownloadFile` hook (already coded in `use-file-operations.ts`, not exposed in UI).
- **Feedback:** `toast.promise` — "Downloading {filename}..." → "Downloaded {filename} to ~/Downloads".
- **Overwrites:** If the file already exists at the destination, rclone overwrites (standard rclone behavior).
- **Bulk download:** Downloads files sequentially via `Promise.all`. Folders are skipped (download is file-only for now).

### Open file fix

- The current `useOpenFile` hook fails with "is a directory not a file" from rclone.
- Fix: use `join()` from `@tauri-apps/api/path` for temp path construction (partially applied). Add a guard that skips the operation if the item is a directory (belt-and-suspenders with the `IsDir` / `MimeType` check already in `handleOpen`).
- The `useOpenFile` flow: `tempDir()` → `join(tmp, fileName)` → `copyFile` to temp → `openPath` to launch with system default app.

---

## Data Flow

```
User action (right-click / hover click)
  → browser-page.tsx handler (handleOpen / handleDownload / handleRename)
    → use-file-operations.ts hook (mutation)
      → rclone operations.ts (HTTP call to rclone RC API)
        → toast feedback (loading / success / error)
        → invalidate file list query on success
```

All actions are optimistic-feedback (toast.promise) with query invalidation on success. No optimistic UI updates to the file list — wait for the refetch.
