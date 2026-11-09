local AudiobookshelfApi = require("audiobookshelf/audiobookshelfapi")
local BookMapping = require("audiobookshelf/bookmapping")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local ProgressSync = {
    MIN_SYNC_INTERVAL = 25,
    DEFAULT_PAGE_THRESHOLD = 5,
    -- push this long after the last page turn, so it runs while you read a
    -- page rather than when you turn one
    IDLE_PUSH_DELAY = 10,
    -- after an automatic sync fails, don't retry automatically for this long,
    -- so an unreachable server can't stall reading every few pages
    FAILURE_BACKOFF = 600,

    ui = nil,
    last_sync_time = 0,
    page_turn_count = 0,
    current_mapping = nil,
    backoff_until = 0,
}

-- Automatic syncs only run when already online: they never turn Wi-Fi on or
-- show a connection prompt, and they stay quiet after a recent failure.
function ProgressSync:canAutoSync()
    if os.time() < self.backoff_until then
        return false
    end
    return NetworkMgr:isOnline()
end

function ProgressSync:noteResult(ok, err)
    if ok then
        self.backoff_until = 0
    elseif err == "network_error" or err == "api_error" then
        self.backoff_until = os.time() + self.FAILURE_BACKOFF
    end
end

function ProgressSync:init(ui)
    self:cancelScheduledPush()
    self.ui = ui
    self.last_sync_time = 0
    self.page_turn_count = 0
    self.current_mapping = nil
end

function ProgressSync:loadMappingForDocument()
    if not self.ui or not self.ui.document then
        return nil
    end
    local filepath = self.ui.document.file
    self.current_mapping = BookMapping:getMapping(filepath)
    return self.current_mapping
end

function ProgressSync:calculateProgress()
    if not self.ui or not self.ui.document then
        return nil
    end

    -- KOReader's own reading percentage: the same figure as its status bar,
    -- and more precise than page / total for reflowable books.
    local ok, current, total, percent = pcall(function()
        local reader = self.ui.document.info.has_pages and self.ui.paging or self.ui.rolling
        return self.ui:getCurrentPage(), self.ui.document:getPageCount(), reader:getLastPercent()
    end)

    if not ok or not current or not total or total == 0 then
        logger.warn("ProgressSync: failed to calculate progress")
        return nil
    end
    if type(percent) ~= "number" or percent ~= percent then
        percent = current / total
    end
    percent = math.max(0, math.min(1, percent))

    return {
        page = current,
        total_pages = total,
        percent = math.floor(percent * 10000 + 0.5) / 10000,
        timestamp = os.time(),
    }
end

function ProgressSync:shouldSync()
    local now = os.time()
    if now - self.last_sync_time < self.MIN_SYNC_INTERVAL then
        return false
    end
    return true
end

function ProgressSync:pushProgress(blocking, callback)
    if not self.current_mapping then
        logger.dbg("ProgressSync: no mapping, skipping push")
        if callback then callback(false, "no_mapping") end
        return
    end

    if not self:shouldSync() and not blocking then
        logger.dbg("ProgressSync: debounced, skipping push")
        if callback then callback(false, "debounced") end
        return
    end

    local local_progress = self:calculateProgress()
    if not local_progress then
        if callback then callback(false, "no_progress") end
        return
    end

    local progress_data = {
        ebookProgress = local_progress.percent,
    }
    -- Only ever report "finished". Sending isFinished = false makes the server
    -- un-finish the book and reset the audiobook position to 0 whenever the
    -- book was already finished, e.g. after listening to it.
    if local_progress.percent >= 0.99 then
        progress_data.isFinished = true
    end

    logger.dbg("ProgressSync: pushing progress", local_progress.percent, "to", self.current_mapping.library_item_id)

    local result, err = AudiobookshelfApi:updateProgress(
        self.current_mapping.library_item_id,
        progress_data
    )

    self:noteResult(result, err)
    if result then
        self.last_sync_time = os.time()
        BookMapping:updateLastSync(self.ui.document.file)
        logger.dbg("ProgressSync: push successful")
        if callback then callback(true) end
    else
        logger.dbg("ProgressSync: push failed:", err)
        if callback then callback(false, err) end
    end
end

