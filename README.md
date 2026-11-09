# Audiobookshelf for KOReader

This is a KOReader plugin to browse, download books, and sync reading progress with an Audiobookshelf server.

## Installation

1. Unzip the release into your KOReader plugins directory
2. Copy the `audiobookshelf_config.example.lua` file to `audiobookshelf_config.lua`
3. Add your Audiobookshelf user's API key as `token` in the config file. This can be found on your Audiobookshelf server at Settings > Users > Click your username
4. Add the `server` to the config file, specifically the url of your server (no trailing slash)

## Usage

The Audiobookshelf menu can be found in Tools > Audiobookshelf.

![FileManager_2025-04-14_164132](https://github.com/user-attachments/assets/99ccfb5c-67b7-47a9-bdd0-cca2ece99c4e)

### Browsing and Downloading

Select "Browse library" to view the list of libraries available to your Audiobookshelf user.

![FileManager_2025-04-14_171731](https://github.com/user-attachments/assets/09d924c7-96d1-41d1-b68e-614da964cd63)

Click on one, and you will get the list of books available from that library (this only returns Audiobookshelf items that contain at least one eBook file).

![FileManager_2025-04-14_171903](https://github.com/user-attachments/assets/423a5c74-2578-4361-bc5a-acdfc3286ddf)

If you click on a book, you go to the Book Details page, which gives details about the book, including a list of Downloadable files:

![FileManager_2025-04-14_172035](https://github.com/user-attachments/assets/43c94cb7-28d1-4931-a658-8e321c528ea9)

Click on the name of one of the Downloadable files, and follow the process to download the eBook.

![FileManager_2025-04-14_172211](https://github.com/user-attachments/assets/a05ce960-48ae-4bf7-a5a3-54b161a3b211)

### Progress Sync

The plugin can sync your reading progress between KOReader and Audiobookshelf.

**Automatic linking:** Books downloaded through the plugin are automatically linked to their Audiobookshelf entry. Only a book's main ebook file is linked, because Audiobookshelf keeps one reading position per book. Links are stored in KOReader's `settings/audiobookshelf_mappings.lua`, so they survive reinstalling the plugin.

**Manual linking:** For books you already have on your device, open the book, go to Tools > Audiobookshelf > "Not linked to Audiobookshelf", search for the book, and select the matching entry.

**Sync triggers:**
- **On book close and on sleep:** Progress is pushed when you close a book or the device goes to sleep
- **On page turns:** After a configurable number of page turns (default: 5), progress is pushed once you pause on a page for about 10 seconds, so a page turn never waits on the network
- **On book open:** Server progress is checked and you're prompted if it differs from local
- **Manual:** Use "Push progress now" or "Pull progress now" from the menu (turns Wi-Fi on if needed)

Automatic syncs only run when the device is already online; they never turn Wi-Fi on. If the server can't be reached, automatic syncs pause for 10 minutes. Reaching the end of a book marks it finished on the server; the plugin never marks a book unfinished, so it can't reset a finished book or its audiobook position.

**Settings:** Go to Tools > Audiobookshelf > Sync settings to configure:
- Auto-push on book close (on/off)
- Auto-push on page turns (on/off)
- Pages before sync (1-50)
- Auto-pull on book open (on/off)

You can also set these in `audiobookshelf_config.lua`:

```lua
["sync"] = {
    ["auto_push_on_close"] = true,
    ["auto_push_on_page_turn"] = true,
    ["page_threshold"] = 5,
    ["auto_pull_on_open"] = true,
}
```

## Development

`sh tests/run.sh` runs the plugin's real code against stand-ins for KOReader (needs `luajit`). It starts from a copy with no config file, and covers navigation, series grouping, read status and progress sync.
