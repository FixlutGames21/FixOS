-- ==========================================================
-- FixOS 3.2.1 - system/programs/settings.lua
-- FIXES:
--   - Update: use event-based async read, no blocking loop
--   - Display: buttons clamped to window width
--   - Display: wallpaper/background color presets
-- ==========================================================

local settings = {}

local function getUI(win, gpuProxy)
    if not win._ui then
        win._ui = dofile("/system/ui.lua")
        win._ui.init(gpuProxy or component.proxy(component.list("gpu")()))
    end
    return win._ui
end

local function L(key, ...) return (_G.Lang and _G.Lang.t(key, ...)) or key end

-- Wallpaper presets: {name, top_color, bottom_color, style}
-- style: "solid", "gradient", "pattern"
local WALLPAPERS = {
    {name="Blue  (Default)",  top=0x0078D7, bot=0x005A9E, style="gradient"},
    {name="Dark  (Night)",    top=0x1A1A2E, bot=0x16213E, style="gradient"},
    {name="Green (Nature)",   top=0x1B5E20, bot=0x2E7D32, style="gradient"},
    {name="Purple(Space)",    top=0x4A148C, bot=0x6A1B9A, style="gradient"},
    {name="Red   (Sunset)",   top=0xB71C1C, bot=0xE64A19, style="gradient"},
    {name="Gray  (Classic)",  top=0x424242, bot=0x616161, style="gradient"},
    {name="Teal  (Ocean)",    top=0x006064, bot=0x00838F, style="gradient"},
    {name="Black (Terminal)", top=0x0C0C0C, bot=0x1A1A1A, style="gradient"},
}

function settings.init(win)
    win.selectedTab  = 1
    win.tabs         = {
        L("settings.system"), L("settings.display"),
        L("settings.update"), L("settings.about"), L("settings.language"),
    }
    win.version      = "3.2.1"
    win.updateStatus = "Ready"
    win.updatePct    = 0
    win.updateRunning = false
    win.elements     = {}
    win._ui          = nil

    local fs = component.proxy(computer.getBootAddress())
    if fs.exists("/version.txt") then
        local h = fs.open("/version.txt", "r")
        if h then
            local v = fs.read(h, math.huge); fs.close(h)
            if v then win.version = v:match("[%d%.]+") or win.version end
        end
    end

    win.resolutions = {
        {w=50,  h=16, name="Tiny    (50x16)"},
        {w=80,  h=25, name="Normal  (80x25)"},
        {w=100, h=30, name="Large  (100x30)"},
        {w=120, h=40, name="Huge   (120x40)"},
        {w=160, h=50, name="Max    (160x50)"},
    }

    local gpu = component.proxy(component.list("gpu")())
    win.currentW, win.currentH = gpu.getResolution()
    win.maxW,     win.maxH     = gpu.maxResolution()

    -- Load current wallpaper index from settings.cfg
    win.wallpaperIdx = 1
    if fs.exists("/settings.cfg") then
        local h = fs.open("/settings.cfg","r")
        if h then
            local d = fs.read(h, math.huge); fs.close(h)
            local wi = d:match("wallpaper=(%d+)")
            if wi then win.wallpaperIdx = tonumber(wi) or 1 end
        end
    end

    -- Async update handle
    win._updateHandle = nil
    win._updateBuf    = {}
    win._updateGotData = false
end