function ProgressSync:pullProgress(callback)
    if not self.current_mapping then
        logger.dbg("ProgressSync: no mapping, skipping pull")
        if callback then callback(false, "no_mapping") end
        return
    end

    logger.dbg("ProgressSync: pulling progress for", self.current_mapping.library_item_id)

    local server_progress, err = AudiobookshelfApi:getProgress(self.current_mapping.library_item_id)

    if err == "not_found" then
        logger.dbg("ProgressSync: no server progress exists")
        if callback then callback(true, nil) end
        return
    end

    self:noteResult(server_progress ~= nil, err)
    if not server_progress then
        logger.warn("ProgressSync: pull failed:", err)
        if callback then callback(false, err) end
        return
    end

    if callback then callback(true, server_progress) end
end

function ProgressSync:checkAndPromptServerProgress(show_no_diff_message)
    self:pullProgress(function(success, server_progress)
        if not success then
            if show_no_diff_message then
                UIManager:show(InfoMessage:new{
                    text = _("Could not fetch progress from server."),
                    timeout = 3,
                })
            end
            return
        end

        if not server_progress then
            if show_no_diff_message then
                UIManager:show(InfoMessage:new{
                    text = _("No progress on server yet."),
                    timeout = 2,
                })
            end
            return
        end

        local local_progress = self:calculateProgress()
        if not local_progress then
            return
        end

        local server_percent = server_progress.ebookProgress or server_progress.progress or 0
        local local_percent = local_progress.percent

        local diff = math.abs(server_percent - local_percent)
        if diff < 0.01 then
            if show_no_diff_message then
                UIManager:show(InfoMessage:new{
                    text = _("Progress is already in sync."),
                    timeout = 2,
                })
            end
            return
        end

        local server_page = math.floor(server_percent * local_progress.total_pages)
        local server_time_str = ""
        if server_progress.lastUpdate then
            server_time_str = os.date("%Y-%m-%d %H:%M", server_progress.lastUpdate / 1000)
        end

        local message
        if server_percent > local_percent then
            message = T(_("Server is ahead of local.\n\nLocal: Page %1 (%2%%)\nServer: Page %3 (%4%%)\nServer updated: %5\n\nJump to server position?"),
                local_progress.page,
                math.floor(local_percent * 100),
                server_page,
                math.floor(server_percent * 100),
                server_time_str
            )
        else
            message = T(_("Server is behind local.\n\nLocal: Page %1 (%2%%)\nServer: Page %3 (%4%%)\nServer updated: %5\n\nGo back to server position?"),
                local_progress.page,
                math.floor(local_percent * 100),
                server_page,
                math.floor(server_percent * 100),
                server_time_str
            )
        end

        UIManager:show(ConfirmBox:new{
            text = message,
            ok_text = _("Use server"),
            cancel_text = _("Keep local"),
            ok_callback = function()
                self:applyServerProgress(server_progress)
            end,
        })
    end)
end

function ProgressSync:applyServerProgress(server_progress)
    if not self.ui or not self.ui.document then
        return
    end

    local server_percent = server_progress.ebookProgress or server_progress.progress or 0
    server_percent = math.max(0, math.min(1, server_percent))

    logger.dbg("ProgressSync: applying server progress, going to", server_percent * 100, "%")

    local Event = require("ui/event")
    self.ui:handleEvent(Event:new("GotoPercent", server_percent * 100))

    UIManager:show(InfoMessage:new{
        text = T(_("Moved to %1%% (page %2)."), math.floor(server_percent * 100), self.ui:getCurrentPage()),
        timeout = 2,
    })
end

function ProgressSync:onPageTurn(settings)
    if not self.current_mapping then
        return
    end

    local auto_sync = settings and settings.auto_push_on_page_turn
    if auto_sync == false then
        return
    end

    self.page_turn_count = self.page_turn_count + 1

    local threshold = (settings and settings.page_threshold) or self.DEFAULT_PAGE_THRESHOLD
    -- once a push is due, keep delaying it until page turns stop for a moment
    if self.push_task or self.page_turn_count >= threshold then
        self:schedulePush()
    end
end

function ProgressSync:schedulePush()
    self:cancelScheduledPush()
    self.push_task = function()
        self.push_task = nil
        if not self.current_mapping or not self:canAutoSync() then
            return
        end
        self.page_turn_count = 0
        self:pushProgress(false)
    end
    UIManager:scheduleIn(self.IDLE_PUSH_DELAY, self.push_task)
end

function ProgressSync:cancelScheduledPush()
    if self.push_task then
        UIManager:unschedule(self.push_task)
        self.push_task = nil
    end
end

function ProgressSync:reset()
    self:cancelScheduledPush()
    self.ui = nil
    self.last_sync_time = 0
    self.page_turn_count = 0
    self.current_mapping = nil
end

return ProgressSync
