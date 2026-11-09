-- One shared copy of audiobookshelf_config.lua for the whole plugin.
-- Separate LuaSettings instances on the same file overwrite each other's
-- changes when they flush, so every module must use this one.
local LuaSettings = require("luasettings")

local plugin_dir = string.gsub(debug.getinfo(1).source, "^@(.+/)[^/]+$", "%1") .. "/.."

local Settings = {
    plugin_dir = plugin_dir,
    store = LuaSettings:open(plugin_dir .. "/audiobookshelf_config.lua"),
}

function Settings:read(key, default)
    return self.store:readSetting(key, default)
end

function Settings:save(key, value)
    self.store:saveSetting(key, value)
    self.store:flush()
end

-- Server URL without trailing slashes, or nil if not set.
function Settings:getServer()
    local server = self.store:readSetting("server")
    if type(server) ~= "string" then return nil end
    server = server:gsub("^%s+", ""):gsub("%s+$", ""):gsub("/+$", "")
    if server == "" then return nil end
    return server
end

function Settings:getToken()
    local token = self.store:readSetting("token")
    if type(token) ~= "string" then return nil end
    token = token:gsub("^%s+", ""):gsub("%s+$", "")
    if token == "" then return nil end
    return token
end

function Settings:isConfigured()
    return self:getServer() ~= nil and self:getToken() ~= nil
end

return Settings
