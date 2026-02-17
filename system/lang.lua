-- FixOS 3.2.0 - system/lang.lua
-- Language system loader
local Lang = {}
local _data    = {}
local _current = "en"

local function getFS()
    return component.proxy(computer.getBootAddress())
end

function Lang.load(code)
    code = code or "en"
    local fs   = getFS()
    local path = "/system/language/" .. code .. ".lang"
    if not fs.exists(path) then
        if code ~= "en" then return Lang.load("en") end
        return
    end
    local h = fs.open(path, "r")
    if not h then return end
    local src = fs.read(h, math.huge); fs.close(h)
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
