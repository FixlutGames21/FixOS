-- ==========================================================
-- FixOS 4.0.1 - installer.lua
-- FIX 4.0.1:
--   - UI stub: pcall(dofile) can return true but nil when a
--     previously-installed (truncated) ui.lua runs without
--     error but never reaches "return UI".  Added type-check:
--     if UI is not a table after pcall, always use the stub.
--   - Slightly longer download timeout (60s) to prevent init.lua
--     truncation on slow connections.
-- ==========================================================

local component = require("component")
local computer  = require("computer")
local event     = require("event")

local gpu      = component.gpu

-- FIX (download rewrite v2): switched to the raw component.internet
-- handle pattern used by MineOS's production installer
-- (github.com/IgorTimofeev/MineOS/blob/master/Installer/BIOS.lua),
-- instead of require("internet"). The key thing that pattern gets
-- right, which our earlier hand-rolled attempts did NOT:
--
--   local chunk = handle.read(math.huge)
--
-- called in a tight `while true do ... end` loop needs NO os.sleep()
-- and NO manual "wait for connect" polling. The internet card's read()
-- method is a non-direct component call, so OpenComputers itself
-- suspends/yields the calling coroutine internally on every such
-- invoke until data (or EOF) is actually available — sleeping or
-- polling on top of that is not just unnecessary, it's what caused the
-- earlier bugs (silently accepting error pages, then a status-check
-- loop that stalled every file for up to 10s). This exact loop shape
-- is what MineOS ships to real users, so we mirror it here.
local internet = component.isAvailable("internet") and component.internet or nil

if not gpu then error("No GPU") end

local W, H = gpu.maxResolution()
gpu.setResolution(math.min(80, W), math.min(25, H))
W, H = gpu.getResolution()

