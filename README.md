# cleanly

cleanly is a macOS-only Swift command-line tool for organizing folders and safely finding files that are duplicated, old, large, or ready for the Trash.

Every mutation is previewed, labeled, confirmed, verified, and recorded. Recoverable operations can be reversed with `cleanly undo`.

## Requirements

- macOS 13 or newer
- Homebrew for the recommended installation, or Swift 5.9 or newer for a source build

## Install

```bash
brew install thecatthatflies/tap/cleanly
```

For a source installation:

```bash
git clone https://github.com/thecatthatflies/cleanly.git
cd cleanly
./scripts/install.sh
```

## Organize a folder

Start with a read-only preview:

```bash
cleanly preview ~/Downloads
```

Apply the labeled plan after confirmation:

```bash
cleanly clean ~/Downloads
```

The legacy path-first form still works:

```bash
cleanly ~/Downloads -c Images,Documents
```

cleanly recognizes compound extensions, preserves macOS packages, skips symlinks and hidden entries by default, avoids its own category folders, and never overwrites an existing item. Unrecognized files go to `Other`.

## More cleanup tools

These commands are read-only unless `--trash` is added:

```bash
cleanly duplicates ~/Downloads
cleanly empty ~/Downloads
cleanly large ~/Downloads --size 1000
cleanly old ~/Downloads --days 180
```

After reviewing a report, move its results to the macOS Trash:

```bash
cleanly duplicates ~/Downloads --trash
cleanly empty ~/Downloads --trash
cleanly large ~/Downloads --size 1000 --trash
cleanly old ~/Downloads --days 180 --trash
```

Remove specific file types or categories:

```bash
cleanly remove ~/Downloads --extension dmg,pkg
cleanly remove ~/Downloads --category Archives
```

Permanent deletion requires `--permanent` and a typed `DELETE` confirmation. For automation it requires all three flags: `--permanent --yes --confirm-permanent DELETE`.

## Undo and history

```bash
cleanly history
cleanly undo
```

Moves and Trash operations are recoverable while the recorded destination still exists. Permanent deletion is recorded but cannot be restored.

## Settings

```bash
cleanly settings show
cleanly settings set confirmations strict
cleanly settings set collisions skip
cleanly settings set clean.include-hidden true
cleanly settings set clean.organize-folders true
cleanly settings set tips.enabled false
cleanly settings category add Screenshots png,jpg
```

Settings live in `~/.cleanly/settings.json`. History lives in `~/.cleanly/data/history.json`. Set `CLEANLY_HOME` to use a different state directory.

## Built-in categories

Images, Audio, Video, Documents, Archives, Applications, Code, Data, Fonts, Design, Torrents, Books, Disk Images, Folders, and Other.

Use `cleanly settings category list` for the exact extension rules and `cleanly settings category add` to override or extend them.

## Safety model

- Protected roots such as `/`, the home directory, `/System`, `/Library`, and `/Applications` are refused.
- Cleaning shows every destination and asks before moving anything.
- Trash is the default for removal and maintenance commands.
- Existing destinations are renamed with a numbered suffix or skipped, according to settings.
- Completed changes are verified before being recorded.
- Recoverable changes roll back if history cannot be saved.
- Hidden items, symlinks, folders, and macOS packages receive conservative handling.

Run `cleanly help` or `cleanly help COMMAND` for the complete interface.

## Development

```bash
swift build
swift test
swift build --configuration release
```

## License

MIT
