-- ==========================================================
-- FixOS 4.0.1 - system/programs/browser.lua
-- FIX 4.0.1:
--   - navigate(): url:match("https?://([^/]+)") can return nil
--     when the URL is malformed.  Concatenating a string with nil
--     crashes Lua.  Fixed with (... or url) grouping.
-- ==========================================================

local browser = {}

local VERSION = "4.0.1"

local BOOKMARKS = {
    {name="Дім",        url="about:home"},
    {name="GitHub",     url="https://github.com"},
    {name="Wikipedia",  url="https://en.m.wikipedia.org/wiki/Main_Page"},
    {name="Pastebin",   url="https://pastebin.com"},
}

-- ============================================================
-- INIT
-- ============================================================
function browser.init(win)
    win.url          = "about:home"
    win.urlBarFocus  = false
    win.urlInput     = ""
    win.lines        = {}
    win.scrollY      = 0
    win.loading      = false
    win.loadStatus   = "Готово"
    win.history      = {}
    win.histIdx      = 0
    win.elements     = {}
    win._ui          = nil

    win._phase       = "idle"
    win._netHandle   = nil
    win._netBuf      = {}
    win._netUrl      = ""
    win._historyNav  = false
    win._timeout     = 0
    win._maxTimeout  = 800
    win._bytesRead   = 0
    win._startTime   = 0

    browser._showHome(win)
end

-- ============================================================
-- HOME PAGE
-- ============================================================
function browser._showHome(win)
    win.lines = {
        "",
        "  \xE2\x95\x94\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x97",
        "  \xE2\x95\x91  FixOS Browser v" .. VERSION .. "                  \xE2\x95\x91",
        "  \xE2\x95\x9A\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x9D",
        "",
        "  Як користуватись:",
        "  -----------------",
        "    [U]     - фокус на адресний рядок",
        "    [Enter] - перейти за адресою",
        "    [<] [>] - назад / вперед",
        "    [R]     - перезавантажити",
        "    [Esc]   - скасувати введення",
        "    Scroll  - прокрутка",
        "",
        "  Підтримується:",
        "  ---------------",
        "    [OK] HTTP / HTTPS запити",
        "    [OK] HTML -> текст (авто-конвертація)",
        "    [OK] Plain text, Markdown, JSON",
        "    [OK] HTTP статус-коди (200, 404, 500...)",
        "    [OK] Закладки",
        "    [OK] Повна історія навігації",
        "",
        "  Приклади адрес:",
        "  ----------------",
        "    github.com",
        "    pastebin.com/raw/xxxxx",
        "    en.m.wikipedia.org/wiki/Lua",
        "",
    }
    win.scrollY    = 0
    win.url        = "about:home"
    win.loadStatus = "Готово | FixOS Browser " .. VERSION
    win.loading    = false
    win._phase     = "idle"
end

