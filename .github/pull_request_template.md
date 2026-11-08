## Summary

<!-- What changes and why. Link the spec in docs/superpowers/specs if there is one. -->

Closes #

## Test plan

<!-- How you verified it. Paste the commands you ran. -->

- [ ] `xcodebuild ... test CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` passes
- [ ] `swift test` in `RcloneKit/` passes (if RcloneKit changed)
- [ ] Verified in the running app (describe what you clicked)

## Screenshots

<!-- Required for anything visible. Before/after, light and dark if relevant. Delete this section for non-UI changes. -->

## Checklist

- [ ] Conventional commit messages, one logical change per commit
- [ ] No `Nimbus/Local.xcconfig`, `xcuserdata`, or regenerated `FileProviderExtension/Info.plist` in the diff
- [ ] Docs updated if behaviour or build steps changed
