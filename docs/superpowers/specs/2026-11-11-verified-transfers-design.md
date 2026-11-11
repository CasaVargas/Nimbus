# Show "Verified" after transfers (#75)

Date: 2026-11-11
Status: proposed; label text awaiting Jon's approval

## Decision

Option (a) from the triage (Jon, 2026-11-11): infer verification from the
hash types the source and destination share, read once per remote from
`operations/fsinfo` (`Hashes`). No extra `operations/check` pass.

## Why the inference holds

rclone already verifies every copy, move and sync file: after writing an
object it compares size, then the first hash type both sides support
(`src.Hashes().Overlap(dst.Hashes()).GetOne()`), and fails the transfer with
`corrupted on transfer: <type> hashes differ …` on a mismatch. Nimbus never
passes `--ignore-checksum`. So:

- a **successful** job between remotes that share a hash type had its
  checksums compared;
- a **mismatch** never shows up as success; it is a failed job whose error
  says `hashes differ`;
- with **no shared hash type** rclone compared sizes only.

What the inference can't see: rclone skips the hash comparison for a single
object when either side returns an empty hash. The UI wording below accounts
for that instead of pretending it can't happen.

## States

`TransferVerification` on `Transfer` (persisted in history as an optional
field, so older history files and older Nimbus builds still read):

| State | When | Pill | Tint | Tooltip |
|---|---|---|---|---|
| `verified(hash)` | Job succeeded; src and dst share a hash type | **Verified** | OK (green) | "rclone compared <MD5> checksums on both sides. A file the service stores without a checksum is checked by size only." |
| `sizeOnly` | Job succeeded; no shared hash type | **Size checked** | secondary text | "These two locations have no checksum type in common, so rclone confirmed file sizes only." |
| `mismatch` | Job failed with `hashes differ` | **Checksum mismatch** | error (red) | "A copied file didn't match the original's checksum, so rclone removed the bad copy. Try the transfer again." + rclone's message |
| none (`nil`) | fsinfo failed, record predates this, or job failed/cancelled for another reason | existing **Done** / **Error** / **Cancelled** | unchanged | unchanged |

`<MD5>` is the shared hash's display name (MD5, SHA-1, SHA-256, QuickXorHash,
CRC32, …); unknown names are shown upper-cased.

## Edge cases that could be mislabeled

- **Crypt.** A crypt remote reports `Hashes: []` (measured on rclone 1.76).
  Uploads into crypt are actually checked (crypt hashes the encrypted stream
  against the wrapped backend), but fsinfo can't tell us, so crypt shows
  **Size checked**. This under-claims, which is the safe direction.
- **S3 multipart / ETag.** S3 reports `md5`. Objects rclone uploads in
  multipart carry the MD5 in metadata, so they verify. Objects whose only
  hash is a multipart ETag (uploaded by other tools, or with
  `--s3-disable-checksum`) return an empty hash, and rclone skips the
  comparison for that object while the job still shows **Verified**. The
  tooltip's second sentence names this case.
- **Google Docs and other exported formats.** Same as above: no hash for
  the object, size-only for that object.
- **Hasher / union / combine wrappers.** Whatever fsinfo reports is what
  rclone uses, so the inference follows rclone.
- **Local ↔ local.** Local supports every hash; shows **Verified**, which is
  correct (rclone compares MD5).

## How the UI avoids overclaiming

1. **Verified only on success.** Failed and cancelled transfers never get a
   positive verification state.
2. **No answer means no badge.** If fsinfo fails or times out, the row keeps
   the plain **Done** pill; the transfer itself is never failed or delayed
   by the lookup.
3. **The tooltip says what was compared,** naming the hash, and states the
   per-file size-only fallback, rather than promising "every byte checked".
4. **Size-only is neutral, not a warning.** The transfer succeeded; the pill
   just says what kind of check it got.
5. **Mismatch is detected from rclone's error text,** not inferred, so it
   can't fire on a success.

## Implementation

- RcloneKit: `RcloneClient.hashTypes(fs:)` decodes `Hashes` from
  `operations/fsinfo` (the decoder already exists for `features(fs:)`).
- `TransferVerification.infer(sourceHashes:destinationHashes:)` and
  `TransferVerification.mismatch(in:)`: pure, unit tested.
- `TransferStore.pollActiveJobs`: when a job finishes successfully, look up
  both remotes' hash types (cached per remote root for the session) and pass
  the result to `handleFinished`. A failed job is checked for the mismatch
  text.
- `TransferRow`: the three pills above, with `.help` tooltips.
