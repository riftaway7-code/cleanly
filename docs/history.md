# History and undo

cleanly stores operation history at `~/.cleanly/data/history.json`. The file is JSON and is written atomically.

Each run contains a timestamp, command label, and completed entries:

```json
[
  {
    "command": "clean",
    "time": "2026-08-03T12:00:00.000Z",
    "entries": [
      {
        "action": "move",
        "from": "/Users/you/Downloads/photo.jpg",
        "to": "/Users/you/Downloads/Images/photo.jpg"
      }
    ]
  }
]
```

Legacy Go history entries without `command` or `action` remain readable.

## Inspect history

```bash
cleanly history
cleanly history --limit 25
```

## Undo

```bash
cleanly undo
```

Before changing anything, undo verifies that every recoverable destination still exists and every original location is free. It then restores entries in reverse order. If a restore fails, already-restored entries are moved back so the run remains consistent.

Trash entries can be restored as long as their recorded Trash paths still exist. Entries with destination `PERMANENT` are skipped because their data no longer exists.

The number of retained runs is controlled by `history.limit`:

```bash
cleanly settings set history.limit 200
```
