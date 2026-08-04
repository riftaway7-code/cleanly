# Getting started

## Install on macOS

```bash
brew install thecatthatflies/tap/cleanly
```

cleanly requires macOS 13 or newer. It is implemented entirely in Swift.

## Preview your first clean

```bash
cleanly preview ~/Downloads
```

The preview labels the directory, operating mode, number of planned moves, and destination for every item. It does not change files.

## Apply the plan

```bash
cleanly clean ~/Downloads
```

Review the plan, then answer the confirmation prompt. Use `cleanly settings set confirmations strict` if you prefer typed confirmations.

## Reverse the movement

```bash
cleanly undo
```

Only the latest recorded operation is reversed at a time.

## Learn the rest

```bash
cleanly help
cleanly help clean
cleanly help settings
```
