local AudiobookshelfApi = require("audiobookshelf/audiobookshelfapi")
local BookDetailsWidget = require("audiobookshelf/bookdetailswidget")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Settings = require("audiobookshelf/settings")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template
local logger = require("logger")

local AudiobookshelfBrowser = Menu:extend{
    no_title = false,
    title = _("Audiobookshelf Browser"),
    is_popout = false,
    is_borderless = true,
    title_bar_left_icon = "appbar.settings",
    show_parent = nil
}

-- Navigation: the top level lists libraries. Opening a library, a series or a
-- search pushes the current list onto self.paths; Back (the X button, the Back
-- key, swipe down or the bottom-left arrow) pops it, so it returns to exactly
-- the list and page you came from. The plugin only closes from the top level.
function AudiobookshelfBrowser:init()
    self.show_parent = self
    self.level = "abs"
    self.current_title = self.title
    self.item_table = self:genItemTableFromLibraries()
    Menu.init(self)
    if not Settings:isConfigured() then
        UIManager:nextTick(function() self:configAudiobookshelf() end)
    end
end

function AudiobookshelfBrowser:genItemTableFromLibraries()
    local item_table = {}
    if not Settings:isConfigured() then
        return item_table
    end
    local libraries = AudiobookshelfApi:getLibraries()
    if not libraries then
        UIManager:show(InfoMessage:new{
            text = _("Could not reach Audiobookshelf server. Check network and settings."),
            timeout = 2,
        })
        return item_table
    end
    for _, library in ipairs(libraries) do
        -- podcast libraries have no ebooks
        if library.mediaType == nil or library.mediaType == "book" then
            table.insert(item_table, {
                text = library.name,
                type = "library",
                id = library.id,
            })
        end
    end
    return item_table
end

-- Read status from Audiobookshelf: finished, started (reading or listening),
-- or not started. Every row gets a mark so titles stay aligned.
local STATUS_MARK = { finished = "● ", started = "◐ ", none = "○ " }

local function readStatus(progress)
    if not progress then return "none" end
    if progress.isFinished then return "finished" end
    if (progress.ebookProgress or 0) > 0 or (progress.progress or 0) > 0
            or (progress.currentTime or 0) > 0 then
        return "started"
    end
    return "none"
end

local function bookEntry(id, metadata, progress_map)
    local author = metadata.authorName
    local text = metadata.title or ""
    if progress_map then
        text = STATUS_MARK[readStatus(progress_map[id])] .. text
    end
    if author and author ~= "" then
        text = text .. " by " .. author
    end
    return { id = id, text = text, type = "book" }
end

-- Audiobookshelf gives seriesName as "Name #3", or "A #1, B #2" for a book in
-- several series. Group by the first series listed.
local function firstSeries(series_name)
    if not series_name or series_name == "" then return nil end
    local name, seq = series_name:match("^(.-) #([%d%.]+)")
    if name and name ~= "" then
        return name, seq
    end
    return series_name, nil
end

function AudiobookshelfBrowser:getFirstVisibleItemNumber()
    return ((self.page or 1) - 1) * (self.perpage or 1) + 1
end

-- Show a new list one level down, remembering the current one for Back.
function AudiobookshelfBrowser:pushList(level, title, item_table)
    table.insert(self.paths, {
        level = self.level,
        title = self.current_title,
        item_table = self.item_table,
        return_item = self:getFirstVisibleItemNumber(),
    })
    self:showList(level, title, item_table)
end

function AudiobookshelfBrowser:showList(level, title, item_table, item_number)
    self.level = level
    self.current_title = title
    self:setTitleBarLeftIcon(level == "abs" and "appbar.settings" or "appbar.search")
    self:switchItemTable(title, item_table, item_number)
end

function AudiobookshelfBrowser:onMenuSelect(item)
    if item.type == "library" then
        self:openLibrary(item.id, item.text)
    elseif item.type == "series" then
        self:openSeries(item)
    elseif item.type == "book" then
        local bookdetailswidget = BookDetailsWidget:new{
            book_id = item.id,
            -- used to close the whole plugin when opening a downloaded book
            onCloseParent = function()
                self:onCloseAllMenus()
            end,
        }
        UIManager:show(bookdetailswidget, "flashui")
    end
    return true
end

-- Defining onReturn makes Menu show its bottom-left back arrow.
function AudiobookshelfBrowser:onReturn()
    local parent = table.remove(self.paths)
    if not parent then
        return false
    end
    if parent.level == "abs" then
        self.library_id = nil
        self.search_value = nil
    end
    self:showList(parent.level, parent.title, parent.item_table, parent.return_item)
    return true
end

function AudiobookshelfBrowser:onClose()
    if #self.paths > 0 then
        return self:onReturn()
    end
    return Menu.onClose(self)
end

