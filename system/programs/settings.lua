-- ==========================================================
-- FixOS 3.1.2 - system/programs/settings.lua
-- Uses UI library for all drawing.
-- FIXES:
--   - UI library is now cached on win object (not re-loaded every draw)
--   - Progress bar width now uses correct card's inner width
-- ==========================================================

local settings = {}

-- Cache helper: loads UI once per window lifetime
local function getUI(win, gpuProxy)
    if not win._ui then
        win._ui = dofile("/system/ui.lua")
        win._ui.init(gpuProxy or component.proxy(component.list("gpu")()))
    end
    return win._ui
end

function settings.init(win)
    win.selectedTab  = 1
    win.tabs         = {"System", "Display", "Update", "About"}
    win.version      = "3.1.2"
    win.updateStatus = "Ready"
    win.updatePct    = 0
    win.elements     = {}
    win._ui          = nil  -- will be populated on first draw

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
    -- FIX: cache UI so it is not re-loaded on every frame
    local UI = getUI(win, gpu)
    local T = UI.Theme
    local P = UI.PADDING

    -- Clear area
    gpu.setBackground(T.surface)
    gpu.fill(cx, cy, cw, ch, " ")

    win.elements = {}

    -- Tab bar
    local tabHits = UI.drawTabBar(cx, cy, cw, win.tabs, win.selectedTab)
    for _, h in ipairs(tabHits) do
        h.action = "tab"
        table.insert(win.elements, h)
    end

    local contentX = cx + P + 1
    local contentY = cy + 2
    local contentW = cw - (P + 1) * 2

    -- --------------------------------------------------------
    if win.selectedTab == 1 then
        -- SYSTEM

        gpu.setForeground(T.accent)
        gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, "System Information")
        contentY = contentY + 2

        -- OS card
        local ix, iy, iw, ih = UI.drawCard(contentX, contentY, contentW, 5, "Operating System")
        gpu.setForeground(T.textSecondary)
        gpu.setBackground(T.surfaceAlt)
        gpu.set(ix, iy + 1, "Name:    FixOS")
        gpu.set(ix, iy + 2, "Version: " .. win.version .. "  (Win10 Edition)")
        contentY = contentY + 6

        -- Memory card
        local total  = computer.totalMemory()
        local free   = computer.freeMemory()
        local used   = total - free
        local memPct = used / total

        -- FIX: capture all 4 return values from drawCard for the memory card
        local mx, my, mw, mh = UI.drawCard(contentX, contentY, contentW, 5, "Memory")
        gpu.setForeground(T.textSecondary)
        gpu.setBackground(T.surfaceAlt)
        gpu.set(mx, my + 1, string.format("Used: %d KB / Total: %d KB",
            math.floor(used/1024), math.floor(total/1024)))

        local barColor = memPct > 0.8 and T.danger or T.success
        -- FIX: use mw (memory card inner width), not iw (OS card inner width)
        UI.drawProgressBar(mx, my + 3, mw, memPct, barColor)

    -- --------------------------------------------------------
    elseif win.selectedTab == 2 then
        -- DISPLAY

        gpu.setForeground(T.accent)
        gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, "Display Settings")
        contentY = contentY + 2

        local rx, ry, rw = UI.drawCard(contentX, contentY, contentW, 3, "Current Resolution")
        gpu.setForeground(T.textSecondary)
        gpu.setBackground(T.surfaceAlt)
        gpu.set(rx, ry + 1, string.format("Active: %d x %d", win.currentW, win.currentH))
        contentY = contentY + 4

        gpu.setForeground(T.textSecondary)
        gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, "Click a resolution to apply and reboot:")
        contentY = contentY + 1

        for _, res in ipairs(win.resolutions) do
            if res.w <= win.maxW and res.h <= win.maxH then
                local isCur = (res.w == win.currentW and res.h == win.currentH)
                local btn = UI.drawButton(contentX, contentY, contentW, 2,
                    res.name, isCur and "accent" or "secondary", true)
                btn.action = "resolution"
                btn.res    = res
                table.insert(win.elements, btn)
                contentY = contentY + 3
            end
        end

    -- --------------------------------------------------------
    elseif win.selectedTab == 3 then
        -- UPDATE

        gpu.setForeground(T.accent)
        gpu.setBackground(T.surface)
        gpu.set(contentX, contentY, "System Update")
        contentY = contentY + 2

        local vx, vy, vw = UI.drawCard(contentX, contentY, contentW, 4, "Version Info")
        gpu.setForeground(T.textSecondary)
        gpu.setBackground(T.surfaceAlt)
        gpu.set(vx, vy + 1, "Installed: FixOS " .. win.version)
        gpu.set(vx, vy + 2, "Status:    " .. win.updateStatus)
        contentY = contentY + 5

        if win.updatePct > 0 then
            UI.drawProgressBar(contentX, contentY, contentW, win.updatePct, T.success)
            contentY = contentY + 2
        end

        local hasNet = component.isAvailable("internet")
        local chkBtn = UI.drawButton(contentX, contentY, 24, 2,
            "Check for Updates", "accent", hasNet)
        chkBtn.action = "update"
        table.insert(win.elements, chkBtn)

    -- --------------------------------------------------------
    elseif win.selectedTab == 4 then
        -- ABOUT

        gpu.setForeground(T.accent)
        gpu.setBackground(T.surface)
        UI.centerText(contentX, contentY,     contentW, "FixOS " .. win.version, T.accent,         T.surface)
        UI.centerText(contentX, contentY + 1, contentW, "Windows 10 Edition",    T.textSecondary, T.surface)
        contentY = contentY + 3

        UI.drawDivider(contentX, contentY, contentW)
        contentY = contentY + 2

        local rows = {
            {"Author",   "FixlutGames21"},
            {"Platform", "OpenComputers (Minecraft)"},
            {"Year",     "2026"},
            {"UI Lib",   "ui.lua v3.1.2"},
        }
        for _, row in ipairs(rows) do
            gpu.setForeground(T.textSecondary)
            gpu.setBackground(T.surface)
            gpu.set(contentX, contentY, row[1])
            gpu.setForeground(T.textPrimary)
            gpu.set(contentX + 12, contentY, row[2])
            contentY = contentY + 1
        end
    end
