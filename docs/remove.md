# Remove files

`cleanly remove` selects immediate files by extension, category, or both. It prints every match before asking for confirmation.

```bash
cleanly remove ~/Downloads --extension png,jpeg,gif
cleanly remove ~/Downloads --category Images,Archives
```

`-f` is the short form of `--extension`; `-c` is the short form of `--category`.

## Trash by default

Selected files go through the native macOS Trash API and are recorded for `cleanly undo`.

```bash
cleanly remove ~/Downloads -f dmg,pkg
cleanly undo
```

## Permanent deletion

```bash
cleanly remove ~/Downloads --extension tmp --permanent
```

The command requires the exact word `DELETE`. `--yes` alone cannot bypass this protection. A noninteractive permanent deletion must specify:

```bash
cleanly remove ~/Downloads --extension tmp --permanent --yes --confirm-permanent DELETE
```

Permanently deleted files cannot be restored. They are still recorded so history accurately describes what happened.