-- ============================================================
-- UI STUB
-- FIX: check type(UI) == "table", not just UI_ok.
-- A truncated ui.lua can execute successfully but return nil.
-- ============================================================
local UI_ok, UI = pcall(dofile, "/system/ui.lua")
if not UI_ok or type(UI) ~= "table" then
    UI = {}
    UI.PADDING = 1
    UI.Theme = {
        accent=0x0078D7, accentDark=0x005A9E, accentLight=0x429CE3,
        accentSubtle=0xCDE8FF, surface=0xFFFFFF, surfaceAlt=0xF3F3F3,
        surfaceInset=0xE8E8E8, chromeDark=0x1F1F1F, chromeMid=0x2D2D30,
        textPrimary=0x1B1B1B, textSecondary=0x666666, textDisabled=0xAAAAAA,
        textOnAccent=0xFFFFFF, textOnDark=0xF3F3F3, borderSubtle=0xE5E5E5,
        success=0x10893E, warning=0xFFB900, danger=0xE81123, progressTrack=0xE0E0E0,
    }
    function UI.init(g) end
    function UI.truncate(s, n)
        s = tostring(s)
        if #s <= n then return s end
        return s:sub(1, n - 1) .. ">"
    end
    function UI.centerText(x, y, w, str, fg, bg)
        str = tostring(str)
        local ox = math.max(0, math.floor((w - #str) / 2))
        if bg then gpu.setBackground(bg) end
        gpu.setForeground(fg)
        gpu.set(x + ox, y, str)
    end
    function UI.drawButton(x, y, w, h, lbl, style, en)
        style = style or "accent"; en = (en == nil) and true or en; h = h or 2
        local T = UI.Theme
        local bg = en and (style == "danger"   and T.danger     or
                           style == "success"  and T.success    or
                           style == "secondary" and T.surfaceAlt or T.accent)
                       or T.surfaceInset
        local fg = (style == "secondary" and en) and T.textPrimary or T.textOnAccent
        gpu.setBackground(bg); gpu.fill(x, y, w, h, " ")
        UI.centerText(x, y + math.floor(h / 2), w, lbl, fg, bg)
        return {x=x, y=y, w=w, h=h}
    end
    function UI.drawProgressBar(x, y, w, pct, color)
        pct = math.max(0, math.min(1, pct or 0)); color = color or UI.Theme.accent
        gpu.setBackground(UI.Theme.progressTrack); gpu.fill(x, y, w, 1, " ")
        local f = math.floor(w * pct)
        if f > 0 then gpu.setBackground(color); gpu.fill(x, y, f, 1, " ") end
        local s  = math.floor(pct * 100) .. "%"
        local lx = x + math.floor((w - #s) / 2)
        gpu.setForeground(lx < x + f and UI.Theme.textOnAccent or UI.Theme.textSecondary)
        gpu.setBackground(lx < x + f and color or UI.Theme.progressTrack)
        gpu.set(lx, y, s)
    end
    function UI.hitTest(r, mx, my)
        return mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
    end
    function UI.clearScreen(sw, sh, bg)
        gpu.setBackground(bg or UI.Theme.surface); gpu.fill(1, 1, sw, sh, " ")
    end
end

UI.init(gpu)
local T = UI.Theme

local VERSION   = "4.0.1"
local MIN_SPACE = 1024 * 512   -- 512 KB minimum
local REPO      = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main"

-- ============================================================
-- FILE LIST
-- ============================================================
local FILES = {
    {path="boot/init.lua",                       target="/init.lua"},
    {path="system/ui.lua",                       target="/system/ui.lua"},
    {path="system/lang.lua",                     target="/system/lang.lua"},
    {path="system/desktop.lua",                  target="/system/desktop.lua"},
	{path="system/version.lua",                  target="/system/version.lua"},
    {path="system/language/en.lang",             target="/system/language/en.lang"},
    {path="system/language/uk.lang",             target="/system/language/uk.lang"},
    {path="system/language/ru.lang",             target="/system/language/ru.lang"},
    {path="system/programs/calculator.lua",      target="/system/programs/calculator.lua"},
    {path="system/programs/notepad.lua",         target="/system/programs/notepad.lua"},
    {path="system/programs/settings.lua",        target="/system/programs/settings.lua"},
    {path="system/programs/mycomputer.lua",      target="/system/programs/mycomputer.lua"},
    {path="system/programs/terminal.lua",        target="/system/programs/terminal.lua"},
    {path="system/programs/explorer.lua",        target="/system/programs/explorer.lua"},
    {path="system/programs/browser.lua",         target="/system/programs/browser.lua"},
    {path="system/icons/mycomputer.png",         target="/system/icons/mycomputer.png"},
    {path="system/icons/calculator.png",         target="/system/icons/calculator.png"},
    {path="system/icons/browser.png",            target="/system/icons/browser.png"},
    {path="system/icons/explorer.png",           target="/system/icons/explorer.png"},
    {path="system/icons/terminal.png",           target="/system/icons/terminal.png"},
    {path="system/icons/settings.png",           target="/system/icons/settings.png"},
    {path="system/icons/notepad.png",            target="/system/icons/notepad.png"},
    {path="version.txt",                         target="/version.txt"},
}

-- ============================================================
-- CARD HELPER
-- ============================================================
local function drawCard(cx, cy, cw, ch, title)
    gpu.setBackground(T.surface); gpu.fill(cx, cy, cw, ch, " ")
    gpu.setBackground(T.accentDark); gpu.fill(cx, cy, cw, 3, " ")
    if title then UI.centerText(cx, cy+1, cw, title, T.textOnAccent, T.accentDark) end
    gpu.setForeground(T.borderSubtle); gpu.setBackground(T.surface)
    for col = 0, cw-1 do gpu.set(cx+col, cy+ch-1, "\xE2\x94\x80") end
    for row = 3, ch-2 do
        gpu.set(cx,       cy+row, "\xE2\x94\x82")
        gpu.set(cx+cw-1,  cy+row, "\xE2\x94\x82")
    end
    gpu.set(cx,      cy+ch-1, "\xE2\x94\x94")
    gpu.set(cx+cw-1, cy+ch-1, "\xE2\x94\x98")
    return cy+4
end

local function cText(y, str, fg, bg)
    UI.centerText(1, y, W, str, fg, bg or T.surface)
end

-- ============================================================
-- DOWNLOAD
-- FIX (v2): rewritten to mirror the exact pattern used by MineOS's
-- production installer (IgorTimofeev/MineOS, Installer/BIOS.lua /
-- Main.lua) — a raw component.internet handle read in a tight loop
-- with NO os.sleep() and NO manual "wait for connect/status" polling.
-- That polling is what caused our two previous regressions; this
-- pattern is what actually ships to real MineOS users.
-- ============================================================
local function download(url, retries)
    if not internet then return nil, "Немає Internet Card" end
    retries = retries or 3

    for attempt = 1, retries do
        local ok, result = pcall(function()
            local handle, reason = internet.request(url, nil, {
                ["User-Agent"] = "FixOS-Installer/" .. VERSION,
            })
            if not handle then
                error(reason or "request failed")
            end

            local buf      = {}
            local deadline = computer.uptime() + 60  -- last-resort safety net only

            while true do
                -- FIX: no os.sleep() here — handle.read() is a
                -- non-direct component call, OpenComputers itself
                -- suspends the coroutine until data/EOF is ready.
                -- Adding sleep/polling on top (like our earlier
                -- attempts did) only slowed things down or broke them.
                local chunk = handle.read(math.huge)
                if chunk then
                    buf[#buf + 1] = chunk
                else
                    break -- nil chunk == EOF, exactly like MineOS's loop
                end
                if computer.uptime() > deadline then
                    error("timeout: з'єднання зависло понад 60с")
                end
            end

            handle.close()
            return table.concat(buf)
        end)

        if ok and result and #result > 0 then
            -- FIX: MineOS's own loader trusts the body unconditionally
            -- (it has no equivalent check). We keep a light content
            -- heuristic on top, since GitHub raw can return an HTML or
            -- plain-text error page with HTTP 200-adjacent framing in
            -- some edge cases (renamed/removed file upstream) — this
            -- only inspects the ALREADY-read string, so it can't
            -- reintroduce the earlier connection-state bugs.
            local lower = result:lower()
            local looksLikeError =
                lower:match("^%s*<!doctype")
                or lower:match("^%s*<html")
                or result:match("^%s*404: Not Found%s*$")

            if not looksLikeError then
                return result
            end
        end

        if attempt < retries then os.sleep(0.5) end
    end
    return nil, "Завантаження не вдалося"
end

-- ============================================================
-- DISK UTILITIES
-- ============================================================
local function listDisks()
    local out = {}
    for addr in component.list("filesystem") do
        local proxy = component.proxy(addr)
        if proxy then
            local lbl, ro, tot, used = "", false, 0, 0
            pcall(function() lbl  = proxy.getLabel()    or "" end)
            pcall(function() ro   = proxy.isReadOnly()         end)
            pcall(function() tot  = proxy.spaceTotal()  or 0  end)
            pcall(function() used = proxy.spaceUsed()   or 0  end)
            if lbl == "" then lbl = addr:sub(1, 8) end

            if tot >= MIN_SPACE and not tostring(lbl):lower():match("tmp") then
                table.insert(out, {
                    address  = addr,
                    label    = lbl,
                    size     = tot,
                    used     = used,
                    free     = tot - used,
                    readOnly = ro,
                })
            end
        end
    end
    table.sort(out, function(a, b) return a.size > b.size end)
    return out
end

local function formatSize(bytes)
    if bytes >= 1024*1024 then return string.format("%.1f MB", bytes/(1024*1024))
    elseif bytes >= 1024  then return string.format("%.0f KB", bytes/1024)
    else                       return bytes .. " B" end
end

local function iterate(lf, fn)
    if type(lf) == "function" then for v in lf do fn(v) end
    elseif type(lf) == "table" then for _, v in ipairs(lf) do fn(v) end end
end

local function formatDisk(addr)
    local proxy = component.proxy(addr)
    if not proxy then return false end
    local function rm(path)
        local ok, isD = pcall(proxy.isDirectory, path)
        if ok and isD then
            local _, lf = pcall(function() return proxy.list(path) end)
            if lf then
                iterate(lf, function(f)
                    rm(path .. (path:match("/$") and "" or "/") .. f)
                end)
            end
        end
        pcall(proxy.remove, path)
    end
    local _, lf = pcall(function() return proxy.list("/") end)
    if lf then iterate(lf, function(f) rm("/" .. f) end) end
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
    pcall(proxy.write, h, content); pcall(proxy.close, h)
    return true
end

-- ============================================================
-- SCREENS
-- ============================================================
local function screen_welcome()
    UI.clearScreen(W, H)
    local CX, CY, CW, CH = 5, 2, W-10, H-4
    local y = drawCard(CX, CY, CW, CH, "FixOS " .. VERSION .. " Встановлення")

    gpu.setBackground(T.surface)
    UI.centerText(CX, y,   CW, "Ласкаво просимо до FixOS " .. VERSION, T.accent, T.surface)
    UI.centerText(CX, y+1, CW, "Pixel Perfect | OpenComputers Edition", T.textSecondary, T.surface)

    local features = {
        "[OK] BROWSER 4.0: Реальне завантаження сайтів",
        "[OK] EXPLORER 4.0: Всі диски, кнопки, іконки",
        "[OK] MY PC 4.0: Всі компоненти та диски",
        "[OK] DESKTOP 4.0: Нові іконки, анімація",
        "[OK] Синхронізовані версії v" .. VERSION,
        "[OK] Мови: EN / UK / RU",
    }
    for i, f in ipairs(features) do
        gpu.setForeground(T.success); gpu.setBackground(T.surface)
        gpu.set(CX+3, y+2+i, f)
    end

    if not internet then
        gpu.setBackground(T.danger); gpu.fill(CX+2, H-7, CW-4, 2, " ")
        UI.centerText(CX+2, H-6, CW-4, "[!!] ПОТРІБНА INTERNET CARD [!!]", T.textOnAccent, T.danger)
        local btn = UI.drawButton(math.floor(W/2)-8, H-4, 16, 2, "Вийти", "secondary")
        while true do
            local ev, _, x, y2 = event.pull()
            if ev == "touch" and UI.hitTest(btn, x, y2) then return false end
        end
    end

    local btnNext = UI.drawButton(CX+4,       H-4, 20, 2, "  Далі ->",  "accent")
    local btnCncl = UI.drawButton(CX+CW-24,   H-4, 20, 2, "Скасувати", "secondary")

    while true do
        local ev, _, x, y2 = event.pull()
        if ev == "touch" then
            if UI.hitTest(btnNext, x, y2) then return true  end
            if UI.hitTest(btnCncl, x, y2) then return false end
        end
    end
end

local function screen_disk()
    UI.clearScreen(W, H)
    local CX, CY, CW, CH = 5, 2, W-10, H-4
    local y = drawCard(CX, CY, CW, CH, "Вибір диска")

    UI.centerText(CX, y, CW, "Оберіть диск для FixOS " .. VERSION, T.textPrimary, T.surface)
    gpu.setBackground(T.warning); gpu.fill(CX+2, y+2, CW-4, 1, " ")
    UI.centerText(CX+2, y+2, CW-4, "[!!] ВСІ ДАНІ НА ДИСКУ БУДУТЬ ВИДАЛЕНІ [!!]", T.textOnAccent, T.warning)

    local disks   = listDisks()
    local buttons = {}

    if #disks == 0 then
        UI.centerText(CX, y+4, CW, "Придатних дисків не знайдено! (мін. 512 KB)", T.danger, T.surface)
        UI.drawButton(math.floor(W/2)-8, H-4, 16, 2, "<- Назад", "secondary")
        event.pull("touch"); return nil
    end

    local dy = y + 4
    for _, disk in ipairs(disks) do
        if dy + 5 < H-6 then
            gpu.setBackground(T.surfaceAlt); gpu.fill(CX+2, dy, CW-4, 4, " ")
            gpu.setForeground(T.accent); gpu.setBackground(T.surfaceAlt)
            gpu.set(CX+4, dy,   "[D] " .. disk.label .. "  (" .. formatSize(disk.size) .. ")")
            gpu.set(CX+4, dy+1, "    " .. disk.address:sub(1, 24))
            gpu.set(CX+4, dy+2, "    Вільно: " .. formatSize(disk.free))
            if disk.readOnly then
                gpu.setForeground(T.danger)
                gpu.set(CX+4, dy+1, "    ТІЛЬКИ ЧИТАННЯ - НЕДОСТУПНО")
            end
            local btn = UI.drawButton(CX+2, dy+3, CW-4, 2,
                disk.readOnly and "Тільки читання" or "  ОБРАТИ ЦЕЙ ДИСК",
                disk.readOnly and "secondary" or "accent", not disk.readOnly)
            btn.disk = disk; table.insert(buttons, btn)
            dy = dy + 6
        end
    end

    local btnBack = UI.drawButton(CX+CW-22, H-4, 20, 2, "<- Назад", "secondary")
    table.insert(buttons, btnBack)

    while true do
        local ev, _, x, y2 = event.pull()
        if ev == "touch" then
            for _, btn in ipairs(buttons) do
                if UI.hitTest(btn, x, y2) then
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
    local y = drawCard(CX, CY, CW, CH, "Підтвердження")

    UI.centerText(CX, y, CW, "Готові встановити FixOS " .. VERSION .. "?", T.textPrimary, T.surface)
    gpu.setForeground(T.textSecondary); gpu.setBackground(T.surface)
    gpu.set(CX+4, y+2, "1. Форматування диска")
    gpu.set(CX+4, y+3, "2. Завантаження " .. #FILES .. " файлів з GitHub")
    gpu.set(CX+4, y+4, "3. Встановлення boot address")

    gpu.setBackground(T.surfaceAlt); gpu.fill(CX+2, y+6, CW-4, 3, " ")
    gpu.setForeground(T.accent)
    gpu.set(CX+4, y+6, "Диск: " .. disk.label .. "  (" .. formatSize(disk.size) .. ")")
    gpu.setForeground(T.textSecondary)
    gpu.set(CX+4, y+7, "UUID: " .. disk.address:sub(1, 20) .. "...")
    gpu.set(CX+4, y+8, "Вільно: " .. formatSize(disk.free))

    local midX = math.floor(W/2)
    local btnI  = UI.drawButton(midX-22, y+11, 20, 2, "  ВСТАНОВИТИ NOW  ", "accent")
    local btnC  = UI.drawButton(midX+2,  y+11, 18, 2, " Скасувати ",       "secondary")

    while true do
        local ev, _, x, y2 = event.pull()
        if ev == "touch" then
            if UI.hitTest(btnI, x, y2) then return true  end
            if UI.hitTest(btnC, x, y2) then return false end
        end
    end
end

local function screen_install(disk)
    local proxy   = component.proxy(disk.address)
    local CX, CY, CW, CH = 5, 2, W-10, H-4
    local frame   = 0
    local skipped = {}
    local spinChars = {"|", "/", "-", "\\"}

    local function redraw(step, file, pct, msg, msgKind)
        UI.clearScreen(W, H)
        local y = drawCard(CX, CY, CW, CH, "Встановлення FixOS " .. VERSION)
        gpu.setBackground(T.surface)
        UI.centerText(CX, y, CW, step, T.accent, T.surface)
        if file then
            UI.centerText(CX, y+1, CW, UI.truncate(file, CW-2), T.textSecondary, T.surface)
        end
        UI.drawProgressBar(CX+2, y+3, CW-4, pct, pct >= 1 and T.success or T.accent)

        frame = (frame + 1) % 4
        gpu.setForeground(T.accent); gpu.setBackground(T.surface)
        gpu.set(math.floor(W/2), y+5, spinChars[frame+1])

        if msg then
            local colMap = {success=T.success, warning=T.warning, danger=T.danger, info=T.accent}
            gpu.setForeground(colMap[msgKind] or T.accent); gpu.setBackground(T.surface)
            gpu.set(CX+2, y+7, UI.truncate(msg, CW-4))
        end

        if #skipped > 0 then
            gpu.setForeground(T.warning); gpu.setBackground(T.surface)
            gpu.set(CX+2, y+8, "Пропущено (" .. #skipped .. "): " ..
                table.concat(skipped, ", "):sub(1, CW-18))
        end
    end

    -- Format
    redraw("Форматування...", disk.label, 0.02, nil)
    if not formatDisk(disk.address) then
        redraw("ПОМИЛКА", nil, 0, "Не вдалося відформатувати диск", "danger")
        UI.drawButton(math.floor(W/2)-8, H-4, 16, 2, "Вийти", "secondary")
        event.pull("touch"); return false
    end
    pcall(proxy.setLabel, "FixOS")
    redraw("Форматування...", "OK", 0.05, "Диск підготовлено", "success")
    os.sleep(0.2)

    -- Download + write
    local total = #FILES
    local done  = 0
    for _, f in ipairs(FILES) do
        local pct = 0.05 + (done / total) * 0.95
        redraw(string.format("Завантаження %d/%d...", done, total),
               f.path, pct, "Отримання: " .. f.path, "info")

        local data, err = download(REPO .. "/" .. f.path, 3)
        if data then
            redraw(string.format("Запис %d/%d...", done+1, total),
                   f.target, pct, "Запис: " .. f.target, "info")
            if writeToDisk(proxy, f.target, data) then
                done = done + 1
            else
                table.insert(skipped, f.path:match("[^/]+$") or f.path)
            end
        else
            table.insert(skipped, f.path:match("[^/]+$") or f.path)
        end
        os.sleep(0.02)
    end

    local success = (done >= total - 3)
    redraw(
        success and "Встановлення завершено!" or "Встановлено з помилками",
        nil, 1.0,
        string.format("%s | %d/%d файлів | %d пропущено",
            success and "OK" or "Увага", done, total, #skipped),
        success and "success" or "warning"
    )
    pcall(computer.setBootAddress, disk.address)
    os.sleep(1.5)
    return success
end

local function screen_finish()
    UI.clearScreen(W, H)
    local CX, CY, CW, CH = 8, 3, W-16, 16
    local y = drawCard(CX, CY, CW, CH, "Встановлення завершено!")

    UI.centerText(CX, y,   CW, "[OK] FixOS " .. VERSION .. " встановлено!", T.success, T.surface)
    UI.centerText(CX, y+1, CW, "Pixel Perfect | OpenComputers Edition",     T.textSecondary, T.surface)

    local info = {
        "Browser:  Виправлено (фази connecting/reading)",
        "Explorer: Всі диски, sidebar, іконки за типом",
        "My PC:    Всі компоненти + диски в реальному часі",
        "Desktop:  Нові іконки, анімація завантаження",
        "Версія:   " .. VERSION .. " (синхронізовано)",
    }
    for i, v in ipairs(info) do
        gpu.setForeground(T.textSecondary); gpu.setBackground(T.surface)
        gpu.set(CX+3, y+3+i, "[OK] " .. v)
    end

    for i = 5, 1, -1 do
        gpu.setBackground(T.surface); gpu.fill(CX+2, y+11, CW-4, 1, " ")
        UI.centerText(CX+2, y+11, CW-4,
            "Перезапуск через " .. i .. " сек...", T.textSecondary, T.surface)
        os.sleep(1)
    end
    computer.shutdown(true)
end

-- ============================================================
-- MAIN
-- ============================================================
local function main()
    if not screen_welcome() then
        UI.clearScreen(W, H)
        cText(math.floor(H/2), "Встановлення скасовано.", T.textPrimary)
        os.sleep(1); return
    end
    local disk = screen_disk()
    if not disk then
        UI.clearScreen(W, H)
        cText(math.floor(H/2), "Встановлення скасовано.", T.textPrimary)
        os.sleep(1); return
    end
    if not screen_confirm(disk) then
        UI.clearScreen(W, H)
        cText(math.floor(H/2), "Встановлення скасовано.", T.textPrimary)
        os.sleep(1); return
    end
    if screen_install(disk) then
        screen_finish()
    else
        UI.clearScreen(W, H)
        cText(math.floor(H/2)-1, "[!!] Помилки під час встановлення.", T.warning)
        cText(math.floor(H/2)+1, "Перевірте інтернет і спробуйте знову.", T.textSecondary)
        os.sleep(3)
    end
end

local ok, err = pcall(main)
if not ok then
    gpu.setBackground(T.danger); gpu.setForeground(T.textOnAccent)
    gpu.fill(1, 1, W, H, " ")
    UI.centerText(1, math.floor(H/2)-1, W, "Помилка встановника",         T.textOnAccent, T.danger)
    UI.centerText(1, math.floor(H/2)+1, W, UI.truncate(tostring(err), W-4), T.textOnAccent, T.danger)
    event.pull("key_down")
end