-- ============================================================
-- HTML STRIPPER
-- ============================================================
local function stripHtml(raw)
    local s = raw

    s = s:gsub("<[Hh][Ee][Aa][Dd][^>]*>", "\0HEAD\0")
    s = s:gsub("<[Ss][Cc][Rr][Ii][Pp][Tt][^>]*>", "\0SCRIPT\0")
    s = s:gsub("<[Ss][Tt][Yy][Ll][Ee][^>]*>",     "\0STYLE\0")

    local function removeBlock(src, opener, closers)
        local result = {}
        local pos = 1
        while pos <= #src do
            local s1, e1 = src:find(opener, pos, true)
            if not s1 then
                result[#result+1] = src:sub(pos)
                break
            end
            result[#result+1] = src:sub(pos, s1 - 1)
            local best = nil
            for _, cl in ipairs(closers) do
                local s2, e2 = src:find(cl, e1 + 1)
                if s2 and (not best or s2 < best[1]) then
                    best = {s2, e2}
                end
            end
            if not best then break end
            pos = best[2] + 1
        end
        return table.concat(result)
    end

    s = removeBlock(s, "\0HEAD\0",   {"</head>","</HEAD>","</Head>"})
    s = removeBlock(s, "\0SCRIPT\0", {"</script>","</SCRIPT>","</Script>"})
    s = removeBlock(s, "\0STYLE\0",  {"</style>","</STYLE>","</Style>"})

    s = s:gsub("<!%-%-.-%-%->", "")
    s = s:gsub("<[Bb][Rr]%s*/?>",             "\n")
    s = s:gsub("<[Hh][Rr]%s*/?>",             "\n" .. string.rep("-", 40) .. "\n")
    s = s:gsub("<[Pp][^>]*>",                 "\n")
    s = s:gsub("</[Pp]>",                     "\n")
    s = s:gsub("<[Dd][Ii][Vv][^>]*>",         "\n")
    s = s:gsub("</[Dd][Ii][Vv]>",             "\n")
    s = s:gsub("<[Ss][Ee][Cc][Tt][Ii][Oo][Nn][^>]*>", "\n")
    s = s:gsub("<[Aa][Rr][Tt][Ii][Cc][Ll][Ee][^>]*>", "\n")

    for n = 1, 6 do
        local pre = n <= 2 and "==" or (n <= 4 and "--" or "  ")
        s = s:gsub("<[Hh]"..n.."[^>]*>", "\n" .. pre .. " ")
        s = s:gsub("</"  .."[Hh]"..n..">", " " .. pre .. "\n")
    end

    s = s:gsub("<[Uu][Ll][^>]*>", "\n")
    s = s:gsub("<[Oo][Ll][^>]*>", "\n")
    s = s:gsub("<[Ll][Ii][^>]*>", "\n  * ")
    s = s:gsub("<[Tt][Rr][^>]*>", "\n")
    s = s:gsub("<[Tt][Hh][^>]*>", " | ")
    s = s:gsub("<[Tt][Dd][^>]*>", " | ")

    s = s:gsub('<[Aa][^>]*[Hh][Rr][Ee][Ff]="([^"]*)"[^>]*>', "[")
    s = s:gsub("</[Aa]>", "]")

    s = s:gsub("<[Bb][^>]*>",      "**")
    s = s:gsub("</"      .."[Bb]>","**")
    s = s:gsub("<[Ii][^>]*>",      "_")
    s = s:gsub("</"      .."[Ii]>","_")
    s = s:gsub("<[Ss][Tt][Rr][Oo][Nn][Gg][^>]*>", "**")
    s = s:gsub("</"              .."[Ss][Tt][Rr][Oo][Nn][Gg]>", "**")
    s = s:gsub("<[Pp][Rr][Ee][^>]*>", "\n```\n")
    s = s:gsub("</"      .."[Pp][Rr][Ee]>", "\n```\n")
    s = s:gsub("<[^>]*>", "")

    local entities = {
        nbsp=" ", amp="&", lt="<", gt=">", quot='"',
        apos="'", mdash="—", ndash="–", hellip="...",
        copy="(c)", reg="(r)", trade="(tm)", bull="*",
        laquo="<<", raquo=">>",
    }
    s = s:gsub("&(%a+);", function(e)
        return entities[e:lower()] or ("&"..e..";")
    end)
    s = s:gsub("&#(%d+);", function(n)
        local c = tonumber(n)
        return (c and c >= 32 and c <= 126) and string.char(c) or " "
    end)
    s = s:gsub("&#[Xx](%x+);", function(h)
        local c = tonumber(h, 16)
        return (c and c >= 32 and c <= 126) and string.char(c) or " "
    end)

    s = s:gsub("[ \t]+",  " ")
    s = s:gsub("^ +",     "")
    s = s:gsub("\n +",    "\n")
    s = s:gsub(" +\n",    "\n")
    s = s:gsub("\n\n\n+", "\n\n")

    local out = {}
    for line in (s.."\n"):gmatch("([^\n]*)\n") do
        table.insert(out, line)
    end
    while #out > 0 and out[1]:match("^%s*$")   do table.remove(out, 1) end
    while #out > 0 and out[#out]:match("^%s*$") do table.remove(out)   end
    return out
end

-- ============================================================
-- TEXT WRAPPING
-- ============================================================
local function wrapLine(line, w)
    if #line <= w then return {line} end
    local out = {}
    while #line > w do
        local cut = w
        local sp  = line:sub(1, w):match("^(.* )") or ""
        if #sp > w * 0.4 then cut = #sp end
        table.insert(out, line:sub(1, cut))
        line = line:sub(cut + 1)
    end
    if #line > 0 then table.insert(out, line) end
    return out
end

local function wrapLines(lines, w)
    local out = {}
    for _, line in ipairs(lines) do
        for _, wrapped in ipairs(wrapLine(line, w)) do
            table.insert(out, wrapped)
        end
    end
    return out
end

-- ============================================================
-- DRAW
-- ============================================================
function browser.draw(win, gpu, cx, cy, cw, ch)
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

    -- Navigation bar
    gpu.setBackground(T.surfaceAlt)
    gpu.fill(cx, y, cw, 1, " ")

    local hasBack = (win.histIdx > 1)
    gpu.setBackground(hasBack and T.accent or T.surfaceInset)
    gpu.setForeground(T.textOnAccent)
    gpu.set(cx, y, "[<] ")
    table.insert(win.elements, {x=cx, y=y, w=4, h=1, action="back"})

    local hasFwd = (win.histIdx < #win.history)
    gpu.setBackground(hasFwd and T.accent or T.surfaceInset)
    gpu.setForeground(T.textOnAccent)
    gpu.set(cx+4, y, "[>] ")
    table.insert(win.elements, {x=cx+4, y=y, w=4, h=1, action="fwd"})

    local reloadLabel = win.loading and "[X]" or "[R]"
    local reloadBg    = win.loading and T.danger or T.accent
    gpu.setBackground(reloadBg); gpu.setForeground(T.textOnAccent)
    gpu.set(cx+8, y, reloadLabel)
    table.insert(win.elements, {x=cx+8, y=y, w=3, h=1, action=win.loading and "stop" or "reload"})

    local urlBarX = cx + 12
    local urlBarW = cw - 14
    local urlBg   = win.urlBarFocus and T.accentSubtle or T.surfaceInset
    gpu.setBackground(urlBg)
    gpu.fill(urlBarX, y, urlBarW, 1, " ")
    gpu.setForeground(win.urlBarFocus and T.textPrimary or T.textSecondary)
    local displayUrl = win.urlBarFocus and win.urlInput or win.url
    if #displayUrl > urlBarW - 2 then
        displayUrl = "..." .. displayUrl:sub(-(urlBarW - 5))
    end
    gpu.set(urlBarX + 1, y, displayUrl)
    if win.urlBarFocus then
        local cx2 = urlBarX + 1 + #displayUrl
        if cx2 < urlBarX + urlBarW - 1 then
            gpu.setBackground(T.textPrimary); gpu.setForeground(urlBg)
            gpu.set(cx2, y, " ")
        end
    end
    table.insert(win.elements, {x=urlBarX, y=y, w=urlBarW, h=1, action="urlbar"})

    y = cy + 1

    -- Bookmarks bar
    gpu.setBackground(T.surfaceAlt)
    gpu.fill(cx, y, cw, 1, " ")
    local bx = cx + 1
    for _, bm in ipairs(BOOKMARKS) do
        local lbl    = " " .. bm.name .. " "
        local isAct  = (win.url == bm.url)
        if bx + #lbl <= cx + cw - 1 then
            gpu.setBackground(isAct and T.accentDark or T.accent)
            gpu.setForeground(T.textOnAccent)
            gpu.set(bx, y, lbl)
            table.insert(win.elements, {x=bx, y=y, w=#lbl, h=1, action="bookmark", url=bm.url})
            bx = bx + #lbl + 1
        end
    end

    y = cy + 2

    -- Status bar
    local statusBg = win.loading and T.accentSubtle or T.surfaceAlt
    gpu.setBackground(statusBg)
    gpu.fill(cx, y, cw, 1, " ")
    gpu.setForeground(win.loading and T.accent or T.textSecondary)
    gpu.set(cx + 1, y, UI.truncate(win.loadStatus or "Готово", cw - 2))

    y = cy + 3

    -- Content area
    local contentH = ch - 4
    local contentW = cw - 1

    local wrapped   = wrapLines(win.lines, contentW)
    local maxScroll = math.max(0, #wrapped - contentH)
    if win.scrollY > maxScroll then win.scrollY = maxScroll end

    gpu.setBackground(T.surface)
    gpu.fill(cx, y, contentW, contentH, " ")

    for row = 0, contentH - 1 do
        local lineIdx = win.scrollY + row + 1
        local line    = wrapped[lineIdx]
        if line then
            if line:match("^==[^=]") or line:match("==$") then
                gpu.setForeground(T.accent)
            elseif line:match("^%-%- ") or line:match("─") then
                gpu.setForeground(T.textSecondary)
            elseif line:match("^  %* ") or line:match("^ +%| ") then
                gpu.setForeground(T.textSecondary)
            elseif line:match("^```") then
                gpu.setForeground(T.info)
            elseif line:match("^%[") and line:match("%]$") then
                gpu.setForeground(T.info)
            else
                gpu.setForeground(T.textPrimary)
            end
            gpu.setBackground(T.surface)
            gpu.set(cx, y + row, line)
        end
    end

    UI.drawScrollbar(cx + cw - 1, y, contentH,
        math.max(contentH, #wrapped), contentH, win.scrollY)

    -- Footer
    gpu.setBackground(T.surfaceAlt)
    gpu.fill(cx, cy + ch - 1, cw, 1, " ")
    gpu.setForeground(T.textSecondary)
    local footerInfo = string.format(
        "Рядки: %d  Позиція: %d/%d  [U]=адреса  [Esc]=скасувати",
        #wrapped,
        math.min(win.scrollY + 1, #wrapped),
        math.max(1, #wrapped)
    )
    gpu.set(cx + 1, cy + ch - 1, UI.truncate(footerInfo, cw - 2))
end

-- ============================================================
-- TICK - Async network state machine
-- ============================================================
function browser.tick(win)
    if win._phase == "idle" or not win._netHandle then
        return false
    end

    win._timeout = win._timeout + 1
    if win._timeout > win._maxTimeout then
        pcall(win._netHandle.close)
        win._netHandle = nil
        win._phase     = "idle"
        win.loading    = false
        win.lines = {
            "",
            "  [Таймаут]",
            "",
            "  Сервер не відповів за " .. math.floor(win._maxTimeout / 50) .. " секунд.",
            "  URL: " .. (win._netUrl or ""),
            "",
            "  Спробуйте:",
            "    * Перевірте адресу",
            "    * Переконайтесь що Internet Card встановлена",
        }
        win.loadStatus = "Таймаут з'єднання"
        return true
    end

    -- CONNECTING phase: wait for response()
    if win._phase == "connecting" then
        local ok, status, msg, headers = pcall(win._netHandle.response)
        if not ok then
            win.loadStatus = "Підключення... " .. win._timeout .. "t"
            return false
        end

        status = status or 200
        win._httpStatus = status
        win._phase      = "reading"

        if status >= 400 then
            win.loadStatus = string.format("HTTP %d %s", status, msg or "")
            win.lines = {
                "",
                string.format("  [HTTP %d] %s", status, msg or "Помилка"),
                "",
                "  URL: " .. (win._netUrl or ""),
                "",
                "  " .. (status == 404 and "Сторінку не знайдено."  or
                         status == 403 and "Доступ заборонений."      or
                         status == 500 and "Внутрішня помилка сервера." or
                         "Спробуйте пізніше."),
            }
            pcall(win._netHandle.close)
            win._netHandle = nil
            win._phase     = "idle"
            win.loading    = false
            browser._commitHistory(win)
            return true
        end

        win.loadStatus = string.format("Завантаження... HTTP %d", status)
        return false
    end

    -- READING phase
    if win._phase == "reading" then
        local ok, chunk = pcall(win._netHandle.read, 8192)

        if ok and chunk and #chunk > 0 then
            table.insert(win._netBuf, chunk)
            win._bytesRead = win._bytesRead + #chunk
            win.loadStatus = string.format(
                "HTTP %d | Завантаження: %d KB",
                win._httpStatus or 200,
                math.floor(win._bytesRead / 1024)
            )
            return false

        elseif ok and (chunk == nil or chunk == "") then
            browser._finishLoad(win)
            return true

        else
            if win._bytesRead > 0 then
                browser._finishLoad(win)
            else
                win.loading    = false
                win._phase     = "idle"
                win.loadStatus = "Помилка читання даних"
                win.lines = {"", "  [Помилка] Не вдалося прочитати відповідь.", ""}
            end
            pcall(win._netHandle.close)
            win._netHandle = nil
            return true
        end
    end

    return false
end

function browser._finishLoad(win)
    pcall(win._netHandle.close)
    win._netHandle = nil

    local raw    = table.concat(win._netBuf)
    local isHtml = raw:lower():match("<!doctype") or raw:lower():match("<html")
    local lines

    if isHtml then
        lines = stripHtml(raw)
        table.insert(lines, 1, "")
        table.insert(lines, 1, "  URL: " .. (win._netUrl or ""))
        table.insert(lines, 1, string.rep("-", 50))
    else
        lines = {}
        for line in (raw.."\n"):gmatch("([^\n]*)\n") do
            table.insert(lines, line)
        end
    end

    local elapsed  = math.floor((computer.uptime() - (win._startTime or 0)) * 10) / 10
    win.lines      = lines
    win.scrollY    = 0
    win.loading    = false
    win._phase     = "idle"
    win.loadStatus = string.format(
        "HTTP %d | %d KB | %d рядків | %.1f сек",
        win._httpStatus or 200,
        math.floor(#raw / 1024),
        #lines,
        elapsed
    )
    win.url = win._netUrl
    browser._commitHistory(win)
end

function browser._commitHistory(win)
    if win._historyNav then win._historyNav = false; return end
    while #win.history > win.histIdx do table.remove(win.history) end
    if #win.history == 0 or win.history[#win.history] ~= win._netUrl then
        table.insert(win.history, win._netUrl)
    end
    win.histIdx = #win.history
end

-- ============================================================
-- NAVIGATE
-- ============================================================
function browser.navigate(win, url, isHistoryNav)
    url = (url or ""):match("^%s*(.-)%s*$")
    if url == "" then return end

    if url == "about:home" or url == "home" then
        browser._showHome(win)
        if not isHistoryNav then
            while #win.history > win.histIdx do table.remove(win.history) end
            if #win.history == 0 or win.history[#win.history] ~= "about:home" then
                table.insert(win.history, "about:home")
            end
            win.histIdx = #win.history
        end
        return
    end

    if not url:match("^https?://") then
        url = "https://" .. url
    end

    if not component.isAvailable("internet") then
        win.loading    = false
        win._phase     = "idle"
        win.loadStatus = "Немає Internet Card!"
        win.lines = {
            "", "  [Помилка] Немає Internet Card", "",
            "  Потрібна Internet Card T2 або T3.", "",
        }
        return
    end

    if win._netHandle then
        pcall(win._netHandle.close)
        win._netHandle = nil
    end

    -- FIX (Critical Bug #1): `component.internet` relied on OpenOS-style
    -- magic field access. Inside FixOS's own runtime (boot/init.lua's
    -- custom `component` table) that field never existed, so `net` was
    -- always nil here and `net.request` below raised "attempt to index
    -- a nil value" BEFORE pcall could even catch it (pcall's own
    -- arguments are evaluated first) — meaning navigate() to any real
    -- URL silently failed, always, even with an Internet Card present.
    local netAddr = component.list("internet")()
    if not netAddr then
        win.loading    = false
        win._phase     = "idle"
        win.loadStatus = "Internet Card не знайдена"
        win.lines = {
            "", "  [Помилка] Internet Card не знайдена", "",
            "  Встановіть Internet Card T2 або T3.", "",
        }
        return
    end
    local net = component.proxy(netAddr)
    local ok, handle = pcall(net.request, url, nil, {
        ["User-Agent"] = "FixOS/" .. VERSION .. " (OpenComputers)",
        ["Accept"]     = "text/html,text/plain,*/*",
    })

    if not ok or not handle then
        win.loading    = false
        win._phase     = "idle"
        win.loadStatus = "Помилка з'єднання"
        win.lines = {
            "", "  [Помилка] Не вдалося підключитися", "",
            "  URL: " .. url, "",
            "  Можливі причини:",
            "    * Неправильна адреса",
            "    * Сервер недоступний",
            "    * URL заблокований сервером OC",
        }
        return
    end

    win._netHandle  = handle
    win._netBuf     = {}
    win._netUrl     = url
    win._phase      = "connecting"
    win._historyNav = isHistoryNav or false
    win._timeout    = 0
    win._bytesRead  = 0
    win._httpStatus = nil
    win._startTime  = computer.uptime()
    win.loading     = true

    -- FIX: url:match() can return nil for unusual URLs; wrap in (...or url)
    -- so that string concatenation never receives nil.
    win.loadStatus  = "Підключення до " .. (url:match("https?://([^/]+)") or url)

    win.lines = {
        "", "  Завантаження: " .. url, "", "  Будь ласка, зачекайте...",
    }
    win.scrollY = 0
end

-- ============================================================
-- CLICK
-- ============================================================
function browser.click(win, clickX, clickY, btn)
    if not win._ui then return false end
    local UI = win._ui

    for _, elem in ipairs(win.elements) do
        if UI.hitTest(elem, clickX, clickY) then
            if elem.action == "urlbar" then
                win.urlBarFocus = true
                win.urlInput    = win.url
                return true
            elseif elem.action == "back" then
                if win.histIdx > 1 then
                    win.histIdx = win.histIdx - 1
                    browser.navigate(win, win.history[win.histIdx], true)
                end
                return true
            elseif elem.action == "fwd" then
                if win.histIdx < #win.history then
                    win.histIdx = win.histIdx + 1
                    browser.navigate(win, win.history[win.histIdx], true)
                end
                return true
            elseif elem.action == "reload" then
                browser.navigate(win, win.url, true)
                return true
            elseif elem.action == "stop" then
                if win._netHandle then
                    pcall(win._netHandle.close)
                    win._netHandle = nil
                end
                win.loading    = false
                win._phase     = "idle"
                win.loadStatus = "Зупинено"
                return true
            elseif elem.action == "bookmark" then
                win.urlBarFocus = false
                browser.navigate(win, elem.url, false)
                return true
            end
        end
    end

    if win.urlBarFocus then
        win.urlBarFocus = false
        return true
    end
    return false
end

-- ============================================================
-- KEY
-- ============================================================
function browser.key(win, char, code)
    if not win.urlBarFocus and (char == 117 or char == 85) then
        win.urlBarFocus = true
        win.urlInput    = win.url
        return true
    end

    if win.urlBarFocus then
        if code == 28 then
            local url       = win.urlInput
            win.urlBarFocus = false
            browser.navigate(win, url, false)
            return true
        elseif code == 1 then
            win.urlBarFocus = false
            return true
        elseif code == 14 then
            if #win.urlInput > 0 then
                win.urlInput = win.urlInput:sub(1, -2)
                return true
            end
        elseif code == 199 then
            win.urlInput = ""
            return true
        elseif char and char >= 32 and char <= 126 then
            win.urlInput = win.urlInput .. string.char(char)
            return true
        end
    else
        if     code == 200 then win.scrollY = math.max(0, win.scrollY - 1);  return true
        elseif code == 208 then win.scrollY = win.scrollY + 1;               return true
        elseif code == 201 then win.scrollY = math.max(0, win.scrollY - 10); return true
        elseif code == 209 then win.scrollY = win.scrollY + 10;              return true
        elseif code == 199 then win.scrollY = 0;                             return true
        elseif code == 207 then win.scrollY = 99999;                         return true
        elseif code == 203 and win.histIdx > 1 then
            win.histIdx = win.histIdx - 1
            browser.navigate(win, win.history[win.histIdx], true)
            return true
        elseif code == 205 and win.histIdx < #win.history then
            win.histIdx = win.histIdx + 1
            browser.navigate(win, win.history[win.histIdx], true)
            return true
        end
    end
    return false
end

-- ============================================================
-- SCROLL
-- ============================================================
function browser.scroll(win, dir)
    win.scrollY = math.max(0, win.scrollY + (dir > 0 and -3 or 3))
    return true
end

return browser