# Contributing

cleanly is a macOS-only Swift Package.

```bash
swift build
swift test
swift build --configuration release
```

When changing file behavior, add a temporary-directory test that verifies both the mutation and its undo path. Keep output labeled, keep help synchronized with command behavior, and do not add emojis to user-facing text.
