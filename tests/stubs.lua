-- Minimal KOReader stand-ins. LuaSettings is file-backed and behaves like the
-- real one: each open() reads the file, each flush() rewrites the whole file.
local H = { shown = {}, closed = {}, scheduled = {}, requests = {}, online = true, now = 1000 }
_G.H = H
local function noop() end
local function serialize(v, ind)
  ind = ind or ""
  if type(v) == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys+1] = k end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    local out = {"{\n"}
    for _, k in ipairs(keys) do
      out[#out+1] = ind .. "  [" .. string.format("%q", k) .. "] = " .. serialize(v[k], ind .. "  ") .. ",\n"
    end
    return table.concat(out) .. ind .. "}"
  elseif type(v) == "string" then return string.format("%q", v)
  else return tostring(v) end
end
H.serialize = serialize
local LuaSettings = {}; LuaSettings.__index = LuaSettings
function LuaSettings:open(file)
  local o = setmetatable({ file = file, data = {} }, LuaSettings)
  local f = io.open(file); if f then f:close(); o.data = dofile(file) or {} end
  return o
end
function LuaSettings:readSetting(k, d) local v = self.data[k]; if v == nil then return d end return v end
function LuaSettings:saveSetting(k, v) self.data[k] = v end
function LuaSettings:flush() local f = assert(io.open(self.file, "w")); f:write("return " .. serialize(self.data) .. "\n"); f:close() end
package.preload["luasettings"] = function() return LuaSettings end

local W = {}; W.__index = W
function W:extend(o) o = o or {}; o.__index = o; return setmetatable(o, self) end
function W:new(o) o = o or {}; setmetatable(o, self); if o.init then o:init() end; return o end
function W:onShowKeyboard() end
function W:onClose() end
function W:getInputText() return self.input end
local function widget() return W:extend{} end
for _, m in ipairs{"ui/widget/infomessage","ui/widget/inputdialog","ui/widget/multiinputdialog","ui/widget/confirmbox",
  "ui/widget/buttondialogtitle","ui/widget/spinwidget","ui/widget/container/widgetcontainer"} do
  package.preload[m] = widget
end
-- Menu: just enough of the real Menu's state handling
local Menu = W:extend{}
function Menu:init()
  self.paths = {}; self.page = 1; self.perpage = 10; self.item_table_stack = {}
  self.title_bar = { setTitle = function(_, t) self.shown_title = t end }
  self.page_return_arrow = { enableDisable = function(_, v) self.arrow_enabled = v end }
  self.shown_title = self.title
end
function Menu:updatePageInfo() if #self.item_table > 0 then self.page_return_arrow:enableDisable(#self.paths > 0) end end
function Menu:switchItemTable(title, items, n)
  if title then self.title_bar:setTitle(title) end
  if items then self.item_table = items end
  self.page = n and math.ceil(n / self.perpage) or 1
  self:updatePageInfo()
end
function Menu:setTitleBarLeftIcon(i) self.left_icon = i end
function Menu:onClose() return self:onCloseAllMenus() end
function Menu:onCloseAllMenus() H.menu_closed = true; return true end
package.preload["ui/widget/menu"] = function() return Menu end

package.preload["ui/uimanager"] = function() return {
  show = function(_, w) H.shown[#H.shown+1] = w end,
  close = function(_, w) H.closed[#H.closed+1] = w end,
  scheduleIn = function(_, s, f) H.scheduled[#H.scheduled+1] = { at = H.now + s, f = f } end,
  nextTick = function(_, f) H.scheduled[#H.scheduled+1] = { at = H.now, f = f } end,
  unschedule = function(_, f) for i = #H.scheduled, 1, -1 do if H.scheduled[i].f == f then table.remove(H.scheduled, i) end end end,
  broadcastEvent = noop,
} end
function H.advance(sec)
  H.now = H.now + sec
  local due = {}
  for i = #H.scheduled, 1, -1 do if H.scheduled[i].at <= H.now then table.insert(due, 1, table.remove(H.scheduled, i)) end end
  for _, t in ipairs(due) do t.f() end
end
local real_time = os.time
os.time = function(t) if t then return real_time(t) end return H.now end

package.preload["ui/network/manager"] = function() return {
  isOnline = function() return H.online end,
  runWhenOnline = function(_, f) H.ran_when_online = (H.ran_when_online or 0) + 1; f() end,
} end
package.preload["dispatcher"] = function() return { registerAction = noop } end
package.preload["gettext"] = function() return function(s) return s end end
package.preload["logger"] = function() return { warn = noop, dbg = noop, info = noop, err = noop } end
package.preload["datastorage"] = function() return { getSettingsDir = function() return H.settings_dir end } end
package.preload["ffi/util"] = function() return { template = function(s, ...) local a = {...}; return (s:gsub("%%(%d)", function(i) return tostring(a[tonumber(i)]) end)) end } end
package.preload["util"] = function() return { urlEncode = function(s) return s end } end
package.preload["ui/renderimage"] = function() return {} end
package.preload["ui/event"] = function() return { new = function(_, name, arg) return { name = name, arg = arg } end } end
package.preload["socketutil"] = function() return { set_timeout = function(_, b, t) H.last_timeout = { b, t } end, reset_timeout = noop } end
package.preload["socket"] = function() return { skip = function(n, ...) return select(n + 1, ...) end } end
package.preload["ltn12"] = function() return {
  sink = { table = function(t) return function(chunk) if chunk then t[#t+1] = chunk end return 1 end end, file = function() return noop end },
  source = { string = function(s) return function() local x = s; s = nil; return x end end },
} end
-- tiny JSON: encode flat tables, decode via a server-provided Lua value
package.preload["json"] = function()
  local J = {}
  function J.encode(t)
    local parts = {}
    local keys = {}; for k in pairs(t) do keys[#keys+1] = k end; table.sort(keys)
    for _, k in ipairs(keys) do local v = t[k]
      parts[#parts+1] = string.format("%q:%s", k, type(v) == "string" and string.format("%q", v) or tostring(v)) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  J.decode = setmetatable({ simple = {} }, { __call = function(_, s) local v = H.decode_map[s]; if v == nil then error("not json") end return v end })
  return J
end
-- fake server: H.routes[method .. " " .. path] = { code, lua_value }
package.preload["socket.http"] = function() return { request = function(req)
  if not H.online then error("network unreachable") end
  local body = req.source and req.source() or nil
  H.requests[#H.requests+1] = { method = req.method, url = req.url, body = body, auth = req.headers.Authorization }
  local path = req.url:gsub("^https?://[^/]+", "")
  local r = H.routes[req.method .. " " .. path:gsub("%?.*$", "")] or { 404, nil, "Not Found" }
  local text = r[3] or ("json:" .. #H.requests)
  if r[2] ~= nil then H.decode_map[text] = r[2] end
  req.sink(text); req.sink(nil)
  return 1, r[1], {}, "HTTP/1.1 " .. r[1]
end } end
H.decode_map = {}
H.routes = {}
-- Any other KOReader UI module (only needed by the book page widgets): a generic widget class.
table.insert(package.loaders, function(name)
  if name:match("^ui/") or name:match("^ffi/") or name:match("^apps/") or name:match("^document/")
     or name:match("^libs/") or name == "device" then
    -- deep auto-table: any field is another auto-table, so module-level
    -- lookups like Size.padding.fullscreen work
    local function auto()
      return setmetatable(W:extend{}, { __index = function(t, k)
        if W[k] then return W[k] end
        local v = auto(); rawset(t, k, v); return v end })
    end
    return function() return auto() end
  end
end)
return H
