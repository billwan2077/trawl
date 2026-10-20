# Trawl — file search for Mac (Apple Silicon) — Spec

A personal-use file search app in the spirit of DEVONtechnologies' EasyFind: it searches
file names and file contents directly on disk, with no index and no Spotlight dependency.

## Goals

- Native arm64 app: Swift + SwiftUI, macOS 14 or later.
- Search names, contents, or both, across one or more chosen folders.
- Boolean queries with wildcards, plus an optional regular-expression mode.
- Results stream in while the search runs, and the search can be stopped at any time.
- Small: no third-party dependencies.

Out of scope for v1: indexing, Spotlight integration, Developer ID signing/notarization,
search inside PDFs/Office documents (only plain-text-decodable files are content-searched).

## Query syntax (Boolean mode, the default)

| Input               | Meaning                                              |
|---------------------|------------------------------------------------------|
| `report budget`     | both terms (implicit AND)                            |
| `report AND budget` | same; `&` also works                                 |
| `report OR memo`    | either term; `|` also works                          |
| `NOT draft`, `-draft`, `!draft` | term must not match                      |
| `"annual report"`   | exact phrase                                         |
| `( a OR b ) c`      | grouping                                             |
| `*.pdf`, `img_??.png` | wildcards: `*` any run of characters, `?` one char |

Precedence: NOT > AND > OR. Operators are recognised only in upper case, so
`and`/`or`/`not` in lower case are ordinary words.

Matching rules:

- A plain term or phrase matches as a substring (case-insensitive unless "Case sensitive"
  is on).
- A term containing `*` or `?` matched against a **file name** must match the whole name
  (`*.pdf` = names ending in `.pdf`, `report*` = names starting with `report`). Against
  **contents** it matches anywhere in the text.

Regex mode: the whole query is one ICU regular expression, matched anywhere.

## Search options

- Target: Names / Contents / Names & Contents (a file matches if either matches).
- Folders: a list of roots (default: the home folder). Add with an Open panel or by dragging
  folders onto the list.
- Case sensitive (off by default).
- Regular expression mode (off by default).
- Include hidden files (off by default).
- Search inside packages/bundles such as `.app` (off by default).
- Include folders in results (on by default, name matches only).
- File types (toolbar "Types" menu): All Files, the Common Files preset (Word, Excel,
  PowerPoint, PDF, Text, Log, Images, Video), or any mix of Word, Excel, PowerPoint, PDF,
  Text, Log, Images, Video, Audio, Archives. Types are decided by file extension. While a
  type filter is set, only files of those types are checked and folders are not returned.
- Content search skips files larger than a limit (default 50 MB) and files that look
  binary (a NUL byte in the first 8 KB). Text is decoded as UTF-8, then UTF-16 if it has a
  BOM, falling back to ISO Latin-1.

## Interface

- Toolbar: search field (Return starts the search), target picker, Search/Stop button,
  options menu.
- Sidebar: folder list with add/remove.
- Filter bar above the results: one button per type present in the results (system icon,
  e.g. the Word/Excel/PowerPoint document icons, plus a count). Clicking a type shows only
  that type; clicking more types combines them; "All" clears the filter. It filters the
  current results without searching again, and resets when a new search starts.
- Results table: Name, Folder, Size, Modified, Kind; sortable by column.
- Row actions: double-click opens; context menu: Open, Reveal in Finder, Copy Path,
  Move to Trash (confirmation dialog); rows can be dragged to other apps.
- Status bar: number of results, files scanned, elapsed time, current folder while running.

## Architecture

- `TrawlCore` (library, unit-tested): `QueryParser` → `QueryExpr` tree; `Matcher`
  evaluates an expression against a name or text; `FileSearcher` walks folders with
  `FileManager.enumerator` and checks contents in parallel (bounded task group), emitting
  results through an `AsyncStream`.
- `Trawl` (executable): SwiftUI app; `SearchModel` (`@MainActor`, `ObservableObject`)
  owns the running task, batches results to the UI.
- `scripts/make-icon.sh`: draws the icon (`scripts/draw-icon.swift`) and writes
  `Assets/AppIcon.icns`.
- `scripts/build-app.sh`: release build, wraps the binary in `Trawl.app` with an
  `Info.plist`, ad-hoc signs it.

## Permissions

Unindexed search reads files directly, so macOS privacy protection applies: Desktop,
Documents, Downloads, and removable volumes trigger one-time prompts, and folders such as
Mail or Messages are only readable after granting Trawl **Full Disk Access** in
System Settings → Privacy & Security. Unreadable folders are skipped silently.
