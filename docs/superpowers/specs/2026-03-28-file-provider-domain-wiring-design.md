# File Provider Domain Registration Wiring — Design Spec

**Goal:** Wire the mount UI to File Provider domain registration so adding/removing a fileprovider mount automatically registers/unregisters the domain in Finder.

**Parent initiative:** Nimbus premium v1 launch — File Provider sub-project 2 of 6

---

## Scope

### In scope
1. Call `fpAddDomain` when user adds a mount with `backend: "fileprovider"`
2. Call `fpRemoveDomain` when user removes a fileprovider mount
3. Hide Mount/Unmount button for fileprovider mounts (Finder handles access)
4. Hide Auto checkbox for fileprovider mounts (domains are always active)
5. Rename mount store persist key from `streamcloned-mounts` to `nimbus-mounts`

### Out of scope
- Domain status indicators (sub-project 4: mount lifecycle UI)
- Error recovery / stale domain cleanup (sub-project 5)
- Change tracking (sub-project 3)

---

## Behavior

### Add flow
1. User opens Add Mount dialog, selects a remote, enters display name
2. User clicks "Add"
3. `addConfig()` saves the mount config to the store
4. If `backend === "fileprovider"`: call `fpAddDomain(remoteName, displayName)`
5. On success: toast "Registered {displayName} in Finder"
6. On failure: toast error, config is still saved (user can retry later)

### Remove flow
1. User clicks "Remove" on a fileprovider mount item
2. If `backend === "fileprovider"`: call `fpRemoveDomain(remoteName)`
3. `removeConfig()` removes the mount config from the store regardless of fpRemoveDomain result
4. On success: toast "Removed {displayName} from Finder"
5. On failure: toast error (stale domain cleaned up on next app launch)

### UI changes for fileprovider mounts
- Mount/Unmount button: hidden (Finder drives access on demand, no mount toggle)
- Auto checkbox: hidden (domains are always registered)
- Status indicator: always shows green when config exists (domain is registered)
- Remove button: always enabled (no "active mount" concept to block removal)

---

## File Changes

| Action | File | Change |
|--------|------|--------|
| Modify | `src/features/mount/components/add-mount-dialog.tsx` | Call `fpAddDomain` in `handleAdd` for fileprovider backend |
| Modify | `src/features/mount/components/mount-item.tsx` | Call `fpRemoveDomain` on remove, hide mount/auto controls for fileprovider |
| Modify | `src/stores/mount-store.ts` | Rename persist key to `nimbus-mounts` |
