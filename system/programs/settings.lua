-- ==========================================================
-- FixOS 3.2.0 - system/programs/settings.lua
-- FIXES 3.2.0:
--   - Update: don't break on first nil (connection wait)
--   - Language tab (5th tab)
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

function settings.init(win)
    win.selectedTab  = 1
    win.tabs         = {
        L("settings.system"), L("settings.display"),
        L("settings.update"), L("settings.about"), L("settings.language"),
    }
    win.version      = "3.2.0"
    win.updateStatus = L("settings.upd.check")
    win.updatePct    = 0
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
    local contentW = cw - (P + 1) * 2

    if win.selectedTab == 1 then
        -- SYSTEM
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

    elseif win.selectedTab == 2 then
        -- DISPLAY
        gpu.setForeground(T.accent); gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, "Display Settings"); contentY = contentY + 2

        local rx, ry = UI.drawCard(contentX, contentY, contentW, 3, "Current Resolution")
        gpu.setForeground(T.textSecondary); gpu.setBackground(T.surfaceAlt)
        gpu.set(rx, ry + 1, string.format("Active: %d x %d", win.currentW, win.currentH))
        contentY = contentY + 4

        gpu.setForeground(T.textSecondary); gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, "Click to apply and reboot:"); contentY = contentY + 1

        for _, res in ipairs(win.resolutions) do
            if res.w <= win.maxW and res.h <= win.maxH then
                local isCur = (res.w == win.currentW and res.h == win.currentH)
                local btn = UI.drawButton(contentX, contentY, contentW, 2,
                    res.name, isCur and "accent" or "secondary", true)
                btn.action = "resolution"; btn.res = res
                table.insert(win.elements, btn); contentY = contentY + 3
            end
        end

    elseif win.selectedTab == 3 then
        -- UPDATE
        gpu.setForeground(T.accent); gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, L("settings.upd.title")); contentY = contentY + 2

        local vx, vy, vw = UI.drawCard(contentX, contentY, contentW, 4, L("settings.upd.info"))
        gpu.setForeground(T.textSecondary); gpu.setBackground(T.surfaceAlt)
        gpu.set(vx, vy + 1, L("settings.upd.installed") .. ": FixOS " .. win.version)
        gpu.set(vx, vy + 2, L("settings.upd.status") .. ":    " .. win.updateStatus)
        contentY = contentY + 5

        if win.updatePct > 0 then
            UI.drawProgressBar(contentX, contentY, contentW, win.updatePct,
                win.updatePct >= 1.0 and T.success or T.accent)
            contentY = contentY + 2
        end

        local hasNet = component.isAvailable("internet")
        local chkBtn = UI.drawButton(contentX, contentY, 28, 2,
            L("settings.upd.check"), "accent", hasNet)
        chkBtn.action = "update"; table.insert(win.elements, chkBtn)

        if not hasNet then
            contentY = contentY + 3
            gpu.setForeground(T.danger); gpu.setBackground(T.surface)
            gpu.set(contentX, contentY, "[!!] " .. L("settings.upd.no_internet"))
        end

    elseif win.selectedTab == 4 then
        -- ABOUT
        gpu.setForeground(T.accent); gpu.setBackground(T.surface)
        UI.centerText(contentX, contentY,     contentW, "FixOS " .. win.version, T.accent,        T.surface)
        UI.centerText(contentX, contentY + 1, contentW, "Windows 10 Edition",   T.textSecondary, T.surface)
        contentY = contentY + 3
        UI.drawDivider(contentX, contentY, contentW); contentY = contentY + 2

        local rows = {
            {L("settings.about.author"),   "FixlutGames21"},
            {L("settings.about.platform"), "OpenComputers (Minecraft)"},
            {L("settings.about.year"),     "2026"},
            {L("settings.about.ui"),       "ui.lua v3.2.0"},
        }
        for _, row in ipairs(rows) do
            gpu.setForeground(T.textSecondary); gpu.setBackground(T.surface)
            gpu.set(contentX, contentY, row[1])
            gpu.setForeground(T.textPrimary)
            gpu.set(contentX + 14, contentY, row[2]); contentY = contentY + 1
        end

    elseif win.selectedTab == 5 then
        -- LANGUAGE
        gpu.setForeground(T.accent); gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, L("settings.lang.title")); contentY = contentY + 2

        local curLang = (_G.Lang and _G.Lang.current()) or "en"
        gpu.setForeground(T.textSecondary); gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, L("settings.lang.current") .. ": " .. curLang)
        contentY = contentY + 2

        local langs = {
            {code="en", name="English"},
            {code="uk", name="Ukrainska (Ukrainian)"},
            {code="ru", name="Russkij (Russian)"},
        }
        for _, entry in ipairs(langs) do
            local isCur = (curLang == entry.code)
            local btn   = UI.drawButton(contentX, contentY, contentW, 2,
                (isCur and "[*] " or "[ ] ") .. entry.name,
                isCur and "accent" or "secondary", true)
            btn.action   = "setlang"
            btn.langCode = entry.code
            table.insert(win.elements, btn); contentY = contentY + 3
        end
        contentY = contentY + 1
        gpu.setForeground(T.textSecondary); gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, "* Reboot to apply fully")
    end
