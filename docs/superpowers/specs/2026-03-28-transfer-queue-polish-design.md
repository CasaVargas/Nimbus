# Transfer Queue Polish — Design Spec

**Goal:** Add per-file progress bars, overall job progress, ETA, and per-transfer speed to the transfer queue UI.

**Parent initiative:** Nimbus premium v1 launch (sub-project 2 of 7)

---

## Scope

### In scope
1. Overall job progress bar on each active transfer (bytes / totalBytes)
2. Per-file progress list under each active transfer (filename, progress bar, speed, ETA)
3. Elapsed time and ETA on each active transfer header
4. Per-transfer speed display
5. Collapsible per-file detail section (expanded by default for active, collapsed for completed)

### Out of scope
- Transfer queue reordering / priority
- Pause/resume individual transfers
- Notification on transfer complete (later sub-project)

---

## Data Flow

Rclone's `core/stats` endpoint returns a `StatsResponse` with:
- `speed`, `bytes`, `totalBytes`, `elapsedTime` — overall stats
- `transferring[]` — array of `TransferringFile` with `name`, `size`, `bytes`, `percentage`, `speed`, `speedAvg`, `eta`
- `transfers`, `totalTransfers` — file count progress

The stats can be filtered by group (job ID) via the `group` parameter. Each copy/sync job creates a group like `job/N`. The `useTransferStats` hook needs to query per-job stats by passing the group.

---

## UI Changes

### Transfer Item (active)
```
[⟳] Copy  gdrive:photos → local:/backup/photos
    ████████████░░░░░░░░  62% · 1.2 GB / 1.9 GB · 45 MB/s · ETA 15s

    vacation.jpg       ████████████████████  100%
    sunset.mp4         ████████░░░░░░░░░░░░   42%  12 MB/s  ETA 8s
    portrait.png       ██░░░░░░░░░░░░░░░░░░   10%   5 MB/s  ETA 22s
```

### Transfer Item (completed)
```
[✓] Copy  gdrive:photos → local:/backup/photos
    1.9 GB · 47 files · 2m 14s
```

### Transfer Item (failed)
```
[✗] Sync  onedrive:docs → b2:backup/docs
    Error: authentication failed
    892 MB / 2.1 GB · 23 files · 1m 45s
```

---

## File Changes

| Action | File | Change |
|--------|------|--------|
| Modify | `src/features/transfers/hooks/use-transfers.ts` | Add per-job stats query with group filter |
| Modify | `src/features/transfers/components/transfer-item.tsx` | Add progress bar, per-file list, ETA, speed, elapsed |
| Modify | `src/features/transfers/pages/transfers-page.tsx` | Pass per-job stats to transfer items |

---

## Component Details

### Progress bar
Use a simple div-based progress bar (no library needed). Tailwind classes: outer `h-1.5 rounded-full bg-muted`, inner `h-full rounded-full bg-primary transition-all`.

### Per-file list
Render `stats.transferring[]` as a compact list under the main progress bar. Each row: filename (truncated), mini progress bar, speed, ETA. Only shown for active transfers.

### Formatting helpers
- `formatBytes(n)` — already exists in file-list.tsx as `formatSize`, extract to shared utility or duplicate
- `formatDuration(seconds)` — new helper: `1m 23s`, `2h 5m`, etc.
- `formatSpeed(bytesPerSec)` — `45 MB/s`, `1.2 GB/s`, etc.

### Stats grouping
Rclone groups stats by `job/N` where N is the job ID. Call `getStats("job/" + jobId)` to get per-transfer stats. The current `useTransferStats` calls `getStats()` with no group (global stats). We need per-job queries.
