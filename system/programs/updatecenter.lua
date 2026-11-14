-- ==========================================================
-- FixOS 4.3.0 - system/programs/updatecenter.lua   (НОВИЙ ФАЙЛ)
-- FixOS Update Center
--   * оновлення з GitHub (компонент за компонентом)
--   * версії окремих програм (встановлена / на GitHub / статус)
--   * автоматична резервна копія перед кожним оновленням
--   * відкат до будь-якої збереженої копії
-- Уся логіка - в /system/lib/updater.lua
-- ==========================================================

local uc = {}

local TABS = {"Оновлення", "Резервні копії", "Журнал"}

local STATUS_TEXT = {
    current  = "актуально",
    update   = "є оновлення",
    new      = "не встановлено",
    repair   = "відсутні файли",
    modified = "змінено локально",
    newer    = "новіша за GitHub",
    legacy   = "версія невідома",
}

local function ulen(s)
    if unicode and unicode.len then return unicode.len(s) end
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end

local function pad(s, n)
    s = tostring(s)
    local l = ulen(s)
    if l >= n then
        if unicode and unicode.sub then return unicode.sub(s, 1, n) end
        return s:sub(1, n)
    end
    return s .. string.rep(" ", n - l)
end

local function statusColor(T, st)
    if st == "current" then return T.success end
    if st == "update" or st == "new" then return T.accent end
    if st == "repair" or st == "modified" or st == "legacy" then return 0xB86E00 end
    return T.textSecondary
end

-- ============================================================
-- INIT / CLOSE
-- ============================================================
function uc.init(win)
    win.tab        = 1
    win.entries    = {}
    win.remote     = nil
    win.sel        = {}
    win.scrollY    = 0
    win.cursor     = 1
    win.bkSel      = 1
    win.bkScroll   = 0
    win.backups    = {}
    win.confirm    = nil
    win.input      = nil
    win.job        = nil
    win.result     = nil
    win.elements   = {}
    win._lastRedraw = 0
    win.title      = "Update Center"
    win.jobLog     = {}

    local okT, tf = pcall(function()
        if not _G._FixTF then _G._FixTF = dofile("/system/lib/textfield.lua") end
        return _G._FixTF
    end)
    win.TF = okT and tf or nil
    local ok, mod = pcall(dofile, "/system/lib/updater.lua")
    if not ok or type(mod) ~= "table" or not win.TF then
        win.broken = "Не вдалося завантажити /system/lib/updater.lua: " .. tostring(mod)
        return
    end
    win.U = mod
    mod.loadConfig()
    win.backups = mod.listBackups()

    local okN, Net = pcall(function()
        if not _G._FixNet then _G._FixNet = dofile("/system/lib/net.lua") end
        return _G._FixNet
    end)
    win.hasNet = okN and Net and Net.available()
    if win.hasNet then
        uc.startCheck(win)
    else
        win.result = {ok = false, message = "Немає Internet Card - перевірка оновлень недоступна. Відкат працює й без мережі."}
    end
end

function uc.close(win)
    if win.job and win.job.state == "running" then
        if win.job.cancellable then win.job:cancel() end
    end
end

-- ============================================================
-- Операції
-- ============================================================
local function setJob(win, job)
    win.job = job
    win.result = nil
    win.jobLog = job.log
    job.onFinish = function(j) uc.onJobFinished(win, j) end
end

function uc.startCheck(win)
    if win.job and win.job.state == "running" then return end
    if not win.U then return end
    setJob(win, win.U.check())
end

function uc.selectedIds(win)
    local ids = {}
    for _, e in ipairs(win.entries) do if win.sel[e.id] then ids[e.id] = true end end
    return ids
end

function uc.startUpdate(win, all)
    if win.job and win.job.state == "running" then return end
    if not win.remote then return end
    local ids = {}
    if all then
        for _, e in ipairs(win.entries) do
            if win.U.needsAction(e.status) then ids[e.id] = true end
        end
    else
        ids = uc.selectedIds(win)
    end
    if next(ids) == nil then
        win.result = {ok = true, message = "Нічого вибрано для оновлення."}
        return
    end
    setJob(win, win.U.update(win.remote, win.entries, ids))
end

function uc.startRollback(win, id)
    if win.job and win.job.state == "running" then return end
    setJob(win, win.U.rollback(id))
end

