## 0.2.1 (2026-11-09)

- Read status in the browser: ● finished, ◐ started (reading or listening), ○ not started; series show how many books are read (ideas from paucapo's fork)
- Podcast libraries are hidden
- Progress sync uses KOReader's own reading percentage and jumps by percentage, which is more accurate for EPUBs
- In the file browser, the menu says to open a book instead of only greying out the sync items
- Removed the deprecated `name` field from _meta.lua
- Added tests (`sh tests/run.sh`, needs luajit), including a check that no `for _,` loop hides gettext

## 0.2.0 (2026-11-09, combined build)

- Back navigation: X, the Back key, swipe down and a back arrow step up one level (book page, search, series, library); the plugin only closes from the top level
- Progress sync from PR #16, with fixes: never sends isFinished = false (which reset finished books and audiobook positions), no network calls during page turns, automatic syncs only when online with a back-off after failures, push on sleep, manual actions turn Wi-Fi on
- Series grouping from PR #20, reworked: series listed alphabetically, books in numeric order, books in several series grouped under the first
- Book rows show "title by author" (PR #9)
- The plugin loads and opens its settings when audiobookshelf_config.lua is missing
- All settings share one store, so saving one setting can no longer overwrite another
- Settings changed in the plugin take effect immediately; trailing slashes in the server URL are ignored

## 0.1.3 (2025-12-01)

Merged a PR with a bunch of error handling (#12)

## 0.1.2 (2025-04-26)

Fix issue #6 where if a book has an unsafe character in the filename.  This sanitizes the name using util.getSafeFilename

## 0.1.1 (2025-04-25)

Add search functionality

Allow user to update settings from plugin

## 0.1.0 (2025-04-14)

First functionality to allow user to download books

## 0.0.1 (2025-04-10)

Initial release
