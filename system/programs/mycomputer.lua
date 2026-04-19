-- ==========================================================
-- FixOS 4.0.1 - system/programs/mycomputer.lua
-- FIX 4.0.1:
--   - click "openDrive": previously stored the drive address in
--     expWin._targetDriveAddr but Explorer never reads that field,
--     so the Explorer always opened on the default (boot) drive.
--     Fixed: after createWindow(), we iterate expWin.drives to
--     find the matching address and call explorer.selectDrive()
--     directly, just like clicking the drive in Explorer's sidebar.
-- ==========================================================

local mycomp = {}

local function formatSize(bytes)
    if bytes >= 1024*1024*1024 then
        return string.format("%.2f GB", bytes / (1024*1024*1024))
    elseif bytes >= 1024*1024 then
        return string.format("%.1f MB", bytes / (1024*1024))
    elseif bytes >= 1024 then
        return string.format("%.1f KB", bytes / 1024)
    else
        return bytes .. " B"
    end
end

local function getAllDrives()
    local drives   = {}
    local bootAddr = computer.getBootAddress()

    for addr in component.list("filesystem") do
        local proxy = component.proxy(addr)
        if proxy then
            local lbl, ro, tot, used = "", false, 0, 0
            pcall(function() lbl  = proxy.getLabel() or "" end)
            pcall(function() ro   = proxy.isReadOnly() end)
            pcall(function() tot  = proxy.spaceTotal() or 0 end)
            pcall(function() used = proxy.spaceUsed()  or 0 end)
            if lbl == "" then lbl = addr:sub(1, 8) end
            table.insert(drives, {
                address  = addr,
                label    = lbl,
                proxy    = proxy,
                readOnly = ro,
                total    = tot,
                used     = used,
                free     = tot - used,
                isBoot   = (addr == bootAddr),
            })
        end
    end

    table.sort(drives, function(a, b)
        if a.isBoot ~= b.isBoot then return a.isBoot end
        return a.total > b.total
    end)
    return drives
end

local function getComponents()
    local comps = {}
    local types = {
        {"gpu",      "[GPU]", "Відеокарта"},
        {"cpu",      "[CPU]", "Процесор"},
        {"memory",   "[RAM]", "Пам'ять"},
        {"internet", "[NET]", "Internet Card"},
        {"screen",   "[SCR]", "Екран"},
        {"modem",    "[MDM]", "Модем"},
        {"redstone", "[RS] ", "Redstone"},
    }
    for _, t in ipairs(types) do
        local found = false
        for _ in component.list(t[1]) do found = true; break end
        if found then
            table.insert(comps, {icon=t[2], name=t[3], type=t[1]})
        end
    end
    return comps
end

-- ============================================================
-- INIT
-- ============================================================
function mycomp.init(win)
    win.scrollY   = 0
    win.drives    = getAllDrives()
    win.comps     = getComponents()
    win.selDrive  = nil
    win.elements  = {}
    win._ui       = nil
    win._lastTick = 0
end

-- ============================================================
-- TICK
-- ============================================================
function mycomp.tick(win)
    local now = computer.uptime()
    if now - win._lastTick < 3 then return false end
    win._lastTick = now
    for _, d in ipairs(win.drives) do
        pcall(function()
            d.used = d.proxy.spaceUsed() or d.used
            d.free = d.total - d.used
        end)
    end
    return true
end

