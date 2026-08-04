# Safety

cleanly is designed around visible plans and recoverable operations.

## Before a change

- Cleaning and removal print every selected item.
- Maintenance commands are reports until `--trash` is explicit.
- Protected root directories are refused.
- Standard confirmation defaults to no; strict mode requires typed action words.
- Permanent deletion always requires `DELETE`.

## During a change

- Symlinks are skipped.
- macOS package directories are preserved.
- Destinations are never overwritten.
- Every move is verified before it is recorded.
- Only completed operations enter history.

## After a change

- Recoverable moves roll back if history cannot be saved.
- `cleanly undo` preflights the entire run before restoring it.
- Trash operations use the native macOS Trash API.
- Permanent deletion is labeled as not recoverable.

For unattended recoverable operations, use `--yes`. It does not authorize permanent deletion on its own.
