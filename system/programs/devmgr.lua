-- ==========================================================
-- FixOS 4.3.0 - system/programs/devmgr.lua   (НОВИЙ ФАЙЛ)
-- Device Manager: усі компоненти комп'ютера OpenComputers.
--   * дерево пристроїв за категоріями + розділ "Система"
--   * деталі: computer.getDeviceInfo() та живі параметри
--     (GPU, екран, диски, EEPROM, Internet Card, мережа...)
--   * методи компонента з документацією (component.methods/doc)
--   * автоматичне виявлення підключення/відключення пристроїв
-- ==========================================================

local dm = {}

local CATEGORIES = {
    {id = "system",  name = "Система"},
    {id = "display", name = "Дисплей і введення"},
    {id = "storage", name = "Сховища"},
    {id = "network", name = "Мережа"},
    {id = "other",   name = "Інші пристрої"},
}

local TYPE_INFO = {
    computer   = {"system",  "Комп'ютер"},
    robot      = {"system",  "Робот"},
    drone      = {"system",  "Дрон"},
    gpu        = {"display", "Відеокарта"},
    screen     = {"display", "Екран"},
    keyboard   = {"display", "Клавіатура"},
    hologram   = {"display", "Голопроєктор"},
    filesystem = {"storage", "Файлова система"},
    eeprom     = {"storage", "EEPROM (BIOS)"},
    disk_drive = {"storage", "Дисковод"},
    internet   = {"network", "Інтернет-карта"},
    modem      = {"network", "Мережева карта"},
    tunnel     = {"network", "Лінкований тунель"},
    redstone   = {"other",   "Редстоун"},
    data       = {"other",   "Карта даних"},
    geolyzer   = {"other",   "Геоаналізатор"},
    sign       = {"other",   "Табличка"},
}

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

local function ulen(s)
    if unicode and unicode.len then return unicode.len(s) end
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end

local function fmtBytes(n)
    if type(n) ~= "number" then return tostring(n) end
    if n >= 1048576 then return string.format("%.1f МБ", n / 1048576) end
    if n >= 1024 then return string.format("%.1f КБ", n / 1024) end
    return n .. " Б"
end

local function typeName(ctype)
    local i = TYPE_INFO[ctype]
    return i and i[2] or ctype
end