-- ============================================================
-- DRAW
-- ============================================================
function mycomp.draw(win, gpu, cx, cy, cw, ch)
    if not win._ui then
        win._ui = dofile("/system/ui.lua")
        win._ui.init(gpu)
    end
    local UI = win._ui
    local T  = UI.Theme

    gpu.setBackground(T.surface)
    gpu.fill(cx, cy, cw, ch, " ")

    win.elements = {}
    local y = cy

    -- Header
    gpu.setBackground(T.accent)
    gpu.fill(cx, y, cw, 2, " ")
    gpu.setForeground(T.textOnAccent)
    gpu.set(cx + 2, y,     "[PC] Мій Комп'ютер")
    gpu.set(cx + 2, y + 1, string.format(
        "Пам'ять: %s / %s використано",
        formatSize(computer.totalMemory() - computer.freeMemory()),
        formatSize(computer.totalMemory())
    ))
    y = y + 3

    -- Memory bar
    local memTotal = computer.totalMemory()
    local memUsed  = memTotal - computer.freeMemory()
    local memPct   = memUsed / memTotal
    local barColor = memPct > 0.85 and T.danger or (memPct > 0.6 and T.warning or T.success)
    UI.drawProgressBar(cx + 1, y, cw - 2, memPct, barColor)
    y = y + 2

    -- Disks section
    gpu.setForeground(T.accent); gpu.setBackground(T.surface)
    gpu.set(cx + 1, y, "Диски (" .. #win.drives .. ")")
    gpu.setForeground(T.borderSubtle)
    for col = cx + 10, cx + cw - 2 do gpu.set(col, y, "\xE2\x94\x80") end
    y = y + 1

    local maxScroll = math.max(0, #win.drives * 5 - (ch - 14))
    if win.scrollY > maxScroll then win.scrollY = maxScroll end

    local startDrive = math.floor(win.scrollY / 5) + 1

    for idx = startDrive, #win.drives do
        local d     = win.drives[idx]
        local cardH = 4
        if y + cardH > cy + ch - 6 then break end

        local isSelected = (idx == win.selDrive)
        local cardBg     = isSelected and T.accentSubtle or T.surfaceAlt

        gpu.setBackground(cardBg)
        gpu.fill(cx + 1, y, cw - 2, cardH, " ")

        local stripeColor = d.isBoot and T.accent or T.tileGray
        if d.readOnly then stripeColor = T.textDisabled end
        gpu.setBackground(stripeColor)
        gpu.fill(cx + 1, y, 1, cardH, " ")

        gpu.setBackground(cardBg)

        local diskIcon = d.isBoot and "[*B*]" or "[ D ]"
        gpu.setForeground(T.accent)
        gpu.set(cx + 3, y, diskIcon .. " " .. d.label)
        if d.isBoot then
            gpu.setForeground(T.success)
            gpu.set(cx + cw - 10, y, "[BOOT]")
        end
        if d.readOnly then
            gpu.setForeground(T.warning)
            gpu.set(cx + cw - 12, y, "[ONLY-R]")
        end

        gpu.setForeground(T.textSecondary)
        gpu.set(cx + 3, y + 1, "Адреса: " .. d.address:sub(1, 20) .. "...")

        local pct     = d.total > 0 and (d.used / d.total) or 0
        local sizeStr = string.format(
            "Зайнято: %s / %s  (Вільно: %s)",
            formatSize(d.used), formatSize(d.total), formatSize(d.free)
        )
        gpu.setForeground(T.textSecondary)
        gpu.set(cx + 3, y + 2, UI.truncate(sizeStr, cw - 5))

        local barW = cw - 4
        gpu.setBackground(T.progressTrack)
        gpu.fill(cx + 2, y + 3, barW, 1, " ")
        if pct > 0 then
            local filled    = math.max(1, math.floor(barW * pct))
            local fillColor = pct > 0.9 and T.danger or (pct > 0.7 and T.warning or T.success)
            gpu.setBackground(fillColor)
            gpu.fill(cx + 2, y + 3, filled, 1, " ")
        end
        local pctStr = string.format("%d%%", math.floor(pct * 100))
        local pctX   = cx + 2 + math.floor((barW - #pctStr) / 2)
        local onBar  = pctX < cx + 2 + math.floor(barW * pct)
        gpu.setForeground(onBar and T.textOnAccent or T.textPrimary)
        gpu.setBackground(onBar and (pct > 0.9 and T.danger or (pct > 0.7 and T.warning or T.success)) or T.progressTrack)
        gpu.set(pctX, y + 3, pctStr)

        table.insert(win.elements, {
            x=cx+1, y=y, w=cw-2, h=cardH,
            action="openDrive", driveAddr=d.address, driveIdx=idx
        })

        y = y + cardH + 1
    end

    -- Components section
    if y + 4 <= cy + ch then
        gpu.setForeground(T.accent); gpu.setBackground(T.surface)
        gpu.set(cx + 1, y, "Компоненти")
        gpu.setForeground(T.borderSubtle)
        for col = cx + 12, cx + cw - 2 do gpu.set(col, y, "\xE2\x94\x80") end
        y = y + 1

        gpu.setBackground(T.surfaceAlt)
        gpu.fill(cx + 1, y, cw - 2, #win.comps, " ")

        for i, comp in ipairs(win.comps) do
            if y >= cy + ch - 1 then break end
            gpu.setForeground(T.success); gpu.setBackground(T.surfaceAlt)
            gpu.set(cx + 2, y, comp.icon)
            gpu.setForeground(T.textPrimary)
            gpu.set(cx + 8, y, comp.name)
            y = y + 1
        end
    end

    -- Footer
    gpu.setBackground(T.surfaceInset)
    gpu.fill(cx, cy + ch - 1, cw, 1, " ")
    gpu.setForeground(T.textSecondary)
    local uptime = math.floor(computer.uptime())
    local hh = math.floor(uptime/3600)
    local mm = math.floor((uptime%3600)/60)
    local ss = uptime % 60
    gpu.set(cx + 1, cy + ch - 1, string.format(
        "Uptime: %02d:%02d:%02d | Диски: %d | Клік -> відкрити у провіднику",
        hh, mm, ss, #win.drives))
end

-- ============================================================
-- CLICK
-- ============================================================
function mycomp.click(win, clickX, clickY, btn)
    if not win._ui then return false end
    local UI = win._ui

    for _, elem in ipairs(win.elements) do
        if UI.hitTest(elem, clickX, clickY) then
            if elem.action == "openDrive" then
                win.selDrive = elem.driveIdx

                if _G.createWindow then
                    local expWin = _G.createWindow("explorer")

                    -- FIX: The old code stored the address in expWin._targetDriveAddr
                    -- but explorer.lua never reads that field, so the drive was never
                    -- pre-selected.  We now iterate expWin.drives (populated by
                    -- explorer.init) and call selectDrive() directly.
                    if expWin and expWin.program and expWin.drives then
                        for i, d in ipairs(expWin.drives) do
                            if d.address == elem.driveAddr then
                                expWin.program.selectDrive(expWin, i)
                                break
                            end
                        end
                    end
                end

                return true
            end
        end
    end
    return false
end

-- ============================================================
-- SCROLL
-- ============================================================
function mycomp.scroll(win, dir)
    win.scrollY = math.max(0, win.scrollY + (dir > 0 and -3 or 3))
    return true
end

return mycomp