end

function settings.click(win, clickX, clickY, button)
    -- FIX: use cached UI, not a fresh dofile() every click
    local UI = getUI(win)

    for _, elem in ipairs(win.elements) do
        if UI.hitTest(elem, clickX, clickY) then
            if elem.action == "tab" then
                win.selectedTab = elem.index
                return true

            elseif elem.action == "resolution" then
                local gpu = component.proxy(component.list("gpu")())
                gpu.setResolution(elem.res.w, elem.res.h)
                local fs = component.proxy(computer.getBootAddress())
                local h  = fs.open("/settings.cfg", "w")
                if h then
                    fs.write(h, string.format("resolution=%dx%d\n", elem.res.w, elem.res.h))
                    fs.close(h)
                end
                computer.shutdown(true)
                return true

            elseif elem.action == "update" then
                settings.checkUpdates(win)
                return true
            end
        end
    end
    return false
end

function settings.checkUpdates(win)
    if not component.isAvailable("internet") then
        win.updateStatus = "No Internet Card"
        return
    end
    win.updateStatus = "Checking..."
    win.updatePct    = 0.4

    local net = component.internet
    local ok, handle = pcall(net.request,
        "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/version.txt")
    if not ok or not handle then
        win.updateStatus = "Connection failed"
        win.updatePct    = 0
        return
    end

    local buf = {}; local t0 = computer.uptime() + 10
    while computer.uptime() < t0 do
        local c = handle.read(math.huge)
        if c then table.insert(buf, c) else break end
        os.sleep(0.05)
    end
    pcall(handle.close)

    local remote = table.concat(buf):match("[%d%.]+")
    if remote then
        win.updatePct    = 1.0
        win.updateStatus = remote == win.version and "Up to date" or
                           "Update available: v" .. remote
    else
        win.updateStatus = "Invalid response"
        win.updatePct    = 0
    end
end

return settings