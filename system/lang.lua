-- FixOS 4.0.1 - system/lang.lua
-- Language system loader
-- FIX 4.0.1:
--   - Explicit component/computer references instead of relying on
--     implicit _G globals (documents the real dependency; falls back
--     to _G for compatibility with how boot/init.lua loads this file
--     via dofile()).
--   - getFS() can legitimately return nil (e.g. computer.getBootAddress()
--     momentarily unavailable during a hot-swap of the boot drive).
--     Every caller now guards against that instead of crashing with
--     "attempt to index a nil value".
local Lang = {}
local _data    = {}
local _current = "en"

local _component = component or _G.component
local _computer  = computer  or _G.computer

local function getFS()
    if not _computer or not _component then return nil end
    local addr = _computer.getBootAddress()
    if not addr then return nil end
    return _component.proxy(addr)
end

function Lang.load(code)
    code = code or "en"
    local fs = getFS()
    if not fs then return end   -- FIX: boot filesystem transiently unavailable

    local path = "/system/language/" .. code .. ".lang"
    local existsOk, exists = pcall(fs.exists, path)
    if not existsOk or not exists then
        if code ~= "en" then return Lang.load("en") end
        return
    end

    local h = fs.open(path, "r")
    if not h then return end
    local src = fs.read(h, math.huge); fs.close(h)
    if not src then return end

    _data = {}
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        line = line:match("^%s*(.-)%s*$") or ""
        if line ~= "" and not line:match("^#") then
            local k, v = line:match("^([^=]+)=(.*)$")
            if k and v then
                _data[k:match("^%s*(.-)%s*$")] = v:match("^%s*(.-)%s*$")
            end
        end
    end
    _current = code
end

-- Translate key, optional {1}, {2} placeholders
function Lang.t(key, ...)
    local s    = _data[key] or key
    local args = {...}
    if #args > 0 then
        s = s:gsub("{(%d+)}", function(n)
            return tostring(args[tonumber(n)] or "?")
        end)
    end
    return s
end

function Lang.current() return _current end

function Lang.available()
    local fs  = getFS()
    local out = {}
    if not fs then return out end   -- FIX: boot filesystem unavailable
    local ok, list = pcall(function() return fs.list("/system/language/") end)
    if not ok or not list then return out end
    local function add(f)
        local c = (f or ""):match("^(.+)%.lang$")
        if c then table.insert(out, c) end
    end
    if type(list) == "function" then
        for f in list do add(f) end
    else
        for _, f in ipairs(list) do add(f) end
    end
    return out
end

return Lang
