# Command reference

## Organize

```bash
cleanly preview [PATH] [OPTIONS]
cleanly clean [PATH] [OPTIONS]
cleanly [PATH] [OPTIONS]
```

Options:

- `-c, --category LIST` limits sorting to named categories.
- `--include-hidden` includes hidden entries for one run.
- `--exclude-hidden` excludes hidden entries for one run.
- `--folders` organizes loose directories under `Folders`.
- `--no-folders` leaves loose directories untouched.
- `-y, --yes` accepts the recoverable move confirmation.

## Maintain

```bash
cleanly duplicates [PATH] [--trash] [--include-hidden] [--yes]
cleanly empty [PATH] [--trash] [--include-hidden] [--yes]
cleanly large [PATH] [--size MB] [--trash] [--include-hidden] [--yes]
cleanly old [PATH] [--days DAYS] [--trash] [--include-hidden] [--yes]
```

Without `--trash`, every maintenance command is read-only.

## Remove

```bash
cleanly remove [PATH] --extension LIST
cleanly remove [PATH] --category LIST
```

Add `--permanent` only when Trash recovery is intentionally unwanted.

## Recover and inspect

```bash
cleanly undo
cleanly history [--limit NUMBER]
```

## Configure

```bash
cleanly settings show
cleanly settings get KEY
cleanly settings set KEY VALUE
cleanly settings category list
cleanly settings category add NAME EXTENSION...
cleanly settings reset
```

## Utility

```bash
cleanly update
cleanly version
cleanly --version
cleanly -v
cleanly help [COMMAND]
cleanly COMMAND --help
```

Successful commands return status `0`, cancelled confirmations return `2`, and errors or partial failures return `1`.