-- Menu doesn't refresh the arrow's enabled state for an empty list, which would
-- leave it disabled in a library or search with no results.
function AudiobookshelfBrowser:updatePageInfo(select_number)
    Menu.updatePageInfo(self, select_number)
    if #self.item_table == 0 then
        self.page_return_arrow:enableDisable(#self.paths > 0)
    end
end

function AudiobookshelfBrowser:onLeftButtonTap()
    if self.level == "abs" then
        self:configAudiobookshelf()
    else
        self:ShowSearch()
    end
end

function AudiobookshelfBrowser:configAudiobookshelf()
    local hint_server = "Audiobookshelf Server Url"
    local text_server = Settings:read("server", "")
    local hint_token = "Audiobookshelf API Token"
    local text_token = Settings:read("token", "")
    local title = "Audiobookshelf Settings"
    self.settings_dialog = MultiInputDialog:new {
        title = title,
        fields = {
            {
                text = text_server,
                input_type = "string",
                hint = hint_server
            },
            {
                text = text_token,
                input_type = "string",
                hint = hint_token
            }
        },
        buttons = {
            {
                {
                    text = "Cancel",
                    id = "close",
                    callback = function()
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
                {
                    text = "Save",
                    callback = function()
                        local fields = self.settings_dialog:getFields()

                        Settings:save("server", fields[1])
                        Settings:save("token", fields[2])

                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)

                        UIManager:show(InfoMessage:new{
                            text = "Settings saved",
                            timeout = 1
                        })
                        if self.level == "abs" then
                            self.item_table = self:genItemTableFromLibraries()
                            self:showList("abs", self.title, self.item_table)
                        end
                    end
                }
            }
        }
    }
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end

function AudiobookshelfBrowser:ShowSearch()
    self.search_dialog = InputDialog:new{
        title = "Search",
        input = self.search_value,
        buttons = {
            {
                {
                    text = "Cancel",
                    id = "close",
                    enabled = true,
                    callback = function()
                        self.search_dialog:onClose()
                        UIManager:close(self.search_dialog)
                    end
                },
                {
                    text = "Search",
                    enabled = true,
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        self:search()
                    end
                }
            }
        }
    }
    UIManager:show(self.search_dialog)
    self.search_dialog:onShowKeyboard()
end

function AudiobookshelfBrowser:search()
    if self.search_value then
        self.search_dialog:onClose()
        UIManager:close(self.search_dialog)
        if string.len(self.search_value) > 0 then
            self:loadLibrarySearch(self.search_value)
        end
    end
end

function AudiobookshelfBrowser:loadLibrarySearch(search)
    local tbl = {}
    local libraryItems = AudiobookshelfApi:getSearchResults(self.library_id, search)
    if not libraryItems or not libraryItems.book then
        UIManager:show(InfoMessage:new{
            text = _("Search failed. Check network and settings."),
            timeout = 2,
        })
        return
    end
    -- nil if it can't be fetched; the list then just shows without marks
    local progress_map = AudiobookshelfApi:getAllProgress()
    for _, item in ipairs(libraryItems.book) do
        table.insert(tbl, bookEntry(item.libraryItem.id, item.libraryItem.media.metadata, progress_map))
    end

    -- a new search replaces the current results, so Back still returns to
    -- where the first search started
    if self.level == "search" then
        self:showList("search", _("Search Results"), tbl)
    else
        self:pushList("search", _("Search Results"), tbl)
    end
end

function AudiobookshelfBrowser:openLibrary(id, name)
    local libraryItems = AudiobookshelfApi:getLibraryItems(id)
    if not libraryItems then
        UIManager:show(InfoMessage:new{
            text = _("Could not load library. Check network and settings."),
            timeout = 2,
        })
        return false
    end

    local progress_map = AudiobookshelfApi:getAllProgress()

    -- Books in a series are grouped into one entry per series, listed first.
    local tbl = {}
    local series_map = {}
    local series_order = {}
    for __, item in ipairs(libraryItems) do
        local metadata = item.media.metadata
        local series, seq = firstSeries(metadata.seriesName)
        if series then
            if not series_map[series] then
                series_map[series] = {}
                table.insert(series_order, series)
            end
            table.insert(series_map[series], {
                id = item.id,
                metadata = metadata,
                sequence = tonumber(seq) or math.huge,
                seq_str = seq,
            })
        else
            table.insert(tbl, bookEntry(item.id, metadata, progress_map))
        end
    end

    table.sort(series_order, function(a, b) return a:lower() < b:lower() end)
    local series_entries = {}
    for __, series in ipairs(series_order) do
        local books = series_map[series]
        table.sort(books, function(a, b) return a.sequence < b.sequence end)
        local text, mandatory = series, tostring(#books) .. " " .. (#books == 1 and _("book") or _("books"))
        if progress_map then
            local finished, started = 0, false
            for __, book in ipairs(books) do
                local status = readStatus(progress_map[book.id])
                if status == "finished" then finished = finished + 1 end
                if status ~= "none" then started = true end
            end
            local mark = finished == #books and "finished" or (started and "started" or "none")
            text = STATUS_MARK[mark] .. series
            mandatory = T(_("%1/%2 read"), finished, #books)
        end
        table.insert(series_entries, {
            text = text,
            mandatory = mandatory,
            type = "series",
            series_books = books,
            progress_map = progress_map,
        })
    end
    for i, entry in ipairs(series_entries) do
        table.insert(tbl, i, entry)
    end

    self.library_id = id
    self:pushList("library", name, tbl)
    return true
end

function AudiobookshelfBrowser:openSeries(item)
    local tbl = {}
    for _, book in ipairs(item.series_books) do
        local entry = bookEntry(book.id, book.metadata, item.progress_map)
        if book.seq_str then
            -- keep the read mark first: "● 3. Title"
            local mark = item.progress_map and STATUS_MARK[readStatus(item.progress_map[book.id])] or ""
            entry.text = mark .. book.seq_str .. ". " .. entry.text:sub(#mark + 1)
        end
        table.insert(tbl, entry)
    end
    self:pushList("series", item.text, tbl)
    return true
end

return AudiobookshelfBrowser
