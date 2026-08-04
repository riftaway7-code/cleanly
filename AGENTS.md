# AGENTS.md

Instructions for agents working on cleanly.

## Project

cleanly is a macOS-only Swift CLI that organizes folders, reports maintenance opportunities, moves unwanted items to the macOS Trash, records every completed mutation, and supports undo.

## Structure

- `Package.swift` defines the Swift package and macOS deployment target.
- `Sources/CleanlyCore/` contains parsing, settings, categories, scanning, history, and file operations.
- `Sources/CleanlyCLI/main.swift` is the executable entry point.
- `Tests/CleanlyCoreTests/` contains Swift Testing coverage.
- `scripts/` contains manual installation and safe uninstallation.
- `docs/` contains user documentation.

## Required behavior

1. Build for macOS only and use Foundation APIs; do not add cross-platform branches.
2. Never overwrite a destination. Respect the configured collision strategy.
3. Skip symlinks and preserve macOS package directories.
4. Use the macOS Trash unless permanent deletion is explicitly requested and confirmed with `DELETE`.
5. Record only completed mutations. Roll back recoverable mutations if history cannot be written.
6. Preserve legacy history decoding. `PERMANENT` entries cannot be restored.
7. Unknown extensions belong to `Other`.
8. Every successful clean prints `undo that movement using \`cleanly undo\`` and then a tip when tips are enabled.
9. User-facing output must be labeled and must not contain emojis.
10. Keep `cleanly help`, `cleanly --help`, and command-specific help synchronized with behavior.

## Verification

```bash
swift format lint --recursive Package.swift Sources Tests
swift test
swift build -c release
```

Manual mutation tests must use a temporary directory and an isolated `CLEANLY_HOME`.
