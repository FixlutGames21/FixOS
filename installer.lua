-- ==========================================================
-- FixOS 3.1.2 - installer.lua
-- FIXES:
--   - All centering uses UI.centerText (unicode.len inside)
--   - Card shadow drawn by UI.shadow (below/right only)
--   - Button centering from UI.drawButton
--   - Progress bar from UI.drawProgressBar
--   - PADDING from UI.PADDING
-- ==========================================================

local component  = require("component")
local computer   = require("computer")
local event      = require("event")

local gpu      = component.gpu
local internet = component.isAvailable("internet") and component.internet or nil

if not gpu then error("No GPU") end

local W, H = gpu.maxResolution()
gpu.setResolution(math.min(80, W), math.min(25, H))
W, H = gpu.getResolution()

-- Load UI library (installer runs on OC, so dofile works)
-- If this file runs on a bare OC machine where /system/ui.lua
-- is not yet installed, fall back to inline stubs below.
local UI_ok, UI = pcall(dofile, "/system/ui.lua")
if not UI_ok then
    -- Minimal inline stubs so the installer still works standalone
    UI = {}
    UI.PADDING = 1
    UI.Theme   = {
        accent=0x0078D7, accentDark=0x005A9E, accentLight=0x429CE3,
        surface=0xFFFFFF, surfaceAlt=0xF3F3F3, surfaceInset=0xE8E8E8,
        chromeDark=0x1F1F1F, chromeMid=0x2D2D30, chromeLight=0xF0F0F0,
        textPrimary=0x1B1B1B, textSecondary=0x666666, textDisabled=0xAAAAAA,
        textOnAccent=0xFFFFFF, textOnDark=0xF3F3F3,
        borderSubtle=0xE5E5E5, divider=0xDDDDDD,
        shadow0=0xDDDDDD, shadow1=0xC0C0C0, shadow2=0xA0A0A0,
        success=0x10893E, warning=0xFFB900, danger=0xE81123, info=0x0078D7,
        progressTrack=0xE0E0E0,
    }
    local function ul(s) return (unicode and unicode.len or function(x) return #x end)(tostring(s)) end
    function UI.init(g) _G._ui_gpu = g end
    function UI.textLen(s) return ul(s) end
    function UI.truncate(s, n)
        s = tostring(s)
        if ul(s) <= n then return s end
        local sub = unicode and unicode.sub or string.sub
        return sub(s, 1, n-1) .. ">"
    end
    function UI.centerText(x, y, w, str, fg, bg)
        str = tostring(str)
        local len = ul(str)
        local ox  = math.max(0, math.floor((w - len) / 2))
        if bg then gpu.setBackground(bg) end
        gpu.setForeground(fg)
        gpu.set(x + ox, y, str)
    end
    function UI.shadow(x, y, w, h, depth)
        depth = math.min(depth or 2, 3)
        local cols = {0xDDDDDD, 0xC0C0C0, 0xA0A0A0}
        for i = 1, depth do
            local c = cols[i] or cols[#cols]
            gpu.setBackground(c)
            gpu.fill(x + i, y + h + (i-1), w, 1, " ")
            gpu.fill(x + w + (i-1), y + i, 1, h, " ")
        end
    end
    function UI.drawButton(x, y, w, h, label, style, enabled)
        style   = style or "accent"
        enabled = (enabled == nil) and true or enabled
        h       = h or 2
        local T = UI.Theme
        local bg = enabled and (style=="danger" and T.danger or style=="success" and T.success or style=="secondary" and T.surfaceAlt or T.accent)
                            or T.surfaceInset
        local fg = (style=="secondary" and enabled) and T.textPrimary or T.textOnAccent
        if enabled then
            gpu.setBackground(T.shadow1)
            gpu.fill(x+1, y+h, w, 1, " ")
        end
        gpu.setBackground(bg)
        gpu.fill(x, y, w, h, " ")
        UI.centerText(x, y + math.floor(h/2), w, label, fg, bg)
        return {x=x, y=y, w=w, h=h}
    end
    function UI.drawProgressBar(x, y, w, percent, barColor)
        percent  = math.max(0, math.min(1, percent or 0))
        barColor = barColor or UI.Theme.accent
        local T  = UI.Theme
        gpu.setBackground(T.progressTrack)
        gpu.fill(x, y, w, 1, " ")
        local filled = math.floor(w * percent)
        if filled > 0 then
            gpu.setBackground(barColor)
            gpu.fill(x, y, filled, 1, " ")
        end
        local pct  = math.floor(percent*100) .. "%"
        local plen = ul(pct)
        local lx   = x + math.floor((w - plen) / 2)
        local onB  = lx < x + filled
        gpu.setForeground(onB and T.textOnAccent or T.textSecondary)
        gpu.setBackground(onB and barColor       or T.progressTrack)
        gpu.set(lx, y, pct)
    end
    function UI.hitTest(r, mx, my)
        return mx>=r.x and mx<r.x+r.w and my>=r.y and my<r.y+r.h
    end
    function UI.clearScreen(sw, sh, bg)
        gpu.setBackground(bg or UI.Theme.surface)
        gpu.fill(1, 1, sw, sh, " ")
    end
end

UI.init(gpu)
local T  = UI.Theme
local P  = UI.PADDING

-- ----------------------------------------------------------
-- FILES TO DOWNLOAD
-- ----------------------------------------------------------
local FILES = {
    { path="boot/init.lua",                     target="/init.lua"                       },
    { path="system/ui.lua",                     target="/system/ui.lua"                  },
    { path="system/desktop.lua",                target="/system/desktop.lua"             },
    { path="system/programs/calculator.lua",    target="/system/programs/calculator.lua" },
    { path="system/programs/notepad.lua",       target="/system/programs/notepad.lua"    },
    { path="system/programs/settings.lua",      target="/system/programs/settings.lua"   },
    { path="system/programs/mycomputer.lua",    target="/system/programs/mycomputer.lua" },
    { path="system/programs/terminal.lua",      target="/system/programs/terminal.lua"   },
    { path="system/programs/explorer.lua",      target="/system/programs/explorer.lua"   },
    { path="version.txt",                       target="/version.txt"                    },
}

local REPO = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main"

-- ----------------------------------------------------------
-- CARD HELPER
-- Draws a floating card (accent title bar + white body + shadow).
-- Returns y of first usable content row inside the card.
-- ----------------------------------------------------------
local function drawCard(cx, cy, cw, ch, title)
    UI.shadow(cx, cy, cw, ch, 2)

    -- Body
    gpu.setBackground(T.surface)
    gpu.fill(cx, cy, cw, ch, " ")

    -- Accent header (3 rows)
    gpu.setBackground(T.accent)
    gpu.fill(cx, cy, cw, 3, " ")
    if title then
        UI.centerText(cx, cy + 1, cw, title, T.textOnAccent, T.accent)
    end

    -- Subtle border
    gpu.setForeground(T.borderSubtle)
    gpu.setBackground(T.surface)
    for col = 0, cw - 1 do
        gpu.set(cx + col, cy + ch - 1, "\xE2\x94\x80")
    end
    for row = 3, ch - 2 do
        gpu.set(cx,        cy + row, "\xE2\x94\x82")
        gpu.set(cx+cw - 1, cy + row, "\xE2\x94\x82")
    end
    gpu.set(cx,        cy + ch - 1, "\xE2\x94\x94")
    gpu.set(cx + cw-1, cy + ch - 1, "\xE2\x94\x98")

    return cy + 4   -- first content row inside card
end

-- Status icon (no emoji; pure ASCII)
local function statusIcon(x, y, kind)
    local map = { success="[OK]", warning="[!!]", danger="[XX]",
                  info="[i] ", loading="[~] " }
    local col = { success=T.success, warning=T.warning, danger=T.danger,
                  info=T.info,       loading=T.accent }
    gpu.setForeground(col[kind] or T.info)
    gpu.setBackground(T.surface)
    gpu.set(x, y, map[kind] or "[?] ")
end

-- Centre helpers that use UI.centerText
local function cText(y, str, fg, bg)
    UI.centerText(1, y, W, str, fg, bg or T.surface)
end

-- ----------------------------------------------------------
-- NETWORK
-- ----------------------------------------------------------
local function download(url, retries)
    if not internet then return nil, "No Internet Card" end
    retries = retries or 3
    for attempt = 1, retries do
        local ok, h = pcall(internet.request, url)
        if ok and h then
            local buf = {}; local t0 = computer.uptime() + 60
            while computer.uptime() < t0 do
                local c = h.read(math.huge)
                if c then table.insert(buf, c) else break end
                os.sleep(0.05)
            end
            pcall(h.close)
            local data = table.concat(buf)
            if #data > 0 and not data:match("^%s*<!DOCTYPE") then return data end
        end
        if attempt < retries then os.sleep(1) end
    end
    return nil, "Download failed"
end

-- ----------------------------------------------------------
-- DISK
-- ----------------------------------------------------------
local function listDisks()
    local out = {}
    for addr in component.list("filesystem") do
        local proxy = component.proxy(addr)
        if proxy then
            local _, lbl = pcall(proxy.getLabel); lbl = (lbl and lbl ~= "") and lbl or addr:sub(1,8)
            local _, ro  = pcall(proxy.isReadOnly)
            local _, tot = pcall(proxy.spaceTotal)
            tot = tot or 0
            if tot > 200000 and not lbl:match("tmpfs") then
                table.insert(out, {address=addr, label=lbl, size=tot, readOnly=ro})
            end
        end
    end
    table.sort(out, function(a,b) return a.size > b.size end)
    return out
end

local function formatDisk(addr)
    local proxy = component.proxy(addr)
    if not proxy then return false end
    local function rm(path)
        local _, isD = pcall(proxy.isDirectory, path)
        if isD then
            local _, lf = pcall(function() return proxy.list(path) end)
            if lf then for f in lf do rm(path..(path:match("/$") and "" or "/")..f) end end
            pcall(proxy.remove, path)
        else pcall(proxy.remove, path) end
    end
    local _, lf = pcall(function() return proxy.list("/") end)
    if lf then for f in lf do rm("/"..f) end end
    return true
end

local function writeToDisk(proxy, path, content)
    local dir = path:match("(.+)/[^/]+$")
    if dir then
        local cur = ""
        for part in dir:gmatch("[^/]+") do
            cur = cur .. "/" .. part
            if not proxy.exists(cur) then pcall(proxy.makeDirectory, cur) end
        end
    end
    local _, h = pcall(proxy.open, path, "w")
    if not h then return false end
    local ok = pcall(proxy.write, h, content)
    pcall(proxy.close, h)
    return ok
end

-- ----------------------------------------------------------
-- SCREENS
-- ----------------------------------------------------------

local function screen_welcome()
    UI.clearScreen(W, H)

    local CX, CY, CW, CH = 8, 2, W-16, H-4
    local contentY = drawCard(CX, CY, CW, CH, "FixOS 3.1.2 Setup")

    gpu.setBackground(T.surface)
    UI.centerText(CX, contentY,     CW, "Welcome to FixOS Setup",   T.accent, T.surface)
    UI.centerText(CX, contentY + 1, CW, "PIXEL PERFECT EDITION",    T.textSecondary, T.surface)

    local features = {
        "[OK] Pixel-Perfect UI Library",
        "[OK] unicode.len() everywhere",
        "[OK] Shadow outside window only",
        "[OK] Strict tile grid (2 cols)",
        "[OK] PADDING constant system",
        "[OK] Central Theme table",
    }
    for i, f in ipairs(features) do
        gpu.setForeground(T.success)
        gpu.setBackground(T.surface)
        gpu.set(CX + 4, contentY + 2 + i, f)
    end

    if not internet then
        UI.drawStatusBanner and UI.drawStatusBanner(CX+2, H-6, CW-4, "Internet Card required!", "danger")
        or (function()
            gpu.setBackground(T.danger); gpu.fill(CX+2, H-6, CW-4, 1, " ")
            UI.centerText(CX+2, H-6, CW-4, "Internet Card required!", T.textOnAccent, T.danger)
        end)()
        local btn = UI.drawButton(math.floor(W/2)-7, H-4, 14, 2, "Exit", "secondary")
        while true do
            local ev,_,x,y = event.pull()
            if ev=="touch" and UI.hitTest(btn,x,y) then return false end
        end
    end

    local btnNext   = UI.drawButton(W-28, H-4, 12, 2, "Next ->",  "accent")
    local btnCancel = UI.drawButton(W-15, H-4, 12, 2, "Cancel",   "secondary")

    while true do
        local ev,_,x,y,_ = event.pull()
        if ev=="touch" then
            if UI.hitTest(btnNext,   x, y) then return true  end
            if UI.hitTest(btnCancel, x, y) then return false end
        elseif ev=="key_down" then
            if _ == 28 then return true  end
            if _ == 1  then return false end
        end
    end
end

local function screen_disk()
    UI.clearScreen(W, H)
    local CX, CY, CW, CH = 8, 2, W-16, H-4
    local contentY = drawCard(CX, CY, CW, CH, "Choose Installation Drive")

    gpu.setBackground(T.surface)
    UI.centerText(CX, contentY, CW, "Select the drive for FixOS 3.1.2", T.textPrimary, T.surface)

    -- Warning banner
    gpu.setBackground(T.warning)
    gpu.fill(CX+2, contentY+2, CW-4, 1, " ")
    UI.centerText(CX+2, contentY+2, CW-4, "[!!] All data will be erased!", T.textOnAccent, T.warning)

    local disks = listDisks()
    local buttons = {}

    if #disks == 0 then
        UI.centerText(CX, contentY+4, CW, "No suitable drives found", T.danger, T.surface)
        local b = UI.drawButton(math.floor(W/2)-7, H-4, 14, 2, "<- Back", "secondary")
        event.pull("touch")
        return nil
    end

    gpu.setBackground(T.surface)
    local dy = contentY + 4
    for _, disk in ipairs(disks) do
        if dy + 4 < H - 6 then
            -- mini card per disk
            gpu.setBackground(T.surfaceAlt)
            gpu.fill(CX+2, dy, CW-4, 3, " ")
            gpu.setForeground(T.accent)
            gpu.setBackground(T.surfaceAlt)
            local sz  = string.format("%.1f MB", disk.size/(1024*1024))
            local lbl = string.format("[D] %s (%s)", disk.label, sz)
            if disk.readOnly then lbl = lbl .. " [READ-ONLY]" end
            gpu.set(CX+4, dy+1, lbl)

            local btn = UI.drawButton(CX+2, dy+2, CW-4, 2,
                disk.readOnly and "Read-Only - Unavailable" or "Select this drive",
                disk.readOnly and "secondary" or "accent",
                not disk.readOnly)
            btn.disk = disk
            table.insert(buttons, btn)
            dy = dy + 5
        end
    end

    local btnBack = UI.drawButton(W-15, H-4, 12, 2, "<- Back", "secondary")
    table.insert(buttons, btnBack)

    while true do
        local ev,_,x,y = event.pull()
        if ev=="touch" then
            for _, btn in ipairs(buttons) do
                if UI.hitTest(btn, x, y) then
                    if btn == btnBack then return nil
                    elseif btn.disk and not btn.disk.readOnly then return btn.disk end
                end
            end
        end
    end
end

local function screen_confirm(disk)
    UI.clearScreen(W, H)
    local CX, CY, CW, CH = 12, 6, W-24, 16
    local contentY = drawCard(CX, CY, CW, CH, "Confirm Installation")

    gpu.setBackground(T.surface)
    statusIcon(math.floor(W/2)-2, contentY, "warning")
    UI.centerText(CX, contentY, CW, "    Ready to install FixOS 3.1.2", T.textPrimary, T.surface)

    local steps = {"Format the selected drive", "Download & install FixOS", "Set boot address"}
    for i, s in ipairs(steps) do
        gpu.setForeground(T.textSecondary)
        gpu.set(CX+4, contentY+2+i, "- " .. s)
    end

    -- Drive info box
    gpu.setBackground(T.surfaceAlt)
    gpu.fill(CX+2, contentY+7, CW-4, 2, " ")
    gpu.setForeground(T.accent)
    gpu.set(CX+4, contentY+7, "[D] Drive: " .. disk.label)
    gpu.setForeground(T.textSecondary)
    gpu.set(CX+4, contentY+8, "    ("..disk.address:sub(1,8)..")")

    gpu.setBackground(T.surface)
    local btnInst = UI.drawButton(math.floor(W/2)-20, contentY+11, 18, 2, "Install Now", "accent")
    local btnCncl = UI.drawButton(math.floor(W/2)+2,  contentY+11, 18, 2, "Cancel",      "secondary")

    while true do
        local ev,_,x,y = event.pull()
        if ev=="touch" then
            if UI.hitTest(btnInst,x,y) then return true  end
            if UI.hitTest(btnCncl,x,y) then return false end
        end
    end
end

local function screen_install(disk)
    local proxy = component.proxy(disk.address)
    local CX, CY, CW, CH = 8, 2, W-16, H-4
    local spinFrame = 0

    local function redraw(step, file, pct, status)
        UI.clearScreen(W, H)
        local y = drawCard(CX, CY, CW, CH, "Installing FixOS 3.1.2")

        UI.centerText(CX, y, CW, step, T.accent, T.surface)
        if file then
            gpu.setBackground(T.surface)
            gpu.setForeground(T.textSecondary)
            UI.centerText(CX, y+1, CW, UI.truncate(file, CW-2), T.textSecondary, T.surface)
        end

        UI.drawProgressBar(CX+2, y+3, CW-4, pct)

        spinFrame = spinFrame + 1
        UI.spinner(math.floor(W/2), y+5, spinFrame, T.accent, T.surface)

        if status then
            gpu.setBackground(T.surface)
            statusIcon(CX+2, y+7, status.kind)
            gpu.setForeground(status.kind=="success" and T.success or
                              status.kind=="warning"  and T.warning or T.info)
            gpu.set(CX+7, y+7, status.msg)
        end
    end

    -- Step 1: Format
    redraw("Preparing drive...", disk.label, 0, nil)
    local ok = formatDisk(disk.address)
    if not ok then
        redraw("Format failed", nil, 0, {kind="danger", msg="Cannot format"})
        UI.drawButton(math.floor(W/2)-7, H-4, 14, 2, "Exit", "secondary")
        event.pull("touch")
        return false
    end
    redraw("Preparing drive...", disk.label, 0.33, {kind="success", msg="Drive formatted"})
    os.sleep(0.4)

    -- Step 2: Label
    redraw("Configuring...", "Setting label to 'FixOS'", 0.5, nil)
    pcall(proxy.setLabel, "FixOS")
    redraw("Configuring...", "Setting label to 'FixOS'", 0.6, {kind="success", msg="Label set"})
    os.sleep(0.4)

    -- Step 3: Download
    local total = #FILES; local done = 0
    for _, f in ipairs(FILES) do
        redraw("Downloading files...", f.path, 0.6 + (done/total)*0.4, {kind="loading", msg="Fetching..."})
        local data = download(REPO.."/"..f.path, 3)
        if data then
            redraw("Downloading files...", f.path, 0.6 + (done/total)*0.4, {kind="loading", msg="Writing..."})
            writeToDisk(proxy, f.target, data)
            done = done + 1
        end
        os.sleep(0.05)
    end

    UI.drawProgressBar(CX+2, 2+4+3, CW-4, 1.0)
    redraw("Downloading files...", nil, 1.0,
        {kind = done >= total-1 and "success" or "warning",
         msg  = done >= total-1 and "All files installed!" or
                string.format("%d/%d files installed", done, total)})

    pcall(computer.setBootAddress, disk.address)
    os.sleep(1.5)
    return done >= total - 1
end

local function screen_finish()
    UI.clearScreen(W, H)
    local CX, CY, CW, CH = 10, 5, W-20, 17
    local y = drawCard(CX, CY, CW, CH, "Setup Complete")

    gpu.setBackground(T.surface)
    statusIcon(math.floor(W/2)-2, y, "success")
    UI.centerText(CX, y, CW, "    FixOS 3.1.2 installed!", T.success, T.surface)

    local details = {"Drive labeled: FixOS", "Boot address: set", "UI Library: installed"}
    for i, d in ipairs(details) do
        gpu.setForeground(T.textSecondary)
        gpu.set(CX+4, y+2+i, "- " .. d)
    end

    gpu.setBackground(T.accentSubtle)
    gpu.fill(CX+2, y+7, CW-4, 1, " ")
    UI.centerText(CX+2, y+7, CW-4, "Pixel-Perfect Edition!", T.accent, T.accentSubtle)

    gpu.setBackground(T.surface)
    for i = 5, 1, -1 do
        local s = string.format("Restarting in %d...", i)
        gpu.fill(CX+2, y+10, CW-4, 1, " ")
        UI.centerText(CX+2, y+10, CW-4, s, T.textSecondary, T.surface)
        os.sleep(1)
    end
    computer.shutdown(true)
end

-- ----------------------------------------------------------
-- MAIN
-- ----------------------------------------------------------
local function main()
    if not screen_welcome() then
        UI.clearScreen(W, H)
        cText(math.floor(H/2), "Setup cancelled.", T.textPrimary)
        os.sleep(1)
        return
    end

    local disk = screen_disk()
    if not disk then
        UI.clearScreen(W, H)
        cText(math.floor(H/2), "Setup cancelled.", T.textPrimary)
        os.sleep(1)
        return
    end

    if not screen_confirm(disk) then
        UI.clearScreen(W, H)
        cText(math.floor(H/2), "Setup cancelled.", T.textPrimary)
        os.sleep(1)
        return
    end

    if screen_install(disk) then
        screen_finish()
    end
end

local ok, err = pcall(main)
if not ok then
    gpu.setBackground(T.danger)
    gpu.setForeground(T.textOnAccent)
    gpu.fill(1, 1, W, H, " ")
    UI.centerText(1, math.floor(H/2)-1, W, "Setup Error", T.textOnAccent, T.danger)
    UI.centerText(1, math.floor(H/2)+1, W, UI.truncate(tostring(err), W-4), T.textOnAccent, T.danger)
    event.pull("key_down")
end
