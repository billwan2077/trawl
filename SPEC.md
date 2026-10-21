# Trawl — file search for Mac (Apple Silicon) — Spec

A personal-use file search app in the spirit of DEVONtechnologies' EasyFind: it searches
file names and file contents directly on disk, and also asks Spotlight when its index is
available, merging both into one result list.

## Goals

- Native arm64 app: Swift + SwiftUI, macOS 14 or later.
- Search names, contents, or both, across one or more chosen folders.
- Boolean queries with wildcards, plus an optional regular-expression mode.
- Results stream in while the search runs, and the search can be stopped at any time.
- Small: no third-party dependencies.

Out of scope for v1: a Trawl-owned index, Developer ID signing/notarization. Text inside
PDF/Office documents is found only through Spotlight (the folder scan reads plain text only).

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
  PowerPoint, PDF, Text, Markdown, Log, Images, Video), or any mix of Word, Excel,
  PowerPoint, PDF, Text, Markdown, HTML, Log, Images, Video, Audio, Archives. Types are decided by file extension. While a
  type filter is set, only files of those types are checked and folders are not returned.
- Search engine (Options menu): Spotlight + Folder Scan (default), Folder Scan Only, or
  Spotlight Only. See "Spotlight" below.
- Content search skips files larger than a limit (default 50 MB) and files that look
  binary (a NUL byte in the first 8 KB). Text is decoded as UTF-8, then UTF-16 if it has a
  BOM, falling back to ISO Latin-1.

## Interface

- Toolbar: search field (Return starts the search), target picker, Search/Stop button,
  options menu.
- Sidebar: "All Folders" plus the folder list, with add/remove. Selecting a folder shows
  only results inside it (type counts follow), and the next search covers only that folder;
  "All Folders" shows and searches everything again.
- Filter bar above the results: one button per type present in the results (system icon,
  e.g. the Word/Excel/PowerPoint document icons, plus a count). Clicking a type shows only
  that type; clicking more types combines them; "All" clears the filter. It filters the
  current results without searching again, and resets when a new search starts.
- Results table: Name, Folder, Size, Modified, Kind, Found By (Spotlight and/or folder scan
  icons); sortable by the first five columns.
- Row actions: double-click opens; context menu: Open, Reveal in Finder, Copy Path,
  Move to Trash (confirmation dialog); rows can be dragged to other apps.
- Status bar: number of results, results per engine (with "…" while an engine runs), files
  scanned, elapsed time, current folder while running, and why Spotlight was skipped. When
  macOS refused access to folders, an orange "N folders couldn't be read" button opens a list
  of them and a shortcut to Privacy & Security settings.

## Spotlight

Each search runs Spotlight (`NSMetadataQuery`, scoped to the chosen folders) and the folder
scan at the same time. Spotlight answers in a fraction of a second from its index; the scan
then adds what the index misses (hidden or unindexed folders, files not yet indexed).
Results are merged by path, and each records which engines found it.

Translation (`SpotlightQueryBuilder`):

| Trawl                    | Spotlight query                                      |
|--------------------------|------------------------------------------------------|
| name term `report`       | `kMDItemFSName == "*report*"c`                       |
| name wildcard `*.pdf`    | `kMDItemFSName == "*.pdf"c`                          |
| content term `budget`    | `kMDItemTextContent == "budget*"c` (word prefix)     |
| content phrase `"a b"`   | `kMDItemTextContent == "a b"c`                       |
| AND / OR, parentheses    | `&&` / `||`                                          |
| type filter              | `&& (kMDItemFSName == "*.docx"c || ...)`             |
| Names & Contents         | `(names query) || (contents query)`                  |

The `c` modifier is dropped when Case sensitive is on.

NOT is never sent to Spotlight: NOT branches are dropped, which only widens what Spotlight
returns. Every Spotlight hit is then checked before it is shown: it must still exist, lie
inside a chosen folder, pass the type/hidden/package/folder options, and, for names, match
the query exactly with `Matcher` (so NOT still applies). Content-only hits are kept only
when the query has no NOT, because text inside Office/PDF files cannot be re-checked.

Before Spotlight is queried, Trawl reads the macOS-protected folders (Desktop, Documents,
Downloads) that overlap the search folders. Spotlight silently hides results in protected
folders an app may not read, so this both triggers the macOS permission prompt on first use
and lets the status bar list the folders that stay blocked, in every engine mode.

Spotlight is skipped, with a note in the status bar, for regex queries, queries with no
positive term (e.g. `NOT draft`), and content searches containing NOT. With indexing off,
Spotlight simply returns nothing and the folder scan still runs.

## Architecture

- `TrawlCore` (library, unit-tested):
  - `QueryParser` → `QueryExpr` tree; `Matcher` evaluates an expression against a name or text.
  - `FileSearcher` walks folders with `FileManager.enumerator` and checks contents in
    parallel (bounded task group), emitting results through an `AsyncStream`.
  - `SpotlightQueryBuilder` turns a query and options into a Spotlight query string, or a
    reason to skip Spotlight; `SpotlightSearcher` runs it with `NSMetadataQuery` on the main
    run loop and streams matching paths.
  - `HybridSearcher` runs both engines, verifies Spotlight hits, merges by path and emits
    `SearchEvent`s: `results`, `sourcesAdded`, `progress`, `engineFinished`, `notice`,
    `finished`.
- `Trawl` (executable): SwiftUI app; `SearchModel` (`@MainActor`, `ObservableObject`)
  owns the running task, keeps results, which engines found each one, and per-engine
  counts, and batches results to the UI.
- `scripts/make-icon.sh`: draws the icon (`scripts/draw-icon.swift`) and writes
  `Assets/AppIcon.icns`.
- `scripts/build-app.sh`: release build, wraps the binary in `Trawl.app` with an
  `Info.plist`, and signs it with the first "Apple Development" identity in the keychain
  (ad-hoc if none; override with `TRAWL_SIGN_IDENTITY`). A stable identity keeps macOS
  privacy grants across rebuilds; an ad-hoc signature changes with every build.

## Permissions

Unindexed search reads files directly, so macOS privacy protection applies: Desktop,
Documents, Downloads, and removable volumes trigger one-time prompts, and folders such as
Mail or Messages are only readable after granting Trawl **Full Disk Access** in
System Settings → Privacy & Security. Spotlight also hides results in folders Trawl may not
read. Unreadable folders are skipped and listed in the status bar.
