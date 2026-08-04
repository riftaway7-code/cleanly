# Settings

cleanly stores human-readable JSON settings at `~/.cleanly/settings.json`. If a compatible legacy `~/.cleanly/config.json` exists and settings do not, it is migrated automatically without deleting the original.

```bash
cleanly settings show
cleanly settings path
cleanly settings get tips.enabled
cleanly settings set tips.enabled false
cleanly settings tips off
```

Available keys:

| Key | Values | Default |
| --- | --- | --- |
| `tips.enabled` | `true`, `false` | `true` |
| `confirmations` | `standard`, `strict` | `standard` |
| `clean.include-hidden` | `true`, `false` | `false` |
| `clean.organize-folders` | `true`, `false` | `false` |
| `collisions` | `rename`, `skip` | `rename` |
| `thresholds.old-days` | positive integer | `90` |
| `thresholds.large-mb` | positive integer | `500` |
| `history.limit` | positive integer | `100` |
| `default.path` | existing directory | `.` |
| `exclusions` | comma-separated names | `.git,.cleanly` |
| `disabled-categories` | comma-separated names | empty |

Resetting settings and custom categories requires confirmation:

```bash
cleanly settings reset
```