function settings.draw(win, gpu, cx, cy, cw, ch)
    local UI = getUI(win, gpu)
    local T  = UI.Theme
    local P  = UI.PADDING

    gpu.setBackground(T.surface)
    gpu.fill(cx, cy, cw, ch, " ")
    win.elements = {}

    local tabHits = UI.drawTabBar(cx, cy, cw, win.tabs, win.selectedTab)
    for _, h in ipairs(tabHits) do
        h.action = "tab"; table.insert(win.elements, h)
    end

    local contentX = cx + P + 1
    local contentY = cy + 2
    -- FIX: clamp contentW so buttons never exceed window
    local contentW = math.min(cw - (P + 1) * 2, cw - 4)

    -- --------------------------------------------------------
    if win.selectedTab == 1 then
        gpu.setForeground(T.accent); gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, L("settings.sys.info")); contentY = contentY + 2

        local ix, iy, iw = UI.drawCard(contentX, contentY, contentW, 5, L("settings.sys.os"))
        gpu.setForeground(T.textSecondary); gpu.setBackground(T.surfaceAlt)
        gpu.set(ix, iy + 1, "Name:    FixOS")
        gpu.set(ix, iy + 2, "Version: " .. win.version)
        contentY = contentY + 6

        local total  = computer.totalMemory()
        local free   = computer.freeMemory()
        local used   = total - free
        local pct    = used / total
        local mx, my, mw = UI.drawCard(contentX, contentY, contentW, 5, L("settings.sys.memory"))
        gpu.setForeground(T.textSecondary); gpu.setBackground(T.surfaceAlt)
        gpu.set(mx, my + 1, string.format("Used: %dKB / Total: %dKB",
            math.floor(used/1024), math.floor(total/1024)))
        UI.drawProgressBar(mx, my + 3, mw, pct, pct > 0.8 and T.danger or T.success)

    -- --------------------------------------------------------
    elseif win.selectedTab == 2 then
        gpu.setForeground(T.accent); gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, "Display Settings"); contentY = contentY + 2

        -- Resolution card
        local rx, ry, rw = UI.drawCard(contentX, contentY, contentW, 3, "Current Resolution")
        gpu.setForeground(T.textSecondary); gpu.setBackground(T.surfaceAlt)
        gpu.set(rx, ry + 1, string.format("Active: %d x %d", win.currentW, win.currentH))
        contentY = contentY + 4

        gpu.setForeground(T.textSecondary); gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, "Resolution (click to apply + reboot):")
        contentY = contentY + 1

        for _, res in ipairs(win.resolutions) do
            if res.w <= win.maxW and res.h <= win.maxH then
                local isCur = (res.w == win.currentW and res.h == win.currentH)
                -- FIX: button width = contentW, never wider than window
                local btnW = math.min(contentW, cw - 4)
                local btn  = UI.drawButton(contentX, contentY, btnW, 2,
                    res.name, isCur and "accent" or "secondary", true)
                btn.action = "resolution"; btn.res = res
                table.insert(win.elements, btn); contentY = contentY + 3
            end
        end

    -- --------------------------------------------------------
    elseif win.selectedTab == 3 then
        gpu.setForeground(T.accent); gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, L("settings.upd.title")); contentY = contentY + 2

        local vx, vy, vw = UI.drawCard(contentX, contentY, contentW, 4, L("settings.upd.info"))
        gpu.setForeground(T.textSecondary); gpu.setBackground(T.surfaceAlt)
        gpu.set(vx, vy + 1, L("settings.upd.installed") .. ": FixOS " .. win.version)
        gpu.set(vx, vy + 2, L("settings.upd.status") .. ":    " .. tostring(win.updateStatus))
        contentY = contentY + 5

        if win.updatePct > 0 then
            local barColor = win.updatePct >= 1.0 and T.success or T.accent
            UI.drawProgressBar(contentX, contentY, contentW, win.updatePct, barColor)
            contentY = contentY + 2
        end

        local hasNet  = component.isAvailable("internet")
        local running = win.updateRunning
        local label   = running and "Checking..." or L("settings.upd.check")
        local chkBtn  = UI.drawButton(contentX, contentY, math.min(28, contentW), 2,
            label, "accent", hasNet and not running)
        chkBtn.action = "update"; table.insert(win.elements, chkBtn)

        if not hasNet then
            contentY = contentY + 3
            gpu.setForeground(T.danger); gpu.setBackground(T.surface)
            gpu.set(contentX, contentY, "[!!] " .. L("settings.upd.no_internet"))
        end

    -- --------------------------------------------------------
    elseif win.selectedTab == 4 then
        gpu.setForeground(T.accent); gpu.setBackground(T.surface)
        UI.centerText(contentX, contentY,     contentW, "FixOS " .. win.version, T.accent,        T.surface)
        UI.centerText(contentX, contentY + 1, contentW, "Windows 10 Edition",   T.textSecondary, T.surface)
        contentY = contentY + 3
        UI.drawDivider(contentX, contentY, contentW); contentY = contentY + 2
        local rows = {
            {L("settings.about.author"),   "FixlutGames21"},
            {L("settings.about.platform"), "OpenComputers (Minecraft)"},
            {L("settings.about.year"),     "2026"},
            {L("settings.about.ui"),       "ui.lua v3.2.1"},
        }
        for _, row in ipairs(rows) do
            gpu.setForeground(T.textSecondary); gpu.setBackground(T.surface)
            gpu.set(contentX, contentY, row[1])
            gpu.setForeground(T.textPrimary)
            gpu.set(contentX + 14, contentY, row[2]); contentY = contentY + 1
        end

    -- --------------------------------------------------------
    elseif win.selectedTab == 5 then
        -- WALLPAPER + LANGUAGE combined
        gpu.setForeground(T.accent); gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, "Wallpaper"); contentY = contentY + 2

        for i, wp in ipairs(WALLPAPERS) do
            local isCur = (i == (win.wallpaperIdx or 1))
            -- Color swatch (2 chars)
            gpu.setBackground(wp.top); gpu.fill(contentX, contentY, 3, 1, " ")
            gpu.setBackground(wp.bot); gpu.fill(contentX, contentY + 1, 3, 1, " ")
            -- Button next to swatch
            local btnW = math.min(contentW - 5, cw - 9)
            local btn  = UI.drawButton(contentX + 4, contentY, btnW, 2,
                (isCur and "[*] " or "[ ] ") .. wp.name,
                isCur and "accent" or "secondary", true)
            btn.action      = "wallpaper"
            btn.wallpaperIdx = i
            table.insert(win.elements, btn)
            contentY = contentY + 3
            if contentY > cy + ch - 4 then break end
        end

        -- Language section below if space allows
        contentY = contentY + 1
        if contentY < cy + ch - 8 then
            UI.drawDivider(contentX, contentY, contentW); contentY = contentY + 2
            gpu.setForeground(T.accent); gpu.setBackground(T.surface)
            gpu.set(contentX, contentY, L("settings.lang.title")); contentY = contentY + 1
            local curLang = (_G.Lang and _G.Lang.current()) or "en"
            local langs = {
                {code="en", name="English"},
                {code="uk", name="Ukrainska"},
                {code="ru", name="Russkij"},
            }
            for _, entry in ipairs(langs) do
                if contentY < cy + ch - 3 then
                    local isCur = (curLang == entry.code)
                    local btnW  = math.min(contentW, cw - 4)
                    local btn   = UI.drawButton(contentX, contentY, btnW, 2,
                        (isCur and "[*] " or "[ ] ") .. entry.name,
                        isCur and "accent" or "secondary", true)
                    btn.action   = "setlang"; btn.langCode = entry.code
                    table.insert(win.elements, btn); contentY = contentY + 3
                end
            end
        end
    end
