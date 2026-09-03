-- ==========================================================
-- FixOS 4.0.1 - system/version.lua  (NEW FILE)
-- FIX (Recommended Refactoring):
--   The version string was hardcoded independently in several places
--   and had drifted out of sync:
--     version.txt          -> 4.0.1
--     boot/init.lua         -> 4.0.2 (BSoD text / comments)
--     system/desktop.lua    -> 4.0.1
--     system/programs/terminal.lua ("ver" command) -> 3.2.0
--     system/programs/settings.lua (fallback default) -> 3.2.2
--   This module is the single source of truth: it reads
--   /version.txt from the boot filesystem once and caches the
--   result. Callers should use Version.get() instead of a literal
--   string. Safe to dofile() from anywhere in the FixOS runtime.
-- ==========================================================

local Version = {}
local _cached = nil

function Version.get()
    if _cached then return _cached end

    local ok, result = pcall(function()
        local fs = component.proxy(computer.getBootAddress())
        if not fs then return nil end
        local existsOk, exists = pcall(fs.exists, "/version.txt")
        if not existsOk or not exists then return nil end
        local h = fs.open("/version.txt", "r")
        if not h then return nil end
        local v = fs.read(h, math.huge)
        fs.close(h)
        if not v then return nil end
        return v:match("[%d%.]+")
    end)

    _cached = (ok and result) or "0.0.0"
    return _cached
end

-- Force a re-read next time Version.get() is called (e.g. right after
-- an update was installed and version.txt changed on disk).
function Version.invalidate()
    _cached = nil
end

return Version
