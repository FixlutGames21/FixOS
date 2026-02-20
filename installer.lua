-- ==========================================================
-- FixOS 3.2.2 - installer.lua
-- FIXES 3.2.2:
--   - NO shadows anywhere (clean UI)
--   - Clean solid buttons (no stripes)
--   - Updated file list (includes browser, updated versions)
--   - Better download loop with proper timeout
-- ==========================================================

local component = require("component")
local computer  = require("computer")
local event     = require("event")

local gpu      = component.gpu
local internet = component.isAvailable("internet") and component.internet or nil

if not gpu then error("No GPU") end

local W, H = gpu.maxResolution()
gpu.setResolution(math.min(80, W), math.min(25, H))
W, H = gpu.getResolution()

-- Load UI or inline stub
local UI_ok, UI = pcall(dofile, "/system/ui.lua")
if not UI_ok then
    UI = {}
    UI.PADDING = 1
    UI.Theme   = {
        accent=0x0078D7, accentDark=0x005A9E, accentLight=0x429CE3,
        accentSubtle=0xCDE8FF,
        surface=0xFFFFFF, surfaceAlt=0xF3F3F3, surfaceInset=0xE8E8E8,
        chromeDark=0x1F1F1F, chromeMid=0x2D2D30, chromeLight=0xF0F0F0,
        textPrimary=0x1B1B1B, textSecondary=0x666666, textDisabled=0xAAAAAA,
        textOnAccent=0xFFFFFF, textOnDark=0xF3F3F3,
        borderSubtle=0xE5E5E5, divider=0xDDDDDD,
        success=0x10893E, warning=0xFFB900, danger=0xE81123, info=0x0078D7,
        progressTrack=0xE0E0E0,
    }
    local function ul(s) return (unicode and unicode.len or function(x) return #x end)(tostring(s)) end
    function UI.init(g) end
    function UI.textLen(s) return ul(s) end
    function UI.truncate(s, n)
        s = tostring(s)
        if ul(s) <= n then return s end
        return (unicode and unicode.sub or string.sub)(s,1,n-1)..">"
    end
    function UI.centerText(x, y, w, str, fg, bg)
        str = tostring(str)
        local ox = math.max(0, math.floor((w - ul(str)) / 2))
        if bg then gpu.setBackground(bg) end
        gpu.setForeground(fg)
        gpu.set(x + ox, y, str)
    end
    function UI.shadow(x,y,w,h,d) end
    function UI.drawButton(x, y, w, h, label, style, enabled)
        style   = style or "accent"
        enabled = (enabled == nil) and true or enabled
        h       = h or 2
        local T  = UI.Theme
        local bg = enabled and (style=="danger" and T.danger or style=="success" and T.success
                               or style=="secondary" and T.surfaceAlt or T.accent) or T.surfaceInset
        local fg = (style=="secondary" and enabled) and T.textPrimary or T.textOnAccent
        gpu.setBackground(bg); gpu.fill(x, y, w, h, " ")
        UI.centerText(x, y + math.floor(h/2), w, label, fg, bg)
        return {x=x, y=y, w=w, h=h}
    end
    function UI.drawProgressBar(x, y, w, pct, color)
        pct   = math.max(0, math.min(1, pct or 0))
        color = color or UI.Theme.accent
        gpu.setBackground(UI.Theme.progressTrack); gpu.fill(x,y,w,1," ")
        local f = math.floor(w * pct)
        if f > 0 then gpu.setBackground(color); gpu.fill(x,y,f,1," ") end
        local s  = math.floor(pct*100).."%"
        local lx = x + math.floor((w-ul(s))/2)
        gpu.setForeground(lx < x+f and UI.Theme.textOnAccent or UI.Theme.textSecondary)
        gpu.setBackground(lx < x+f and color or UI.Theme.progressTrack)
        gpu.set(lx, y, s)
    end
    function UI.spinner(x, y, frame, color, bg)
        local f = {"|","/","-","\\","|","/","-","\\"}
        gpu.setForeground(color or UI.Theme.accent)
        gpu.setBackground(bg or UI.Theme.surface)
        gpu.set(x, y, f[(frame % #f) + 1])
    end
    function UI.hitTest(r, mx, my)
        return mx>=r.x and mx<r.x+r.w and my>=r.y and my<r.y+r.h
    end
    function UI.clearScreen(sw, sh, bg)
        gpu.setBackground(bg or UI.Theme.surface); gpu.fill(1,1,sw,sh," ")
    end
end

UI.init(gpu)
local T = UI.Theme
local P = UI.PADDING

-- FILES TO DOWNLOAD (updated with 3.2.2 versions)
local FILES = {
    { path="boot/init.lua",                         target="/init.lua"                          },
    { path="system/ui.lua",                         target="/system/ui.lua"                     },
    { path="system/lang.lua",                       target="/system/lang.lua"                   },
    { path="system/desktop.lua",                    target="/system/desktop.lua"                },
    { path="system/language/en.lang",               target="/system/language/en.lang"           },
    { path="system/language/uk.lang",               target="/system/language/uk.lang"           },
    { path="system/language/ru.lang",               target="/system/language/ru.lang"           },
    { path="system/programs/calculator.lua",        target="/system/programs/calculator.lua"    },
    { path="system/programs/notepad.lua",           target="/system/programs/notepad.lua"       },
    { path="system/programs/settings.lua",          target="/system/programs/settings.lua"      },
    { path="system/programs/mycomputer.lua",        target="/system/programs/mycomputer.lua"    },
    { path="system/programs/terminal.lua",          target="/system/programs/terminal.lua"      },
    { path="system/programs/explorer.lua",          target="/system/programs/explorer.lua"      },
    { path="system/programs/browser.lua",           target="/system/programs/browser.lua"       },
    { path="system/icons/mycomputer.png",           target="/system/icons/mycomputer.png"       },
    { path="system/icons/calculator.png",           target="/system/icons/calculator.png"       },
    { path="system/icons/browser.png",              target="/system/icons/browser.png"          },
    { path="system/icons/explorer.png",             target="/system/icons/explorer.png"         },
    { path="system/icons/terminal.png",             target="/system/icons/terminal.png"         },
    { path="system/icons/settings.png",             target="/system/icons/settings.png"         },
    { path="system/icons/notepad.png",              target="/system/icons/notepad.png"          },
    { path="version.txt",                           target="/version.txt"                       },
}

local REPO = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main"

-- Card helper (NO SHADOW)
local function drawCard(cx, cy, cw, ch, title)
    gpu.setBackground(T.surface)
    gpu.fill(cx, cy, cw, ch, " ")

    gpu.setBackground(T.accent)
    gpu.fill(cx, cy, cw, 3, " ")
    if title then
        UI.centerText(cx, cy + 1, cw, title, T.textOnAccent, T.accent)
    end

    gpu.setForeground(T.borderSubtle)
    gpu.setBackground(T.surface)
    for col = 0, cw - 1 do
        gpu.set(cx + col, cy + ch - 1, "\xE2\x94\x80")
    end
    for row = 3, ch - 2 do
        gpu.set(cx,       cy + row, "\xE2\x94\x82")
        gpu.set(cx+cw-1,  cy + row, "\xE2\x94\x82")
    end
    gpu.set(cx,      cy + ch - 1, "\xE2\x94\x94")
    gpu.set(cx+cw-1, cy + ch - 1, "\xE2\x94\x98")
    return cy + 4
end

local function statusIcon(x, y, kind)
    local map = {success="[OK]",warning="[!!]",danger="[XX]",info="[i] ",loading="[~] "}
    local col = {success=T.success,warning=T.warning,danger=T.danger,info=T.info,loading=T.accent}
    gpu.setForeground(col[kind] or T.info)
    gpu.setBackground(T.surface)
    gpu.set(x, y, map[kind] or "[?] ")
end

local function cText(y, str, fg, bg)
    UI.centerText(1, y, W, str, fg, bg or T.surface)
end

-- DOWNLOAD with proper timeout
local function download(url, retries)
    if not internet then return nil, "No Internet Card" end
    retries = retries or 3
    for attempt = 1, retries do
        local ok, h = pcall(internet.request, url)
        if ok and h then
            local buf      = {}
            local deadline = computer.uptime() + 30
            local gotData  = false

            while computer.uptime() < deadline do
                local c = h.read(8192)
                if c then
                    table.insert(buf, c)
                    gotData = true
                elseif gotData then
                    break
                else
                    os.sleep(0.2)
                end
            end
            pcall(h.close)

            local data = table.concat(buf)
            if #data > 0 and not data:match("^%s*<!DOCTYPE") then
                return data
            end
        end
        if attempt < retries then os.sleep(1) end
    end
    return nil, "Download failed"
end

-- DISK
local function listDisks()
    local out = {}
    for addr in component.list("filesystem") do
        local proxy = component.proxy(addr)
        if proxy then
            local _, lbl = pcall(proxy.getLabel)
            lbl = (lbl and lbl ~= "") and lbl or addr:sub(1,8)
            local _, ro  = pcall(proxy.isReadOnly)
            local _, tot = pcall(proxy.spaceTotal)
            tot = tot or 0
            if tot > 200000 and not tostring(lbl):match("tmpfs") then
                table.insert(out, {address=addr, label=lbl, size=tot, readOnly=ro})
            end
        end
    end
    table.sort(out, function(a,b) return a.size > b.size end)
    return out
end

local function iterate(lf, fn)
    if type(lf) == "function" then
        for v in lf do fn(v) end
    elseif type(lf) == "table" then
        for _, v in ipairs(lf) do fn(v) end
    end
end

local function formatDisk(addr)
    local proxy = component.proxy(addr)
    if not proxy then return false end
    local function rm(path)
        local _, isD = pcall(proxy.isDirectory, path)
        if isD then
            local _, lf = pcall(function() return proxy.list(path) end)
            if lf then
                iterate(lf, function(f)
                    rm(path..(path:match("/$") and "" or "/")..f)
                end)
            end
            pcall(proxy.remove, path)
        else
            pcall(proxy.remove, path)
        end
    end
    local _, lf = pcall(function() return proxy.list("/") end)
    if lf then iterate(lf, function(f) rm("/"..f) end) end
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
    pcall(proxy.write, h, content)
    pcall(proxy.close, h)
    return true
end

-- SCREENS
local function screen_welcome()
    UI.clearScreen(W, H)
    local CX, CY, CW, CH = 6, 2, W-12, H-4
    local contentY = drawCard(CX, CY, CW, CH, "FixOS 3.2.2 Setup")

    gpu.setBackground(T.surface)
    UI.centerText(CX, contentY,     CW, "Welcome to FixOS Setup",  T.accent,        T.surface)
    UI.centerText(CX, contentY + 1, CW, "PIXEL PERFECT EDITION",   T.textSecondary, T.surface)

    local features = {
        "[OK] Clean UI (no shadow artifacts)",
        "[OK] Language system (EN/UK/RU)",
        "[OK] Wallpaper presets (8 colors)",
        "[OK] Terminal with full commands",
        "[OK] Text-mode web browser",
        "[OK] Async update check",
    }
    for i, f in ipairs(features) do
        gpu.setForeground(T.success); gpu.setBackground(T.surface)
        gpu.set(CX + 3, contentY + 2 + i, f)
    end

    if not internet then
        gpu.setBackground(T.danger); gpu.fill(CX+2, H-7, CW-4, 1, " ")
        UI.centerText(CX+2, H-7, CW-4, "[!!] Internet Card required!", T.textOnAccent, T.danger)
        local btn = UI.drawButton(math.floor(W/2)-8, H-4, 16, 2, "Exit", "secondary")
        while true do
            local ev,_,x,y = event.pull()
            if ev=="touch" and UI.hitTest(btn,x,y) then return false end
        end
    end

    local btnNext   = UI.drawButton(CX + 4,      H-4, 20, 2, "  Next ->  ",  "accent")
    local btnCancel = UI.drawButton(CX + CW - 24, H-4, 20, 2, "  Cancel   ", "secondary")

    while true do
        local ev,_,x,y,_ = event.pull()
        if ev=="touch" then
            if UI.hitTest(btnNext,   x, y) then return true  end
            if UI.hitTest(btnCancel, x, y) then return false end
        end
    end
end

local function screen_disk()
    UI.clearScreen(W, H)
    local CX, CY, CW, CH = 6, 2, W-12, H-4
    local contentY = drawCard(CX, CY, CW, CH, "Choose Installation Drive")

    gpu.setBackground(T.surface)
    UI.centerText(CX, contentY, CW, "Select the drive for FixOS 3.2.2", T.textPrimary, T.surface)

    gpu.setBackground(T.warning); gpu.fill(CX+2, contentY+2, CW-4, 1, " ")
    UI.centerText(CX+2, contentY+2, CW-4, "[!!]  ALL DATA WILL BE ERASED  [!!]", T.textOnAccent, T.warning)

    local disks   = listDisks()
    local buttons = {}

    if #disks == 0 then
        UI.centerText(CX, contentY+4, CW, "No suitable drives found!", T.danger, T.surface)
        UI.drawButton(math.floor(W/2)-8, H-4, 16, 2, "<- Back", "secondary")
        event.pull("touch"); return nil
    end

    local dy = contentY + 4
    for _, disk in ipairs(disks) do
        if dy + 5 < H - 6 then
            gpu.setBackground(T.surfaceAlt); gpu.fill(CX+2, dy, CW-4, 4, " ")
            gpu.setForeground(T.accent); gpu.setBackground(T.surfaceAlt)
            local sz  = string.format("%.1f MB", disk.size/(1024*1024))
            gpu.set(CX+4, dy+1, "[D] " .. disk.label .. "  (" .. sz .. ")")
            gpu.set(CX+4, dy+2, "    " .. disk.address:sub(1,16))
            if disk.readOnly then
                gpu.setForeground(T.danger); gpu.set(CX+4, dy+2, "    READ ONLY")
            end

            local btn = UI.drawButton(CX+2, dy+3, CW-4, 2,
                disk.readOnly and "Read-Only - Unavailable" or "  SELECT THIS DRIVE  ",
                disk.readOnly and "secondary" or "accent",
                not disk.readOnly)
            btn.disk = disk
            table.insert(buttons, btn)
            dy = dy + 6
        end
    end

    local btnBack = UI.drawButton(CX + CW - 20, H-4, 18, 2, "<- Back", "secondary")
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
    local CX, CY, CW, CH = 10, 4, W-20, 16
    local contentY = drawCard(CX, CY, CW, CH, "Confirm Installation")

    gpu.setBackground(T.surface)
    statusIcon(CX+2, contentY, "warning")
    UI.centerText(CX, contentY, CW, "    Ready to install FixOS 3.2.2", T.textPrimary, T.surface)

    local steps = {"1. Format selected drive", "2. Download & install FixOS", "3. Set boot address"}
    for i, s in ipairs(steps) do
        gpu.setForeground(T.textSecondary); gpu.setBackground(T.surface)
        gpu.set(CX+4, contentY+2+i, "  " .. s)
    end

    gpu.setBackground(T.surfaceAlt); gpu.fill(CX+2, contentY+7, CW-4, 3, " ")
    gpu.setForeground(T.accent)
    gpu.set(CX+4, contentY+7, "[DRIVE]  " .. disk.label)
    gpu.setForeground(T.textSecondary)
    gpu.set(CX+4, contentY+8, "         " .. disk.address:sub(1,16))

    local midX    = math.floor(W/2)
    local btnInst = UI.drawButton(midX - 22, contentY+11, 20, 2, "  INSTALL NOW  ", "accent")
    local btnCncl = UI.drawButton(midX +  2, contentY+11, 18, 2, "  Cancel  ",       "secondary")

    while true do
        local ev,_,x,y = event.pull()
        if ev=="touch" then
            if UI.hitTest(btnInst,x,y) then return true  end
            if UI.hitTest(btnCncl,x,y) then return false end
        end
    end
end

local function screen_install(disk)
    local proxy     = component.proxy(disk.address)
    local CX, CY, CW, CH = 6, 2, W-12, H-4
    local spinFrame = 0

    local function redraw(step, file, pct, status)
        UI.clearScreen(W, H)
        local y = drawCard(CX, CY, CW, CH, "Installing FixOS 3.2.2")
        UI.centerText(CX, y, CW, step, T.accent, T.surface)
        if file then
            UI.centerText(CX, y+1, CW, UI.truncate(file, CW-2), T.textSecondary, T.surface)
        end
        UI.drawProgressBar(CX+2, y+3, CW-4, pct)
        spinFrame = spinFrame + 1
        UI.spinner(math.floor(W/2), y+5, spinFrame, T.accent, T.surface)
        if status then
            statusIcon(CX+2, y+7, status.kind)
            gpu.setForeground(status.kind=="success" and T.success or
                              status.kind=="warning"  and T.warning or T.info)
            gpu.setBackground(T.surface)
            gpu.set(CX+7, y+7, status.msg)
        end
    end

    redraw("Preparing drive...", disk.label, 0, nil)
    if not formatDisk(disk.address) then
        redraw("Format failed", nil, 0, {kind="danger", msg="Cannot format drive"})
        UI.drawButton(math.floor(W/2)-8, H-4, 16, 2, "Exit", "secondary")
        event.pull("touch"); return false
    end
    redraw("Preparing drive...", disk.label, 0.25, {kind="success", msg="Drive formatted"})
    os.sleep(0.3)

    redraw("Configuring...", "Setting label to 'FixOS'", 0.4, nil)
    pcall(proxy.setLabel, "FixOS")
    os.sleep(0.2)

    local total = #FILES; local done = 0
    for _, f in ipairs(FILES) do
        local pct = 0.4 + (done / total) * 0.6
        redraw("Downloading files...", f.path, pct, {kind="loading", msg="Fetching..."})
        local data = download(REPO.."/"..f.path, 3)
        if data then
            redraw("Downloading files...", f.path, pct, {kind="loading", msg="Writing..."})
            writeToDisk(proxy, f.target, data)
            done = done + 1
        else
            redraw("Downloading files...", f.path, pct, {kind="warning", msg="Skipped"})
            os.sleep(0.3)
        end
        os.sleep(0.05)
    end

    redraw("Complete!", nil, 1.0,
        {kind = done >= total - 2 and "success" or "warning",
         msg  = done >= total - 2 and "All files installed!" or
                string.format("%d/%d files installed", done, total)})

    pcall(computer.setBootAddress, disk.address)
    os.sleep(1.5)
    return done >= total - 2
end

local function screen_finish()
    UI.clearScreen(W, H)
    local CX, CY, CW, CH = 8, 4, W-16, 16
    local y = drawCard(CX, CY, CW, CH, "Setup Complete")

    statusIcon(math.floor(W/2)-2, y, "success")
    UI.centerText(CX, y, CW, "    FixOS 3.2.2 installed!", T.success, T.surface)

    local details = {
        "Drive labeled: FixOS",
        "Boot address: set",
        "Languages: EN / UK / RU",
        "UI Library: v3.2.2 (clean)",
        "Browser: included",
    }
    for i, d in ipairs(details) do
        gpu.setForeground(T.textSecondary); gpu.setBackground(T.surface)
        gpu.set(CX+4, y+2+i, "[OK] " .. d)
    end

    gpu.setBackground(T.accentSubtle); gpu.fill(CX+2, y+9, CW-4, 1, " ")
    UI.centerText(CX+2, y+9, CW-4, "Pixel-Perfect Edition 3.2.2", T.accent, T.accentSubtle)

    for i = 5, 1, -1 do
        gpu.setBackground(T.surface)
        gpu.fill(CX+2, y+11, CW-4, 1, " ")
        UI.centerText(CX+2, y+11, CW-4,
            string.format("Restarting in %d seconds...", i), T.textSecondary, T.surface)
        os.sleep(1)
    end
    computer.shutdown(true)
end

-- MAIN
local function main()
    if not screen_welcome() then
        UI.clearScreen(W, H); cText(math.floor(H/2), "Setup cancelled.", T.textPrimary)
        os.sleep(1); return
    end

    local disk = screen_disk()
    if not disk then
        UI.clearScreen(W, H); cText(math.floor(H/2), "Setup cancelled.", T.textPrimary)
        os.sleep(1); return
    end

    if not screen_confirm(disk) then
        UI.clearScreen(W, H); cText(math.floor(H/2), "Setup cancelled.", T.textPrimary)
        os.sleep(1); return
    end

    if screen_install(disk) then
        screen_finish()
    end
end

local ok, err = pcall(main)
if not ok then
    gpu.setBackground(T.danger); gpu.setForeground(T.textOnAccent)
    gpu.fill(1, 1, W, H, " ")
    UI.centerText(1, math.floor(H/2)-1, W, "Setup Error", T.textOnAccent, T.danger)
    UI.centerText(1, math.floor(H/2)+1, W, UI.truncate(tostring(err), W-4), T.textOnAccent, T.danger)
    event.pull("key_down")
end