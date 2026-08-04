# Maintenance tools

All maintenance commands scan recursively and report results without changing files. Add `--trash` only after reviewing the report.

## Exact duplicates

```bash
cleanly duplicates ~/Downloads
cleanly duplicates ~/Downloads --trash
```

Files are grouped by size and then compared with streaming SHA-256 hashes. cleanly keeps the oldest file in each group, breaking timestamp ties by path, and selects the other exact copies for Trash.

## Empty folders

```bash
cleanly empty ~/Downloads
cleanly empty ~/Downloads --trash
```

Symlinks and macOS package contents are not traversed.

## Large files

```bash
cleanly large ~/Downloads --size 500
cleanly large ~/Downloads --size 500 --trash
```

The default comes from `thresholds.large-mb`.

## Old files

```bash
cleanly old ~/Downloads --days 90
cleanly old ~/Downloads --days 90 --trash
```

Age is based on the content modification date. The default comes from `thresholds.old-days`.
