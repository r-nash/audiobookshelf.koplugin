local plugin, settings_dir = arg[1], arg[2]
package.path = plugin .. "/?.lua;" .. package.path
local H = dofile(arg[0]:gsub("tests%.lua$", "stubs.lua"))
H.settings_dir = settings_dir
local pass = 0
local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end pass = pass + 1 end
local function last_shown() return H.shown[#H.shown] end
local cfg = plugin .. "/audiobookshelf_config.lua"
check(io.open(cfg) == nil, "test starts with no config file")

-- 1. Everything loads with the config file missing ---------------------------
-- the book page is pure layout: load its real code (and the download row it
-- uses) to prove it loads, then stand in for drawing it
package.preload["audiobookshelf/bookdetailswidget"] = function()
  assert(loadfile(plugin .. "/audiobookshelf/bookdetailswidget.lua"))()
  return { new = function(_, o) return o end }
end
local Main = require("main")
for _, m in ipairs{"audiobookshelf/audiobookshelfapi","audiobookshelf/audiobookshelfbrowser",
  "audiobookshelf/progresssync","audiobookshelf/bookmapping","audiobookshelf/settings"} do
  check(pcall(require, m), "module loads without config: " .. m)
end
local menu_items = {}
local fm = Main:new{ ui = { menu = { registerToMainMenu = function(_, p) p:addToMainMenu(menu_items) end } } }
check(menu_items.audiobookshelf ~= nil, "Audiobookshelf menu entry registered without config")
local link_item = menu_items.audiobookshelf.sub_item_table[4]
check(link_item.text_func() == "Open a book to link or sync progress", "file browser explains why sync items are unavailable")
check(dofile(plugin .. "/_meta.lua").name == nil, "_meta.lua has no deprecated name field")
local Api = require("audiobookshelf/audiobookshelfapi")
check(Api:getLibraries() == nil and #H.requests == 0, "unconfigured API fails quietly without a request")

local Browser = require("audiobookshelf/audiobookshelfbrowser")
local b = Browser:new{}
check(#b.item_table == 0, "empty library list when unconfigured")
H.advance(0)
check(b.settings_dialog ~= nil, "settings dialog opens automatically when unconfigured")

-- 2. Saving settings works and reloads libraries -----------------------------
H.routes["GET /api/libraries"] = { 200, { libraries = { { name = "Books", id = "L1" } } } }
b.settings_dialog.getFields = function() return { "https://abs.example/ ", "tok123" } end
b.settings_dialog.onClose = function() end
b.settings_dialog.buttons[1][2].callback()
check(#b.item_table == 1 and b.item_table[1].text == "Books", "libraries load right after saving settings")
check(H.requests[#H.requests].url == "https://abs.example/api/libraries", "trailing slash and spaces trimmed from server URL")
check(H.requests[#H.requests].auth == "Bearer tok123", "token sent")

-- 3. One shared settings store -------------------------------------------------
fm:saveSyncSetting("page_threshold", 7)
local saved = dofile(cfg)
check(saved.server == "https://abs.example/ " and saved.token == "tok123" and saved.sync.page_threshold == 7,
  "server, token and sync settings all survive together in the config file")
check(fm:getSyncSettings().auto_pull_on_open == true, "unsaved sync options fall back to defaults")

-- 4. Navigation with series ---------------------------------------------------
local function item(id, title, author, series) return { id = id, media = { metadata = { title = title, authorName = author, seriesName = series } } } end
H.routes["GET /api/libraries/L1/items"] = { 200, { results = {
  item("a", "Anathem", "Neal Stephenson", ""),
  item("d2", "Carl's Doomsday Scenario", "Matt Dinniman", "Dungeon Crawler Carl #2"),
  item("d1", "Dungeon Crawler Carl", "Matt Dinniman", "Dungeon Crawler Carl #1"),
  item("h10", "He Who Fights with Monsters 10", "Shirtaloon", "He Who Fights with Monsters #10"),
  item("h2", "He Who Fights with Monsters 2", "Shirtaloon", "He Who Fights with Monsters #2"),
  item("x", "Crossover", "Someone", "Zeta Saga #1, Alpha Saga #3"),
  item("n", "No Author", nil, nil),
} } }
b:onMenuSelect(b.item_table[1])
check(b.level == "library" and #b.paths == 1 and b.shown_title == "Books", "opened library")
check(b.arrow_enabled == true and b.left_icon == "appbar.search", "back arrow and search icon in library")
local texts = {} for i, e in ipairs(b.item_table) do texts[i] = e.text end
check(texts[1] == "Dungeon Crawler Carl" and texts[2] == "He Who Fights with Monsters" and texts[3] == "Zeta Saga",
  "series first, alphabetical, multi-series book under its first series: " .. table.concat(texts, " | "))
check(b.item_table[1].mandatory == "2 books", "series shows book count")
check(texts[4] == "Anathem by Neal Stephenson" and texts[5] == "No Author", "loose books as 'title by author', missing author OK")
local library_table = b.item_table
b.page = 2
b:onMenuSelect(b.item_table[2])
check(b.level == "series" and #b.paths == 2 and b.shown_title == "He Who Fights with Monsters", "opened series")
check(b.item_table[1].text == "2. He Who Fights with Monsters 2 by Shirtaloon" and b.item_table[2].text:sub(1,3) == "10.",
  "series books in numeric reading order (2 before 10)")
b:onMenuSelect(b.item_table[1])
check(last_shown().book_id == "h2" and not H.menu_closed, "book page opens over the list")
H.routes["GET /api/libraries/L1/search"] = { 200, { book = { { libraryItem = item("d1", "Dungeon Crawler Carl", "Matt Dinniman", "") } } } }
b:onLeftButtonTap(); check(b.search_dialog ~= nil, "search available inside a series")
b:loadLibrarySearch("carl"); b:loadLibrarySearch("carl again")
check(b.level == "search" and #b.paths == 3, "repeat search replaces results instead of stacking")
check(b:onClose() and b.level == "series" and b.shown_title == "He Who Fights with Monsters", "X from search returns to the series")
check(b:onReturn() and b.level == "library" and b.item_table == library_table and b.page == 2, "back from series returns to the library, same page")
check(b:onClose() and b.level == "abs" and b.left_icon == "appbar.settings" and b.library_id == nil, "back to library list")
check(not H.menu_closed, "plugin still open after stepping back")
b:onClose(); check(H.menu_closed, "X at the top level closes the plugin")
H.menu_closed = nil
H.routes["GET /api/libraries/L1/items"] = { 500, nil, "err" }
local b2 = Browser:new{}; b2:onMenuSelect(b2.item_table[1])
check(b2.level == "abs" and #b2.paths == 0, "failed library load leaves navigation intact")

-- 5. Progress sync -------------------------------------------------------------
local BookMapping = require("audiobookshelf/bookmapping")
local PS = require("audiobookshelf/progresssync")
local page, total = 50, 100
local reader_events = {}
local ui = { menu = { registerToMainMenu = function() end },
  document = { file = "/mnt/us/books/hwfwm5.epub", info = { has_pages = false },
    getPageCount = function() return total end, getProps = function() return {} end },
  rolling = { getLastPercent = function() return page / total end },
  getCurrentPage = function() return page end,
  handleEvent = function(_, ev) reader_events[#reader_events+1] = ev end }
BookMapping:setMapping(ui.document.file, "h5", 77, "HWFWM 5")
check(io.open(settings_dir .. "/audiobookshelf_mappings.lua") ~= nil, "links stored in KOReader's settings folder")
local reader = Main:new{ ui = ui }
local function progress_requests(method)
  local n, last = 0, nil
  for _, r in ipairs(H.requests) do if r.url:find("/api/me/progress/h5", 1, true) and r.method == method then n = n + 1; last = r end end
  return n, last
end
H.routes["GET /api/me/progress/h5"] = { 404, nil, "Not Found" }
H.routes["PATCH /api/me/progress/h5"] = { 200, nil, "OK" }
local shown_before = #H.shown
reader:onReaderReady(); H.advance(1)
check(progress_requests("GET") == 1 and #H.shown == shown_before, "no server progress yet: checked quietly, no popup")

H.advance(30)
for i = 1, 6 do page = page + 1; reader:onPageUpdate(page) end
check(progress_requests("PATCH") == 0, "no request while turning pages")
H.advance(5); page = page + 1; reader:onPageUpdate(page)
H.advance(9); check(progress_requests("PATCH") == 0, "push keeps waiting while pages keep turning")
H.advance(2)
local n, last = progress_requests("PATCH")
check(n == 1 and last.body == '{"ebookProgress":0.57}', "one push after the pause, no isFinished: " .. tostring(last and last.body))
check(H.last_timeout[1] == 3 and H.last_timeout[2] == 6, "short timeouts on sync requests")

page = 100; H.advance(30); reader:onSuspend()
n, last = progress_requests("PATCH")
check(n == 2 and last.body == '{"ebookProgress":1,"isFinished":true}', "suspend pushes; end of book marks it finished: " .. tostring(last and last.body))

H.online = false; H.advance(60)
for i = 1, 6 do reader:onPageUpdate(i) end; H.advance(20); reader:onSuspend()
check(progress_requests("PATCH") == 2, "offline: no sync attempts")
H.online = true

H.routes["PATCH /api/me/progress/h5"] = { 502, nil, "Bad Gateway" }
H.advance(60); page = 40; reader:onSuspend()
check(progress_requests("PATCH") == 3, "attempted once while server is down")
H.advance(60); for i = 1, 6 do reader:onPageUpdate(10 + i) end; H.advance(20); reader:onSuspend()
check(progress_requests("PATCH") == 3, "backs off after a failure instead of retrying every few pages")
H.routes["PATCH /api/me/progress/h5"] = { 200, nil, "OK" }
H.advance(700); reader:onSuspend()
check(progress_requests("PATCH") == 4, "resumes after the back-off period")

H.routes["GET /api/me/progress/h5"] = { 200, { ebookProgress = 0.8, lastUpdate = 1700000000000 } }
page = 40; reader:onReaderReady(); H.advance(1)
local box = last_shown()
check(box.ok_text == "Use server" and box.text:find("Server is ahead"), "asks before jumping to the server position")
box.ok_callback()
check(reader_events[#reader_events].name == "GotoPercent" and reader_events[#reader_events].arg == 80, "jumps to the server percentage")

local before = H.ran_when_online or 0
H.advance(30); reader:onABSPushProgress()
check((H.ran_when_online or 0) == before + 1 and progress_requests("PATCH") == 5, "manual push turns Wi-Fi on first and pushes")

-- (pages before sync was set to 7 in section 3)
H.advance(60)
for i = 1, 7 do page = page + 1; reader:onPageUpdate(page) end
check(PS.push_task ~= nil, "push scheduled after 7 page turns")
local pending = #H.scheduled
reader:onCloseDocument()
check(#H.scheduled < pending, "closing the book cancels the pending push")
check(progress_requests("PATCH") == 6, "closing the book pushes once")
check(PS.current_mapping == nil, "sync state cleared after close")
H.advance(60); check(progress_requests("PATCH") == 6, "no stray push after the book is closed")

local EB = io.open(plugin .. "/audiobookshelf/ebookfilewidget.lua"):read("*a")
check(EB:find("if self.is_primary then", 1, true), "download links only the main ebook file")
-- 7. 0.2.1: read status, podcast libraries --------------------------------------
H.routes["GET /api/libraries"] = { 200, { libraries = {
  { name = "Books", id = "L1", mediaType = "book" }, { name = "Podcasts", id = "P1", mediaType = "podcast" } } } }
H.routes["GET /api/libraries/L1/items"] = { 200, { results = {
  item("a", "Anathem", "Neal Stephenson", ""),
  item("b", "Blindsight", "Peter Watts", ""),
  item("c", "Children of Time", "Adrian Tchaikovsky", ""),
  item("h1", "HWFWM 1", "Shirtaloon", "He Who Fights with Monsters #1"),
  item("h2", "HWFWM 2", "Shirtaloon", "He Who Fights with Monsters #2"),
  item("h3", "HWFWM 3", "Shirtaloon", "He Who Fights with Monsters #3"),
  item("d1", "Dungeon Crawler Carl", "Matt Dinniman", "Dungeon Crawler Carl #1"),
} } }
H.routes["GET /api/me"] = { 200, { mediaProgress = {
  { libraryItemId = "a", isFinished = true },
  { libraryItemId = "b", ebookProgress = 0.3, progress = 0 },
  { libraryItemId = "h1", isFinished = true }, { libraryItemId = "h2", isFinished = true },
  { libraryItemId = "h3", ebookProgress = 0, progress = 0.4, currentTime = 1200 },
  { libraryItemId = "c", episodeId = "ep1", isFinished = true },
} } }
local b3 = Browser:new{}
check(#b3.item_table == 1 and b3.item_table[1].text == "Books", "podcast libraries hidden")
b3:onMenuSelect(b3.item_table[1])
local t = {} for i, e in ipairs(b3.item_table) do t[i] = e.text end
check(t[1] == "○ Dungeon Crawler Carl" and b3.item_table[1].mandatory == "0/1 read", "unstarted series: " .. t[1])
check(t[2] == "◐ He Who Fights with Monsters" and b3.item_table[2].mandatory == "2/3 read", "series in progress with count: " .. t[2])
check(t[3] == "● Anathem by Neal Stephenson", "finished book marked")
check(t[4] == "◐ Blindsight by Peter Watts", "ebook in progress marked")
check(t[5] == "○ Children of Time by Adrian Tchaikovsky", "podcast-episode progress ignored, book unstarted")
b3:onMenuSelect(b3.item_table[2])
check(b3.item_table[1].text == "● 1. HWFWM 1 by Shirtaloon" and b3.item_table[3].text == "◐ 3. HWFWM 3 by Shirtaloon",
  "marks before the series number; audiobook listening counts as started: " .. b3.item_table[3].text)
H.routes["GET /api/me"] = { 500, nil, "err" }
b3:onClose(); b3:onClose(); check(b3.level == "abs", "two Backs from a series reach the library list"); b3:onMenuSelect(b3.item_table[1])
check(b3.item_table[3].text == "Anathem by Neal Stephenson" and b3.item_table[2].mandatory == "3 books",
  "if progress can't be fetched, the list still shows, without marks")

-- 8. No loop variable named _ hides gettext ------------------------------------
for _, f in ipairs{"main.lua","audiobookshelf/audiobookshelfbrowser.lua","audiobookshelf/progresssync.lua",
  "audiobookshelf/audiobookshelfapi.lua","audiobookshelf/bookdetailswidget.lua","audiobookshelf/ebookfilewidget.lua"} do
  local depth
  local n = 0
  for line in io.lines(plugin .. "/" .. f) do
    n = n + 1
    local ind = line:match("^(%s*)for _,")
    if ind then depth = #ind
    elseif depth then
      if line:match("^" .. string.rep(" ", depth) .. "end%f[%W]") then depth = nil
      else check(not line:find("%f[%w_]_%("), f .. ":" .. n .. " calls _() inside a 'for _,' loop") end
    end
  end
end
print(("all %d checks passed"):format(pass))
