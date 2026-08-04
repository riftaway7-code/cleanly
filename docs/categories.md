# Categories

cleanly uses file names and extensions to select destination folders. Matching is case-insensitive, and the longest matching extension wins, so `backup.tar.gz` is correctly classified as an archive.

Built-in destinations include Images, Audio, Video, Documents, Archives, Applications, Code, Data, Fonts, Design, Torrents, Books, and Disk Images. Unknown files use Other. Loose directories use Folders only when folder organization is enabled.

See every active extension:

```bash
cleanly settings category list
```

## Add or override a category

```bash
cleanly settings category add Screenshots png,jpg
```

Custom categories take precedence over built-ins, so PNG and JPEG files will now go to Screenshots.

```bash
cleanly settings category remove Screenshots
```

## Disable a built-in category

```bash
cleanly settings category disable Torrents
cleanly settings category enable Torrents
```

Extensions from disabled categories fall through to another matching category or Other.