end

-- ----------------------------------------------------------
-- CLICK
-- ----------------------------------------------------------
function settings.click(win, clickX, clickY, button)
    local UI = getUI(win)

    for _, elem in ipairs(win.elements) do
        if UI.hitTest(elem, clickX, clickY) then

            if elem.action == "tab" then
                win.selectedTab = elem.index; return true

            elseif elem.action == "resolution" then
                local gpu = component.proxy(component.list("gpu")())
                gpu.setResolution(elem.res.w, elem.res.h)
                settings._saveCfg(win, {
                    resolution = string.format("%dx%d", elem.res.w, elem.res.h)
                })
                computer.shutdown(true); return true

            elseif elem.action == "update" then
                if not win.updateRunning then
                    settings.startUpdateCheck(win)
                end
                return true

            elseif elem.action == "wallpaper" then
                win.wallpaperIdx = elem.wallpaperIdx
                settings._saveCfg(win, {wallpaper = tostring(elem.wallpaperIdx)})
                -- Notify desktop to redraw background
                if _G._desktop_state then
                    _G._desktop_state.wallpaperIdx = elem.wallpaperIdx
                end
                return true

            elseif elem.action == "setlang" then
                settings._saveCfg(win, {language = elem.langCode})
                if _G.Lang then _G.Lang.load(elem.langCode) end
                return true
            end
        end
    end
    return false
