# Open File with System Default App

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Double-clicking a file in the browser downloads it to a temp directory and opens it with the system's default application.

**Architecture:** Add a `useOpenFile` hook that calls rclone `copyFile` to download the file to the OS temp directory, then calls `openPath` from `@tauri-apps/plugin-opener` to launch it. The existing `handleOpen` in `browser-page.tsx` gets extended to handle files (currently only handles directories).

**Tech Stack:** React, @tanstack/react-query, @tauri-apps/api/path (tempDir), @tauri-apps/plugin-opener (openPath), rclone copyFile

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `src/features/browser/hooks/use-file-operations.ts` | Add `useOpenFile` hook |
| Modify | `src/features/browser/pages/browser-page.tsx` | Wire `handleOpen` to open files |

---

### Task 1: Add `useOpenFile` hook

**Files:**
- Modify: `src/features/browser/hooks/use-file-operations.ts`

- [ ] **Step 1: Add the `useOpenFile` hook**

Add these imports at the top of the file:

```typescript
import { tempDir } from "@tauri-apps/api/path";
import { openPath } from "@tauri-apps/plugin-opener";
```

Add this hook after `useDownloadFile`:

```typescript
export function useOpenFile(remote: string) {
  return useMutation({
    mutationFn: async (remotePath: string) => {
      const tmp = await tempDir();
      const fileName = remotePath.split("/").pop() ?? "file";
      const localPath = `${tmp}${fileName}`;
      await operations.copyFile(`${remote}:`, remotePath, "/", localPath);
      await openPath(localPath);
    },
  });
}
```

- [ ] **Step 2: Verify it compiles**

Run: `npm run build` (or check Vite dev server output for errors)
Expected: No TypeScript errors

- [ ] **Step 3: Commit**

```bash
git add src/features/browser/hooks/use-file-operations.ts
git commit -m "feat: add useOpenFile hook to download and open files with system app"
```

---

### Task 2: Wire file opening into the browser page

**Files:**
- Modify: `src/features/browser/pages/browser-page.tsx`

- [ ] **Step 1: Import and instantiate the hook**

Add `useOpenFile` to the import from `../hooks/use-file-operations`:

```typescript
import {
  useCreateFolder,
  useDeleteItems,
  useOpenFile,
  useUploadFile,
} from "../hooks/use-file-operations";
```

Add after `const uploadFile = useUploadFile(...)`:

```typescript
const openFile = useOpenFile(remote ?? "");
```

- [ ] **Step 2: Extend `handleOpen` to handle files**

Replace the existing `handleOpen` callback:

```typescript
const handleOpen = useCallback(
  (item: FileItem) => {
    if (item.IsDir) {
      const newPath = path ? `${path}/${item.Name}` : item.Name;
      navigate(`/browser/${remote}/${newPath}`);
      clear();
      setFilter("");
    } else {
      const remotePath = path ? `${path}/${item.Name}` : item.Name;
      toast.promise(openFile.mutateAsync(remotePath), {
        loading: `Opening ${item.Name}...`,
        success: `Opened ${item.Name}`,
        error: (err) =>
          `Failed to open: ${err instanceof Error ? err.message : String(err)}`,
      });
    }
  },
  [path, remote, navigate, clear, openFile],
);
```

- [ ] **Step 3: Verify it compiles and works**

Run: `npm run build`
Expected: No errors. Double-clicking a file in the browser should download it and open with the default app.

- [ ] **Step 4: Commit**

```bash
git add src/features/browser/pages/browser-page.tsx
git commit -m "feat: double-click files to open with system default app"
```