function uc.onJobFinished(win, job)
    local U = win.U
    if job.kind == "check" then
        if job.state == "done" then
            win.remote  = job.result.remote
            win.entries = job.result.entries
            win.sel = {}
            for _, e in ipairs(win.entries) do
                if e.status == "update" or e.status == "legacy" or e.status == "repair" then
                    win.sel[e.id] = true
                end
            end
            local n = 0
            for _, e in ipairs(win.entries) do if U.needsAction(e.status) then n = n + 1 end end
            win.result = {ok = true, message = (n > 0)
                and string.format("Знайдено оновлень: %d. Виберіть компоненти й натисніть «Оновити».", n)
                or "Усе актуально."}
        else
            win.result = {ok = false, message = tostring(job.err)}
        end
    elseif job.kind == "update" then
        if job.state == "done" then
            win.backups = U.listBackups()
            -- нове порівняння без мережі
            if win.remote then win.entries = U.compare(U.loadLocal(), win.remote) end
            win.sel = {}
            win.result = {ok = true, reboot = job.result.reboot, backup = job.result.backup,
                message = string.format("Оновлено компонентів: %d. Резервна копія: %s.%s",
                    #job.result.installed, job.result.backup,
                    job.result.reboot and " Потрібне перезавантаження." or "")}
        elseif job.state == "cancelled" then
            win.result = {ok = false, message = "Оновлення скасовано. Систему не змінено."}
        else
            win.backups = U.listBackups()
            win.result = {ok = false, message = tostring(job.err)}
        end
    elseif job.kind == "rollback" then
        win.backups = U.listBackups()
        if win.remote then win.entries = U.compare(U.loadLocal(), win.remote) end
        if job.state == "done" then
            win.result = {ok = true, reboot = job.result.reboot,
                message = string.format("Відкат до %s виконано. Попередній стан збережено як %s.%s",
                    job.result.backup, job.result.undo, job.result.reboot and " Перезавантажте систему." or "")}
        elseif job.state == "cancelled" then
            win.result = {ok = false, message = "Відкат скасовано."}
        else
            win.result = {ok = false, message = tostring(job.err)}
        end
        win.bkSel = math.min(win.bkSel, math.max(1, #win.backups))
    end
end

-- ============================================================
-- TICK
-- ============================================================
function uc.tick(win)
    if win.broken then return false end
    local job = win.job
    if job and job.state == "running" then
        for _ = 1, 2 do
            if job:step() ~= "running" then return true end
        end
        local now = computer.uptime()
        if now - win._lastRedraw > 0.2 then
            win._lastRedraw = now
            return true
        end
    end
    return false
end

-- ============================================================
-- DRAW
-- ============================================================
local function drawPanel(win, gpu, UI, T, x, y, w)
    local job = win.job
    gpu.setBackground(T.surfaceAlt)
    gpu.fill(x, y, w, 4, " ")
    if job and job.state == "running" then
        UI.spinner(x + 1, y, math.floor(computer.uptime() * 8), T.accent, T.surfaceAlt)
        gpu.setForeground(T.textPrimary); gpu.setBackground(T.surfaceAlt)
        gpu.set(x + 3, y, UI.truncate(job.phase or "", w - 4))
        UI.drawProgressBar(x + 1, y + 1, w - 2, job.progress or 0, T.accent)
        gpu.setBackground(T.surfaceAlt); gpu.setForeground(T.textSecondary)
        gpu.set(x + 1, y + 2, UI.truncate(job.detail or "", w - 2))
        local lastLog = job.log[#job.log]
        if lastLog then gpu.set(x + 1, y + 3, UI.truncate(lastLog, w - 2)) end
    elseif win.result then
        local r = win.result
        local bg = r.ok and T.success or T.danger
        local lines = {}
        local cur = ""
        for word in (r.message or ""):gmatch("%S+") do
            if cur == "" then cur = word
            elseif ulen(cur) + 1 + ulen(word) <= w - 4 then cur = cur .. " " .. word
            else lines[#lines + 1] = cur; cur = word end
        end
        if cur ~= "" then lines[#lines + 1] = cur end
        for i = 1, math.min(4, #lines) do
            gpu.setBackground(bg); gpu.fill(x, y + i - 1, w, 1, " ")
            gpu.setForeground(T.textOnAccent)
            local prefix = (i == 1) and (r.ok and "[OK] " or "[XX] ") or "     "
            gpu.set(x + 1, y + i - 1, UI.truncate(prefix .. lines[i], w - 2))
        end
    else
        gpu.setForeground(T.textSecondary)
        gpu.set(x + 1, y + 1, "Готово до роботи.")
    end
end

local function addBtn(win, UI, x, y, w, label, style, enabled, action, extra)
    UI.drawButton(x, y, w, 1, label, style, enabled)
    local e = {x = x, y = y, w = w, h = 1, action = action, enabled = enabled}
    if extra then for k, v in pairs(extra) do e[k] = v end end
    win.elements[#win.elements + 1] = e
end

function uc.draw(win, gpu, cx, cy, cw, ch)
    if not win._ui then
        win._ui = dofile("/system/ui.lua")
        win._ui.init(gpu)
    end
    local UI, T = win._ui, win._ui.Theme
    gpu.setBackground(T.surface); gpu.fill(cx, cy, cw, ch, " ")
    win.elements = {}

    if win.broken then
        gpu.setForeground(T.danger)
        gpu.set(cx + 1, cy + 1, UI.truncate(win.broken, cw - 2))
        gpu.set(cx + 1, cy + 3, "Перевстановіть FixOS (installer.lua).")
        return
    end
    local U = win.U
    local running = win.job and win.job.state == "running"

    -- ── заголовок ─────────────────────────────────────────
    gpu.setBackground(T.surfaceAlt); gpu.fill(cx, cy, cw, 1, " ")
    gpu.setForeground(T.textPrimary)
    local remoteOs = win.remote and win.remote.os or "—"
    gpu.set(cx + 1, cy, UI.truncate(string.format("Система v%s  ·  GitHub v%s  ·  %s@%s",
        U.localOsVersion(), remoteOs, U.REPO, U.BRANCH), cw - 2))

    -- ── вкладки ───────────────────────────────────────────
    local hits = UI.drawTabBar(cx, cy + 1, cw, TABS, win.tab)
    for _, h in ipairs(hits) do
        win.elements[#win.elements + 1] = {x = h.x, y = h.y, w = h.w, h = 1, action = "tab", index = h.index}
    end

    local y0     = cy + 3
    local panelH = 4
    local panelY = cy + ch - panelH - 1
    local listH  = panelY - (y0 + 3) - 1
    win._listH   = listH

    -- ── вкладка 1: оновлення ──────────────────────────────
    if win.tab == 1 then
        addBtn(win, UI, cx + 1, y0, 14, "Перевірити", "secondary", not running and win.hasNet, "check")
        addBtn(win, UI, cx + 16, y0, 18, "Оновити вибране", "accent", not running and win.remote ~= nil, "update")
        addBtn(win, UI, cx + 35, y0, 14, "Оновити все", "success", not running and win.remote ~= nil, "updateAll")
        if running and win.job.cancellable then
            addBtn(win, UI, cx + 50, y0, 12, "Скасувати", "danger", true, "cancel")
        elseif win.result and win.result.reboot and not running then
            addBtn(win, UI, cx + 50, y0, 20, "Перезавантажити", "danger", true, "reboot")
        end

        -- заголовок таблиці
        local hy = y0 + 2
        gpu.setBackground(T.surfaceInset); gpu.setForeground(T.textSecondary)
        gpu.fill(cx, hy, cw, 1, " ")
        gpu.set(cx + 5,  hy, "Компонент")
        gpu.set(cx + 28, hy, "Встановл.")
        gpu.set(cx + 38, hy, "GitHub")
        gpu.set(cx + 47, hy, "Стан")

        local maxScroll = math.max(0, #win.entries - listH)
        if win.scrollY > maxScroll then win.scrollY = maxScroll end
        gpu.setBackground(T.surface)
        if #win.entries == 0 then
            gpu.setForeground(T.textSecondary)
            gpu.set(cx + 2, hy + 2, win.hasNet and "Натисніть «Перевірити», щоб отримати список з GitHub."
                                                or "Internet Card не знайдено.")
        end
        for row = 1, math.min(listH, #win.entries - win.scrollY) do
            local e = win.entries[win.scrollY + row]
            local ry = hy + row
            local mark = win.sel[e.id] and "[x]" or "[ ]"
            local need = U.needsAction(e.status)
            gpu.setBackground(win.sel[e.id] and T.accentSubtle or T.surface)
            gpu.fill(cx, ry, cw - 1, 1, " ")
            if win.scrollY + row == win.cursor then
                gpu.setForeground(T.accentDark); gpu.set(cx, ry, ">")
            end
            gpu.setForeground(need and T.accent or T.textDisabled)
            gpu.set(cx + 1, ry, mark)
            gpu.setForeground(T.textPrimary)
            gpu.set(cx + 5, ry, pad(e.name .. (e.reboot and " ⟳" or ""), 22))
            gpu.setForeground(T.textSecondary)
            gpu.set(cx + 28, ry, pad(e.localVer, 9))
            gpu.set(cx + 38, ry, pad(e.remoteVer, 8))
            gpu.setForeground(statusColor(T, e.status))
            gpu.set(cx + 47, ry, UI.truncate(STATUS_TEXT[e.status] or e.status, cw - 48))
            win.elements[#win.elements + 1] = {x = cx, y = ry, w = cw - 1, h = 1, action = "toggle", id = e.id,
                                               enabled = not running}
        end
        UI.drawScrollbar(cx + cw - 1, hy + 1, listH, math.max(listH, #win.entries), listH, win.scrollY)

    -- ── вкладка 2: резервні копії ─────────────────────────
    elseif win.tab == 2 then
        local sel = win.backups[win.bkSel]
        addBtn(win, UI, cx + 1, y0, 14, "Відкотити", "accent", not running and sel ~= nil, "rollback")
        addBtn(win, UI, cx + 16, y0, 12, "Видалити", "danger", not running and sel ~= nil, "delBackup")
        addBtn(win, UI, cx + 29, y0, 12, "Оновити", "secondary", not running, "refreshBackups")
        if running and win.job.cancellable then
            addBtn(win, UI, cx + 50, y0, 12, "Скасувати", "danger", true, "cancel")
        elseif win.result and win.result.reboot and not running then
            addBtn(win, UI, cx + 50, y0, 20, "Перезавантажити", "danger", true, "reboot")
        end

        local hy = y0 + 2
        gpu.setBackground(T.surfaceInset); gpu.setForeground(T.textSecondary)
        gpu.fill(cx, hy, cw, 1, " ")
        gpu.set(cx + 1, hy, "Копія"); gpu.set(cx + 8, hy, "Версія"); gpu.set(cx + 17, hy, "Файлів")
        gpu.set(cx + 25, hy, "КБ"); gpu.set(cx + 31, hy, "Опис")

        gpu.setBackground(T.surface)
        if #win.backups == 0 then
            gpu.setForeground(T.textSecondary)
            gpu.set(cx + 2, hy + 2, "Резервних копій ще немає. Вони створюються автоматично перед оновленням.")
        end
        local maxScroll = math.max(0, #win.backups - listH)
        if win.bkScroll > maxScroll then win.bkScroll = maxScroll end
        for row = 1, math.min(listH, #win.backups - win.bkScroll) do
            local idx = win.bkScroll + row
            local b = win.backups[idx]
            local ry = hy + row
            gpu.setBackground(idx == win.bkSel and T.accentSubtle or T.surface)
            gpu.fill(cx, ry, cw - 1, 1, " ")
            gpu.setForeground(T.textPrimary)
            gpu.set(cx + 1, ry, b.id)
            gpu.setForeground(T.textSecondary)
            gpu.set(cx + 8, ry, pad("v" .. b.os, 8))
            gpu.set(cx + 17, ry, pad(b.files, 7))
            gpu.set(cx + 25, ry, pad(math.ceil(b.size / 1024), 5))
            gpu.setForeground(T.textPrimary)
            gpu.set(cx + 31, ry, UI.truncate(b.label, cw - 33))
            win.elements[#win.elements + 1] = {x = cx, y = ry, w = cw - 1, h = 1, action = "pickBackup",
                                               index = idx, enabled = not running}
        end
        UI.drawScrollbar(cx + cw - 1, hy + 1, listH, math.max(listH, #win.backups), listH, win.bkScroll)

        -- підтвердження
        if win.confirm then
            local bx, by, bw = cx + 6, hy + 2, cw - 12
            gpu.setBackground(T.surface); gpu.fill(bx, by, bw, 6, " ")
            gpu.setBackground(T.warning); gpu.fill(bx, by, bw, 1, " ")
            gpu.setForeground(0x1B1B1B); gpu.set(bx + 1, by, UI.truncate(win.confirm.title, bw - 2))
            gpu.setBackground(T.surface); gpu.setForeground(T.textPrimary)
            gpu.set(bx + 1, by + 2, UI.truncate(win.confirm.text1 or "", bw - 2))
            gpu.set(bx + 1, by + 3, UI.truncate(win.confirm.text2 or "", bw - 2))
            addBtn(win, UI, bx + 2, by + 5, 14, "Так", win.confirm.style or "accent", true, "confirmYes")
            addBtn(win, UI, bx + 18, by + 5, 14, "Скасувати", "secondary", true, "confirmNo")
        end

    -- ── вкладка 3: журнал та налаштування ─────────────────
    else
        addBtn(win, UI, cx + 1, y0, 20, "Репозиторій/гілка…", "secondary", not running, "editRepo")
        gpu.setBackground(T.surface)
        if win.input then
            gpu.setBackground(T.accentSubtle); gpu.fill(cx + 22, y0, cw - 23, 1, " ")
            win.TF.draw(gpu, win.input, cx + 23, y0, cw - 25,
                {fg = T.textPrimary, bg = T.accentSubtle, curFg = T.accentSubtle, curBg = T.textPrimary,
                 selFg = T.textOnAccent, selBg = T.accent}, true)
            win.elements[#win.elements + 1] = {x = cx + 22, y = y0, w = cw - 23, h = 1, action = "inputClick", x0 = cx + 23}
            gpu.setBackground(T.surface); gpu.setForeground(T.textSecondary)
            gpu.set(cx + 1, y0 + 1, "Формат: власник/репозиторій@гілка  ·  Enter - зберегти, Esc - скасувати")
        end
        local y = y0 + 3
        gpu.setBackground(T.surface)
        gpu.setForeground(T.accent); gpu.set(cx + 1, y, "Що нового на GitHub:"); y = y + 1
        local shown = 0
        if win.remote then
            for _, l in ipairs(win.remote.log) do
                if y >= panelY - 4 then break end
                gpu.setForeground(T.textPrimary)
                gpu.set(cx + 2, y, UI.truncate("v" .. l.version .. "  " .. l.text, cw - 4))
                y = y + 1; shown = shown + 1
            end
        end
        if shown == 0 then
            gpu.setForeground(T.textSecondary); gpu.set(cx + 2, y, "(немає даних - виконайте перевірку)"); y = y + 1
        end
        y = y + 1
        if y < panelY - 1 then
            gpu.setForeground(T.accent); gpu.set(cx + 1, y, "Журнал останньої операції:"); y = y + 1
            local log = win.jobLog or {}
            local first = math.max(1, #log - (panelY - 1 - y) + 1)
            for i = first, #log do
                if y >= panelY - 1 then break end
                gpu.setForeground(T.textSecondary)
                gpu.set(cx + 2, y, UI.truncate(log[i], cw - 4)); y = y + 1
            end
        end
    end

    -- ── нижня панель завдання + підказка ──────────────────
    drawPanel(win, gpu, UI, T, cx, panelY, cw)
    gpu.setBackground(T.surface); gpu.setForeground(T.textDisabled)
    gpu.set(cx + 1, cy + ch - 1, UI.truncate("1/2/3 вкладки · Пробіл - вибір · C - перевірити · ↑↓ список", cw - 2))
end

-- ============================================================
-- CLICK
-- ============================================================
local function askConfirm(win, title, t1, t2, style, onYes)
    win.confirm = {title = title, text1 = t1, text2 = t2, style = style, onYes = onYes}
end

function uc.click(win, mx, my, btn)
    if win.broken or not win._ui then return false end
    local UI = win._ui
    for i = #win.elements, 1, -1 do
        local e = win.elements[i]
        if e.enabled ~= false and UI.hitTest(e, mx, my) then
            local a = e.action
            if win.confirm and a ~= "confirmYes" and a ~= "confirmNo" then
                -- модальне вікно: решту ігноруємо
            elseif a == "tab" then win.tab = e.index; win.input = nil
            elseif a == "check" then uc.startCheck(win)
            elseif a == "update" then uc.startUpdate(win, false)
            elseif a == "updateAll" then uc.startUpdate(win, true)
            elseif a == "cancel" then if win.job then win.job:cancel() end
            elseif a == "reboot" then computer.shutdown(true)
            elseif a == "toggle" then
                win.sel[e.id] = not win.sel[e.id] or nil
                for i, en in ipairs(win.entries) do if en.id == e.id then win.cursor = i end end
            elseif a == "pickBackup" then win.bkSel = e.index
            elseif a == "refreshBackups" then win.backups = win.U.listBackups()
            elseif a == "rollback" then
                local b = win.backups[win.bkSel]
                if b then
                    askConfirm(win, "Відкат до " .. b.id,
                        "Файли повернуться до стану: " .. b.label,
                        "Поточний стан буде збережено в нову копію (відкат можна скасувати).", "accent",
                        function() uc.startRollback(win, b.id) end)
                end
            elseif a == "delBackup" then
                local b = win.backups[win.bkSel]
                if b then
                    askConfirm(win, "Видалити копію " .. b.id .. "?",
                        "Цю дію не можна скасувати.", b.label, "danger",
                        function()
                            win.U.deleteBackup(b.id)
                            win.backups = win.U.listBackups()
                            win.bkSel = math.max(1, math.min(win.bkSel, #win.backups))
                        end)
                end
            elseif a == "confirmYes" then
                local f = win.confirm and win.confirm.onYes
                win.confirm = nil
                if f then f() end
            elseif a == "confirmNo" then win.confirm = nil
            elseif a == "inputClick" then
                if win.input then win.TF.click(win.input, e.x0, mx) end
            elseif a == "editRepo" then
                win.input = win.TF.new(win.U.REPO .. "@" .. win.U.BRANCH, {max = 120})
                win.input.fresh = true
            end
            return true
        end
    end
    return false
end

-- ============================================================
-- KEY / SCROLL / PASTE
-- ============================================================
local function moveSel(win, d)
    if win.tab == 1 then
        local n = #win.entries
        if n == 0 then return end
        win.cursor = math.max(1, math.min(n, win.cursor + d))
        local lh = win._listH or 6
        if win.cursor <= win.scrollY then win.scrollY = win.cursor - 1 end
        if win.cursor > win.scrollY + lh then win.scrollY = win.cursor - lh end
    elseif win.tab == 2 then
        win.bkSel = math.max(1, math.min(#win.backups, win.bkSel + d))
        if win.bkSel <= win.bkScroll then win.bkScroll = win.bkSel - 1 end
        local lh = win._listH or 6
        if win.bkSel > win.bkScroll + lh then win.bkScroll = win.bkSel - lh end
    end
end

function uc.paste(win, text)
    if win.input then
        local line = text:gsub("[\r\n].*$", "")
        win.TF.insert(win.input, line)
        return true
    end
    return false
end

function uc.key(win, char, code)
    if win.broken then return false end

    if win.input then
        local handled, action = win.TF.key(win.input, char, code)
        if action == "submit" then
            local value = win.input.text
            local repo, branch = value:match("^%s*([%w%._%-]+/[%w%._%-]+)@([%w%._%-/]+)%s*$")
            if not repo then
                repo = value:match("^%s*([%w%._%-]+/[%w%._%-]+)%s*$"); branch = win.U.BRANCH
            end
            if repo then
                win.U.saveConfig(repo, branch)
                win.result = {ok = true, message = "Збережено: " .. repo .. "@" .. branch .. ". Натисніть «Перевірити»."}
                win.remote, win.entries = nil, {}
                win.input = nil
            else
                win.result = {ok = false, message = "Невірний формат. Приклад: FixlutGames21/FixOS@main"}
            end
        elseif action == "cancel" then
            win.input = nil
        end
        return true
    end

    if win.confirm then
        if code == 1 then win.confirm = nil; return true end
        if code == 28 then
            local f = win.confirm.onYes; win.confirm = nil; if f then f() end
            return true
        end
        return true
    end

    if char == 49 then win.tab = 1; return true
    elseif char == 50 then win.tab = 2; return true
    elseif char == 51 then win.tab = 3; return true
    elseif char == 99 or char == 67 or char == 1089 or char == 1057 then uc.startCheck(win); return true
    elseif char == 32 and win.tab == 1 then
        local e = win.entries[win.cursor]
        if e then win.sel[e.id] = not win.sel[e.id] or nil end
        return true
    end
    if code == 200 then moveSel(win, -1); return true
    elseif code == 208 then moveSel(win, 1); return true
    elseif code == 28 and win.tab == 1 then uc.startUpdate(win, false); return true
    elseif code == 1 and win.job and win.job.state == "running" then win.job:cancel(); return true
    end
    return false
end

function uc.scroll(win, dir)
    moveSel(win, dir > 0 and -2 or 2)
    return true
end

return uc