end

function settings.click(win, clickX, clickY, button)
    local UI = getUI(win)
    for _, elem in ipairs(win.elements) do
        if UI.hitTest(elem, clickX, clickY) then
            if elem.action == "tab" then
                win.selectedTab = elem.index; return true

            elseif elem.action == "resolution" then
                local gpu = component.proxy(component.list("gpu")())
                gpu.setResolution(elem.res.w, elem.res.h)
                local fs = component.proxy(computer.getBootAddress())
                local h  = fs.open("/settings.cfg", "w")
                if h then
                    local lc = (_G.Lang and _G.Lang.current()) or "en"
                    fs.write(h, string.format("resolution=%dx%d\nlanguage=%s\n",
                        elem.res.w, elem.res.h, lc))
                    fs.close(h)
                end
                computer.shutdown(true); return true

            elseif elem.action == "update" then
                settings.checkUpdates(win); return true

            elseif elem.action == "setlang" then
                local fs = component.proxy(computer.getBootAddress())
                local old = ""
                if fs.exists("/settings.cfg") then
                    local h = fs.open("/settings.cfg","r")
                    if h then old = fs.read(h, math.huge); fs.close(h) end
                end
                local new = old:gsub("language=%a+\n?","") .. "language=" .. elem.langCode .. "\n"
                local h = fs.open("/settings.cfg","w")
                if h then fs.write(h, new); fs.close(h) end
                if _G.Lang then _G.Lang.load(elem.langCode) end
                return true
            end
        end
    end
    return false
end

-- FIX: correct download loop - wait for connection before giving up on nil
function settings.checkUpdates(win)
    if not component.isAvailable("internet") then
        win.updateStatus = L("settings.upd.no_internet"); win.updatePct = 0; return
    end
    win.updateStatus = L("settings.upd.checking"); win.updatePct = 0.2

    local net = component.internet
    local ok, handle = pcall(net.request,
        "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/version.txt")
    if not ok or not handle then
        win.updateStatus = L("settings.upd.failed"); win.updatePct = 0; return
    end

    local buf      = {}
    local deadline = computer.uptime() + 30
    local gotData  = false

    while computer.uptime() < deadline do
        local chunk = handle.read(math.huge)
        if chunk then
            table.insert(buf, chunk)
            gotData = true
            win.updatePct = 0.7
        elseif gotData then
            break           -- EOF after data received
        else
            os.sleep(0.2)   -- Still connecting, wait
        end
    end
    pcall(handle.close)

    local remote = table.concat(buf):match("[%d%.]+")
    if remote then
        win.updatePct = 1.0
        if remote == win.version then
            win.updateStatus = L("settings.upd.up_to_date")
        else
            win.updateStatus = L("settings.upd.available", remote)
        end
    else
        win.updateStatus = L("settings.upd.invalid"); win.updatePct = 0
    end
end

return settings