end

-- ----------------------------------------------------------
-- tick() - called every frame from desktop (if program has it)
-- Used for async update check
-- ----------------------------------------------------------
function settings.tick(win)
    if not win.updateRunning then return false end
    if not win._updateHandle then
        win.updateRunning  = false
        win.updateStatus   = "Error"
        win.updatePct      = 0
        return true
    end

    -- Try reading a chunk (non-blocking in OC)
    local ok, chunk = pcall(win._updateHandle.read, math.huge)
    if ok and chunk and chunk ~= "" then
        table.insert(win._updateBuf, chunk)
        win._updateGotData = true
        win.updatePct      = 0.7
    elseif win._updateGotData then
        -- EOF after data: parse result
        pcall(win._updateHandle.close)
        win._updateHandle = nil
        local data   = table.concat(win._updateBuf)
        local remote = data:match("[%d%.]+")
        if remote then
            win.updatePct = 1.0
            local L2 = _G.Lang
            if remote == win.version then
                win.updateStatus = L2 and L2.t("settings.upd.up_to_date") or "Up to date"
            else
                win.updateStatus = L2 and L2.t("settings.upd.available", remote) or ("v"..remote.." available")
            end
        else
            win.updateStatus = "Invalid response"
            win.updatePct    = 0
        end
        win.updateRunning  = false
        return true   -- force redraw
    else
        -- Still connecting - bump timeout counter
        win._updateTimeout = (win._updateTimeout or 0) + 1
        if win._updateTimeout > 300 then  -- ~6s at 50ms ticks
            pcall(win._updateHandle.close)
            win._updateHandle = nil
            win.updateStatus  = "Timeout"
            win.updatePct     = 0
            win.updateRunning = false
            return true
        end
    end
    return false
end

-- ----------------------------------------------------------
-- ASYNC UPDATE START
-- ----------------------------------------------------------
function settings.startUpdateCheck(win)
    if not component.isAvailable("internet") then
        win.updateStatus = L("settings.upd.no_internet"); return
    end
    win.updateStatus    = L("settings.upd.checking")
    win.updatePct       = 0.2
    win.updateRunning   = true
    win._updateBuf      = {}
    win._updateGotData  = false
    win._updateTimeout  = 0

    local net = component.internet
    local ok, handle = pcall(net.request,
        "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/version.txt")
    if not ok or not handle then
        win.updateStatus  = L("settings.upd.failed")
        win.updatePct     = 0
        win.updateRunning = false
        return
    end
    win._updateHandle = handle
end

-- ----------------------------------------------------------
-- SAVE SETTINGS HELPER
-- ----------------------------------------------------------
function settings._saveCfg(win, overrides)
    local fs = component.proxy(computer.getBootAddress())
    local cfg = {}

    -- Read existing settings
    if fs.exists("/settings.cfg") then
        local h = fs.open("/settings.cfg","r")
        if h then
            local d = fs.read(h, math.huge); fs.close(h)
            for line in (d.."\n"):gmatch("([^\n]+)\n?") do
                local k, v = line:match("^([^=]+)=(.+)$")
                if k then cfg[k:match("^%s*(.-)%s*$")] = v:match("^%s*(.-)%s*$") end
            end
        end
    end

    -- Apply overrides
    for k, v in pairs(overrides) do cfg[k] = v end

    -- Ensure resolution is in cfg
    if not cfg.resolution then
        local gpu = component.proxy(component.list("gpu")())
        local w, h = gpu.getResolution()
        cfg.resolution = w.."x"..h
    end

    -- Write back
    local h = fs.open("/settings.cfg","w")
    if h then
        for k, v in pairs(cfg) do
            fs.write(h, k.."="..v.."\n")
        end
        fs.close(h)
    end
end

return settings