-- ============================================================
-- Збір даних
-- ============================================================
local function listComponents()
    local out = {}
    for addr, ctype in component.list() do out[#out + 1] = {addr = addr, ctype = ctype} end
    table.sort(out, function(a, b)
        if a.ctype ~= b.ctype then return a.ctype < b.ctype end
        return a.addr < b.addr
    end)
    return out
end

local function signature(list)
    local t = {}
    for _, c in ipairs(list) do t[#t + 1] = c.addr end
    return table.concat(t, ",")
end

local function buildItems(list)
    local byCat = {}
    for _, c in ipairs(list) do
        local cat = (TYPE_INFO[c.ctype] or {"other"})[1]
        byCat[cat] = byCat[cat] or {}
        table.insert(byCat[cat], c)
    end
    local items = {}
    for _, cat in ipairs(CATEGORIES) do
        if cat.id == "system" then
            items[#items + 1] = {kind = "cat", label = cat.name}
            items[#items + 1] = {kind = "sys", label = "Параметри системи"}
            for _, c in ipairs(byCat.system or {}) do
                items[#items + 1] = {kind = "dev", label = typeName(c.ctype), addr = c.addr, ctype = c.ctype}
            end
        elseif byCat[cat.id] then
            items[#items + 1] = {kind = "cat", label = cat.name .. " (" .. #byCat[cat.id] .. ")"}
            for _, c in ipairs(byCat[cat.id]) do
                items[#items + 1] = {kind = "dev", label = typeName(c.ctype), addr = c.addr, ctype = c.ctype}
            end
        end
    end
    return items
end

-- Системна інформація
local function systemLines()
    local L = {}
    local function add(k, v) L[#L + 1] = {k, tostring(v)} end
    add("Архітектура", safe(computer.getArchitecture) or "?")
    local total, free = safe(computer.totalMemory), safe(computer.freeMemory)
    if total then
        add("Пам'ять", string.format("%s вільно з %s (%d%%)", fmtBytes(free or 0), fmtBytes(total),
            math.floor(100 * (total - (free or 0)) / math.max(1, total))))
    end
    local e, me = safe(computer.energy), safe(computer.maxEnergy)
    if e and me then add("Енергія", string.format("%d / %d (%d%%)", e, me, math.floor(100 * e / math.max(1, me)))) end
    local up = safe(computer.uptime)
    if up then add("Працює", string.format("%d хв %d с", math.floor(up / 60), math.floor(up) % 60)) end
    add("Boot-диск", safe(computer.getBootAddress) or "?")
    add("Tmp-диск", safe(computer.tmpAddress) or "?")
    local users = safe(computer.users)
    if type(users) == "string" and users ~= "" then add("Користувачі", users) end
    local n = 0
    for _ in component.list() do n = n + 1 end
    add("Компонентів", n)
    return L
end

-- Деталі пристрою: список {ключ, значення}
local function deviceLines(addr, ctype)
    local L = {}
    local function add(k, v) if v ~= nil then L[#L + 1] = {k, tostring(v)} end end
    add("Тип", ctype .. "  (" .. typeName(ctype) .. ")")
    add("Адреса", addr)

    local info = safe(computer.getDeviceInfo)
    local di = type(info) == "table" and info[addr]
    if type(di) == "table" then
        add("Опис", di.description)
        add("Виробник", di.vendor)
        add("Модель", di.product)
        add("Клас", di["class"])
        if di.capacity then add("Ємність", fmtBytes(tonumber(di.capacity) or 0)) end
        if di.size then add("Розмір", fmtBytes(tonumber(di.size) or 0)) end
        if di.clock then add("Частота/швидкість", di.clock) end
        if di.width then add("Ширина", di.width) end
    end

    local p = safe(component.proxy, addr)
    if p then
        if ctype == "gpu" then
            local mw, mh = safe(p.maxResolution)
            local w, h = safe(p.getResolution)
            if mw then add("Макс. роздільність", mw .. "x" .. tostring(mh)) end
            if w then add("Поточна роздільність", w .. "x" .. tostring(h)) end
            add("Глибина кольору", (safe(p.getDepth) or "?") .. " біт (макс. " .. tostring(safe(p.maxDepth) or "?") .. ")")
            add("Підключено до екрана", safe(p.getScreen))
            local vt, vf = safe(p.totalMemory), safe(p.freeMemory)
            if vt then add("Відеопам'ять", fmtBytes(vf or 0) .. " вільно з " .. fmtBytes(vt)) end
        elseif ctype == "screen" then
            add("Увімкнено", safe(p.isOn) and "так" or "ні")
            local ar1, ar2 = safe(p.getAspectRatio)
            if ar1 then add("Розмір (блоки)", ar1 .. "x" .. tostring(ar2)) end
            add("Точне введення", safe(p.isPrecise) and "так" or "ні")
            local kbs = safe(p.getKeyboards)
            if type(kbs) == "table" then add("Клавіатур", #kbs) end
        elseif ctype == "filesystem" then
            local label = safe(p.getLabel)
            add("Мітка", label or "(немає)")
            local total, used = safe(p.spaceTotal), safe(p.spaceUsed)
            if total then
                add("Місце", string.format("%s використано з %s (%d%%)", fmtBytes(used or 0), fmtBytes(total),
                    math.floor(100 * (used or 0) / math.max(1, total))))
            end
            add("Лише читання", safe(p.isReadOnly) and "так" or "ні")
            if addr == safe(computer.getBootAddress) then add("Роль", "BOOT-диск (з нього завантажено FixOS)") end
            if addr == safe(computer.tmpAddress) then add("Роль", "TMP-диск") end
        elseif ctype == "eeprom" then
            add("Мітка", safe(p.getLabel))
            local sz, dsz = safe(p.getSize), safe(p.getDataSize)
            if sz then add("Розмір коду", fmtBytes(sz)) end
            if dsz then add("Розмір даних", fmtBytes(dsz)) end
            add("Контрольна сума", safe(p.getChecksum))
        elseif ctype == "internet" then
            local h, t = safe(p.isHttpEnabled), safe(p.isTcpEnabled)
            add("HTTP", h == nil and "невідомо" or (h and "дозволено" or "ВИМКНЕНО сервером"))
            add("TCP", t == nil and "невідомо" or (t and "дозволено" or "ВИМКНЕНО сервером"))
        elseif ctype == "modem" then
            add("Бездротовий", safe(p.isWireless) and "так" or "ні")
            add("Макс. розмір пакета", safe(p.maxPacketSize))
            add("Сила сигналу", safe(p.getStrength))
        elseif ctype == "computer" or ctype == "robot" then
            add("Запущено", safe(p.isRunning) and "так" or "ні")
        end
    end
    return L
end

local function methodList(addr)
    local out = {}
    local m = safe(component.methods, addr)
    if type(m) == "table" then
        for name, direct in pairs(m) do out[#out + 1] = {name = name, direct = (direct == true or (type(direct) == "table" and direct.direct))} end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- ============================================================
-- INIT
-- ============================================================
function dm.init(win)
    win.title      = "Device Manager"
    win.list       = listComponents()
    win.sig        = signature(win.list)
    win.items      = buildItems(win.list)
    win.sel        = 2          -- перший пункт після заголовка = "Параметри системи"
    win.lscroll    = 0
    win.rscroll    = 0
    win.view       = "info"     -- info | methods
    win.methods    = {}
    win.msel       = 1
    win.notice     = nil
    win.noticeUntil = 0
    win.lastPoll   = computer.uptime()
    win.elements   = {}
    dm.refreshDetail(win)
end

function dm.refreshDetail(win)
    local it = win.items[win.sel]
    win.rscroll = 0
    if not it or it.kind == "cat" then win.detail = {}; win.methods = {}; return end
    if it.kind == "sys" then
        win.detail = systemLines(); win.methods = {}
    else
        win.detail = deviceLines(it.addr, it.ctype)
        win.methods = methodList(it.addr)
    end
    win.msel = 1
end

local function selectedItem(win) return win.items[win.sel] end

-- ============================================================
-- Опитування змін обладнання
-- ============================================================
function dm.rescan(win, announce)
    local newList = listComponents()
    local sig = signature(newList)
    if sig == win.sig then return false end

    local old, new = {}, {}
    for _, c in ipairs(win.list) do old[c.addr] = c end
    for _, c in ipairs(newList) do new[c.addr] = c end
    if announce then
        for addr, c in pairs(new) do
            if not old[addr] then win.notice = "Підключено: " .. typeName(c.ctype) .. " (" .. addr:sub(1, 8) .. ")" end
        end
        for addr, c in pairs(old) do
            if not new[addr] then win.notice = "Відключено: " .. typeName(c.ctype) .. " (" .. addr:sub(1, 8) .. ")" end
        end
        win.noticeUntil = computer.uptime() + 8
    end

    local keep = selectedItem(win)
    win.list, win.sig = newList, sig
    win.items = buildItems(newList)
    win.sel = 2
    for i, it in ipairs(win.items) do
        if keep and ((keep.kind == "sys" and it.kind == "sys") or (keep.addr and it.addr == keep.addr)) then
            win.sel = i
        end
    end
    dm.refreshDetail(win)
    return true
end

function dm.tick(win)
    local now = computer.uptime()
    local changed = false
    if now - win.lastPoll >= 1.0 then
        win.lastPoll = now
        if dm.rescan(win, true) then changed = true end
        -- "Параметри системи" оновлюються наживо (пам'ять, енергія, uptime)
        local it = selectedItem(win)
        if it and it.kind == "sys" and win.view == "info" then
            win.detail = systemLines(); changed = true
        end
    end
    if win.notice and now > win.noticeUntil then win.notice = nil; changed = true end
    return changed
end

-- ============================================================
-- DRAW
-- ============================================================
local LEFT_W = 26
local KEY_W  = 17

local function usubs(s, i, j)
    if unicode and unicode.sub then return unicode.sub(s, i, j) end
    return s:sub(i, j)
end

-- Перенос значень: довгі рядки не обрізаємо, а продовжуємо на наступному рядку
local function wrapRows(rows, vw)
    local out = {}
    for _, kv in ipairs(rows) do
        local key, text = kv[1], kv[2]
        local pieces, cur = {}, ""
        for word in text:gmatch("%S+") do
            while ulen(word) > vw do
                if cur ~= "" then pieces[#pieces + 1] = cur; cur = "" end
                pieces[#pieces + 1] = usubs(word, 1, vw)
                word = usubs(word, vw + 1)
            end
            if cur == "" then cur = word
            elseif ulen(cur) + 1 + ulen(word) <= vw then cur = cur .. " " .. word
            else pieces[#pieces + 1] = cur; cur = word end
        end
        if cur ~= "" or #pieces == 0 then pieces[#pieces + 1] = cur end
        for i, piece in ipairs(pieces) do
            out[#out + 1] = {i == 1 and key or "", piece}
        end
    end
    return out
end

function dm.draw(win, gpu, cx, cy, cw, ch)
    if not win._ui then
        win._ui = dofile("/system/ui.lua")
        win._ui.init(gpu)
    end
    local UI, T = win._ui, win._ui.Theme
    gpu.setBackground(T.surface); gpu.fill(cx, cy, cw, ch, " ")
    win.elements = {}

    -- панель дій
    gpu.setBackground(T.surfaceAlt); gpu.fill(cx, cy, cw, 1, " ")
    local function btn(x, w, label, style, action)
        UI.drawButton(x, cy, w, 1, label, style, true)
        win.elements[#win.elements + 1] = {x = x, y = cy, w = w, h = 1, action = action}
    end
    btn(cx, 11, "Оновити", "secondary", "refresh")
    btn(cx + 12, 11, "Деталі", win.view == "info" and "accent" or "secondary", "viewInfo")
    btn(cx + 24, 11, "Методи", win.view == "methods" and "accent" or "secondary", "viewMethods")
    gpu.setBackground(T.surfaceAlt)
    if win.notice then
        gpu.setForeground(T.success)
        gpu.set(cx + 37, cy, UI.truncate("● " .. win.notice, cw - 38))
    else
        gpu.setForeground(T.textSecondary)
        gpu.set(cx + 37, cy, UI.truncate("Пристроїв: " .. #win.list, cw - 38))
    end

    local top = cy + 2
    local h   = ch - 3
    win._h = h

    -- ліва панель
    gpu.setBackground(T.surface)
    local maxScroll = math.max(0, #win.items - h)
    if win.lscroll > maxScroll then win.lscroll = maxScroll end
    for row = 1, math.min(h, #win.items - win.lscroll) do
        local idx = win.lscroll + row
        local it = win.items[idx]
        local y = top + row - 1
        if it.kind == "cat" then
            gpu.setBackground(T.surfaceInset); gpu.setForeground(T.textSecondary)
            gpu.fill(cx, y, LEFT_W, 1, " ")
            gpu.set(cx + 1, y, UI.truncate(it.label, LEFT_W - 2))
        else
            local selected = (idx == win.sel)
            gpu.setBackground(selected and T.accent or T.surface)
            gpu.fill(cx, y, LEFT_W, 1, " ")
            gpu.setForeground(selected and T.textOnAccent or T.textPrimary)
            gpu.set(cx + 2, y, UI.truncate(it.label, 18))
            if it.addr then
                gpu.setForeground(selected and T.accentSubtle or T.textDisabled)
                gpu.set(cx + LEFT_W - 9, y, it.addr:sub(1, 7))
            end
            win.elements[#win.elements + 1] = {x = cx, y = y, w = LEFT_W, h = 1, action = "pick", index = idx}
        end
    end
    UI.drawScrollbar(cx + LEFT_W, top, h, math.max(h, #win.items), h, win.lscroll)

    -- права панель
    local rx = cx + LEFT_W + 2
    local rw = cw - LEFT_W - 3
    gpu.setBackground(T.surface)
    local it = selectedItem(win)

    if win.view == "info" or not it or it.kind ~= "dev" then
        local rows = wrapRows(win.detail or {}, rw - KEY_W - 1)
        local maxR = math.max(0, #rows - h)
        if win.rscroll > maxR then win.rscroll = maxR end
        for row = 1, math.min(h, #rows - win.rscroll) do
            local kv = rows[win.rscroll + row]
            local y = top + row - 1
            gpu.setForeground(T.textSecondary)
            gpu.set(rx, y, UI.truncate(kv[1], KEY_W - 1))
            gpu.setForeground(T.textPrimary)
            gpu.set(rx + KEY_W, y, kv[2])
        end
        UI.drawScrollbar(cx + cw - 1, top, h, math.max(h, #rows), h, win.rscroll)
        if #rows == 0 then
            gpu.setForeground(T.textSecondary)
            gpu.set(rx, top, "Виберіть пристрій зліва.")
        end
    else
        -- методи: список + документація внизу
        local docH = 4
        local listH = h - docH - 1
        local ms = win.methods
        local first = math.max(0, math.min(win.msel - 1 - math.floor(listH / 2), #ms - listH))
        first = math.max(0, first)
        for row = 1, math.min(listH, #ms - first) do
            local m = ms[first + row]
            local y = top + row - 1
            local selected = (first + row == win.msel)
            gpu.setBackground(selected and T.accentSubtle or T.surface)
            gpu.fill(rx, y, rw, 1, " ")
            gpu.setForeground(selected and T.accentDark or T.textPrimary)
            gpu.set(rx, y, UI.truncate(m.name, rw - 10))
            gpu.setForeground(T.textDisabled)
            gpu.set(rx + rw - 8, y, m.direct and "direct" or "")
            win.elements[#win.elements + 1] = {x = rx, y = y, w = rw, h = 1, action = "pickMethod", index = first + row}
        end
        gpu.setBackground(T.surface)
        UI.drawDivider(rx, top + listH, rw)
        local m = ms[win.msel]
        if m then
            local doc = safe(component.doc, it.addr, m.name)
            gpu.setForeground(T.textSecondary); gpu.setBackground(T.surface)
            doc = tostring(doc or "(немає документації)")
            for i = 0, docH - 1 do
                local seg = doc:sub(i * rw + 1, (i + 1) * rw)
                if seg ~= "" then gpu.set(rx, top + listH + 1 + i, seg) end
            end
        end
        if #ms == 0 then
            gpu.setForeground(T.textSecondary); gpu.set(rx, top, "Методів немає.")
        end
    end

    gpu.setBackground(T.surface); gpu.setForeground(T.textDisabled)
    gpu.set(cx + 1, cy + ch - 1, UI.truncate("↑↓ вибір · Tab: Деталі/Методи · R оновити · колесо - прокрутка", cw - 2))
end

-- ============================================================
-- INPUT
-- ============================================================
local function moveSel(win, d)
    local i = win.sel
    repeat
        i = i + d
    until i < 1 or i > #win.items or win.items[i].kind ~= "cat"
    if i >= 1 and i <= #win.items then
        win.sel = i
        local h = win._h or 10
        if i <= win.lscroll then win.lscroll = math.max(0, i - 1) end
        if i > win.lscroll + h then win.lscroll = i - h end
        dm.refreshDetail(win)
    end
end

function dm.click(win, mx, my, btn)
    if not win._ui then return false end
    for _, e in ipairs(win.elements) do
        if win._ui.hitTest(e, mx, my) then
            local a = e.action
            if a == "refresh" then
                win.sig = ""; dm.rescan(win, false); dm.refreshDetail(win)
                win.notice = "Список оновлено"; win.noticeUntil = computer.uptime() + 3
            elseif a == "viewInfo" then win.view = "info"
            elseif a == "viewMethods" then win.view = "methods"
            elseif a == "pick" then win.sel = e.index; dm.refreshDetail(win)
            elseif a == "pickMethod" then win.msel = e.index end
            return true
        end
    end
    return false
end

function dm.key(win, char, code)
    if code == 200 then
        if win.view == "methods" and selectedItem(win) and selectedItem(win).kind == "dev" then
            win.msel = math.max(1, win.msel - 1)
        else moveSel(win, -1) end
        return true
    elseif code == 208 then
        if win.view == "methods" and selectedItem(win) and selectedItem(win).kind == "dev" then
            win.msel = math.min(#win.methods, win.msel + 1)
        else moveSel(win, 1) end
        return true
    elseif code == 15 then win.view = (win.view == "info") and "methods" or "info"; return true
    elseif code == 203 then moveSel(win, -1); return true
    elseif code == 205 then moveSel(win, 1); return true
    elseif char == 114 or char == 82 or char == 1082 or char == 1050 then
        win.sig = ""; dm.rescan(win, false)
        win.notice = "Список оновлено"; win.noticeUntil = computer.uptime() + 3
        return true
    end
    return false
end

function dm.scroll(win, dir)
    win.rscroll = math.max(0, win.rscroll + (dir > 0 and -3 or 3))
    return true
end

return dm
