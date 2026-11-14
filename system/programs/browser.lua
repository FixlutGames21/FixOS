-- ==========================================================
-- FixOS 4.2.0 - system/programs/browser.lua  (ПЕРЕПИСАНО)
--
-- Що нового:
--   * Справжня робота з інтернетом через /system/lib/net.lua:
--     редіректи, коректне читання відповіді, HTTPS->HTTP відкат,
--     TCP-режим, ліміт за пам'яттю, зрозумілі помилки.
--   * Нормальний рендер сторінок (/system/lib/html.lua): заголовки,
--     списки, таблиці, цитати, pre, КЛІКАБЕЛЬНІ посилання, кольори
--     для жирного/курсиву/коду, Unicode (кирилиця).
--   * Адресний рядок = пошук (DuckDuckGo), вставка (Shift+Insert),
--     набір кирилиці, введення "замінює" поточну адресу.
--   * Режим Reader [M] (r.jina.ai) для сайтів, які без JavaScript
--     порожні, а також about:net - діагностика мережі.
--   * Парсинг/розкладка порціями, тому OC не вбиває скрипт
--     "too long without yielding".
-- ==========================================================

local browser = {}

local VERSION = "4.2.0"

local SEARCH_URL = "https://html.duckduckgo.com/html/?q="
local READER_URL = "https://r.jina.ai/"

local BOOKMARKS = {
    {name = "Дім",      url = "about:home"},
    {name = "Вікі",     url = "https://uk.m.wikipedia.org/"},
    {name = "HN",       url = "https://news.ycombinator.com/"},
    {name = "Example",  url = "http://example.com/"},
    {name = "Мережа",   url = "about:net"},
}

local STRONG_COL  = 0x9C2B00
local CODE_COL    = 0x00796B
local VISITED_COL = 0x7B3FA0

local Net, Html, TF

-- ============================================================
-- Бібліотеки (кешуються в _G, щоб не читати диск для кожного вікна)
-- ============================================================
local function loadLibs()
    if Net and Html and TF then return true end
    local ok, err = pcall(function()
        if not _G._FixTF then _G._FixTF = dofile("/system/lib/textfield.lua") end
        TF = _G._FixTF
        if not _G._FixNet then _G._FixNet = dofile("/system/lib/net.lua") end
        if not _G._FixHtml then
            _G._FixHtml = dofile("/system/lib/html.lua")
            _G._FixHtml.Net = _G._FixNet
        end
        Net, Html = _G._FixNet, _G._FixHtml
    end)
    if not ok then return false, tostring(err) end
    return true
end

local function ulen(s)
    if unicode and unicode.len then return unicode.len(s) end
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end

local function usub(s, i, j)
    if unicode and unicode.sub then return unicode.sub(s, i, j) end
    return s:sub(i, j)
end

-- ============================================================
-- Внутрішні сторінки (markdown)
-- ============================================================
local function homeMarkdown()
    return table.concat({
        "# FixOS Browser " .. VERSION,
        "",
        "Текстовий браузер для OpenComputers. Введіть адресу або пошуковий запит у рядку зверху (клавіша **U**).",
        "",
        "## Швидкі посилання",
        "- [Вікіпедія (українська)](https://uk.m.wikipedia.org/)",
        "- [Wikipedia (English)](https://en.m.wikipedia.org/wiki/Main_Page)",
        "- [Hacker News](https://news.ycombinator.com/)",
        "- [NPR - текстова версія](https://text.npr.org/)",
        "- [OpenComputers Wiki](https://ocdoc.cil.li/)",
        "- [Репозиторій FixOS](https://github.com/FixlutGames21/FixOS)",
        "- [Тестова сторінка (HTTP)](http://example.com/)",
        "- [Перший у світі сайт](http://info.cern.ch/)",
        "",
        "## Сервіс",
        "- [Діагностика мережі](about:net)",
        "- [Довідка та гарячі клавіші](about:help)",
        "",
        "Якщо сайт показує порожню сторінку - йому потрібен JavaScript. Спробуйте режим Reader (клавіша **M**).",
    }, "\n")
end

local function helpMarkdown()
    return table.concat({
        "# Довідка",
        "",
        "## Клавіші",
        "- **U** або **/** - адресний рядок (перший символ замінює адресу)",
        "- **Enter** - перейти; **Esc** - скасувати/зупинити",
        "- **Shift+Insert** - вставити з буфера обміну",
        "- **R** - оновити; **H** - додому; **M** - режим Reader",
        "- **Backspace** або **←** - назад; **→** - вперед",
        "- **↑ ↓ PgUp PgDn Home End Пробіл** - прокрутка",
        "",
        "## Адресний рядок",
        "- Слова без крапки (напр. `lua таблиці`) шукаються в DuckDuckGo",
        "- `example.com` автоматично стає `https://example.com`",
        "",
        "## Режим Reader",
        "Адреса надсилається сервісу r.jina.ai, який повертає чистий текст сторінки. Корисно для сайтів на JavaScript і для старої Java без потрібних сертифікатів. Увага: сторонній сервіс бачить, які сторінки ви відкриваєте.",
        "",
        "[← На головну](about:home)",
    }, "\n")
end

local function netMarkdown(win)
    local info = Net.info()
    local function yn(v)
        if v == true then return "так" elseif v == false then return "НІ" end
        return "невідомо"
    end
    local free = "?"
    if computer.freeMemory then
        local ok, f = pcall(computer.freeMemory)
        if ok and f then free = math.floor(f / 1024) .. " КБ" end
    end
    local lines = {
        "# Діагностика мережі",
        "",
        "- Internet Card: **" .. (info.present and "є" or "НЕМАЄ") .. "**",
    }
    if info.address then lines[#lines + 1] = "- Адреса компонента: `" .. info.address .. "`" end
    lines[#lines + 1] = "- HTTP дозволено сервером: **" .. yn(info.http) .. "**"
    lines[#lines + 1] = "- TCP дозволено сервером: **" .. yn(info.tcp) .. "**"
    lines[#lines + 1] = "- Вільна пам'ять: " .. free
    lines[#lines + 1] = "- Максимальний розмір сторінки зараз: " .. math.floor(Net.memoryLimit() / 1024) .. " КБ"
    lines[#lines + 1] = "- Режим Reader: " .. (win.reader and "увімкнено" or "вимкнено")
    lines[#lines + 1] = ""
    if not info.present then
        lines[#lines + 1] = "Встановіть Internet Card (tier 1 або 2) у комп'ютер."
    elseif info.http == false then
        lines[#lines + 1] = "HTTP вимкнено в конфігу сервера (internet.enableHttp). Працює лише TCP-режим для http:// без шифрування."
    else
        lines[#lines + 1] = "Все гаразд. Перевірте з'єднання:"
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Тести"
    lines[#lines + 1] = "- [HTTP: example.com](http://example.com/)"
    lines[#lines + 1] = "- [HTTPS: example.com](https://example.com/)"
    lines[#lines + 1] = "- [HTTPS: Вікіпедія](https://uk.m.wikipedia.org/wiki/Lua)"
    lines[#lines + 1] = "- [HTTPS: GitHub raw](https://raw.githubusercontent.com/FixlutGames21/FixOS/main/README.md)"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Типові проблеми"
    lines[#lines + 1] = "- **PKIX / SSL** - стара Java не довіряє сертифікату сайту. Браузер сам пробує http://, також допоможе Reader."
    lines[#lines + 1] = "- **Адресу заблоковано** - адмін сервера обмежив Internet Card (internet.filteringRules)."
    lines[#lines + 1] = "- **Забагато з'єднань** - картка тримає лише кілька з'єднань одночасно."
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[← На головну](about:home)"
    return table.concat(lines, "\n")
end

-- ============================================================
-- Документ / розкладка
-- ============================================================
local function setDoc(win, doc)
    win.doc       = doc
    win.lines     = {}
    win.laid      = 0
    win.layoutW   = nil
    win.scrollY   = 0
end

local function showMarkdown(win, md, url, title)
    local p = Html.newTextParser(md, url, "md")
    while not p:step(100000) do end
    setDoc(win, p.doc)
    win.url        = url
    win.title      = "Browser"
    win.loading    = false
    win.loadStatus = title or "Готово"
end

local function errorMarkdown(win, req, target)
    local title, hint = req.errTitle or "Помилка", req.errHint or ""
    local lines = {
        "# Не вдалося відкрити сторінку",
        "",
        "**" .. title .. "**",
    }
    if hint ~= "" then lines[#lines + 1] = ""; lines[#lines + 1] = hint end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Адреса: " .. target
    lines[#lines + 1] = ""
    if req.errRaw and req.errRaw ~= "" then
        lines[#lines + 1] = "Технічно: `" .. tostring(req.errRaw):gsub("%s+", " "):sub(1, 160) .. "`"
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Що можна зробити"
    lines[#lines + 1] = "- [Спробувати ще раз](" .. target:gsub("%)", "%%29"):gsub(" ", "%%20") .. ")"
    if not win.reader and target:match("^https?://") then
        lines[#lines + 1] = "- [Відкрити через Reader](about:reader?u=" .. Net.urlencode(target) .. ")"
    end
    lines[#lines + 1] = "- [Діагностика мережі](about:net)"
    lines[#lines + 1] = "- [На головну](about:home)"
    return table.concat(lines, "\n")
end

local function layoutStep(win, nBlocks)
    local doc = win.doc
    if not doc then return false end
    local w = math.max(12, (win._cw or 70) - 1)
    if win.layoutW ~= w then
        win.layoutW = w; win.lines = {}; win.laid = 0
    end
    local did, n = false, 0
    while win.laid < #doc.blocks and n < nBlocks do
        win.laid = win.laid + 1
        Html.layoutBlock(doc.blocks[win.laid], w, win.lines)
        n = n + 1; did = true
    end
    return did
end

-- ============================================================
-- INIT / CLOSE
-- ============================================================
function browser.init(win)
    win.url          = "about:home"
    win.urlBarFocus  = false
    win.scrollY      = 0
    win.loading      = false
    win.loadStatus   = "Готово"
    win.history      = {}
    win.histIdx      = 0
    win.elements     = {}
    win.visited      = {}
    win.reader       = false
    win.lines        = {}
    win.laid         = 0
    win._ui          = nil
    win._lastRedraw  = 0
    win.refreshCount = 0

    local ok, err = loadLibs()
    if not ok then
        win.lines = {"1Помилка", "pНе вдалося завантажити /system/lib/net.lua або html.lua:",
                     "p" .. tostring(err), "pПеревстановіть FixOS (installer.lua)."}
        win.laid = 4; win.layoutW = 0
        win.doc = {blocks = {}, links = {}}
        win.broken = true
        return
    end
    win.urlField = TF.new("", {max = 500})
    browser.navigate(win, "about:home", {})
end

-- Фокус на адресному рядку. fresh=true: текст "виділено" (перший символ замінює його).
function browser.focusUrl(win, text, fresh)
    if win.broken or not win.urlField then return end
    TF.set(win.urlField, text or "", fresh)
    win.urlBarFocus = true
end

-- Викликається desktop.lua при закритті вікна: звільняє з'єднання
function browser.close(win)
    if win.req then pcall(win.req.cancel, win.req); win.req = nil end
    win.parser = nil
end

-- ============================================================
-- Навігація
-- ============================================================
local function classify(input)
    input = input:gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then return nil end
    if input:match("^about:") then return input end
    if input:match("^%a[%w+.-]*://") then return input end
    if not input:find("%s") and (input:find(".", 1, true) or input:find(":", 1, true)
       or input:find("/", 1, true) or input:lower():match("^localhost")) then
        return "https://" .. input
    end
    return SEARCH_URL .. Net.urlencode(input)
end

local function stopRequest(win)
    if win.req then pcall(win.req.cancel, win.req); win.req = nil end
    win.parser = nil
end

local function pushHistory(win, url)
    if win.history[win.histIdx] then win.history[win.histIdx].scroll = win.scrollY end
    while #win.history > win.histIdx do table.remove(win.history) end
    if not win.history[#win.history] or win.history[#win.history].url ~= url then
        win.history[#win.history + 1] = {url = url, scroll = 0}
    end
    win.histIdx = #win.history
    while #win.history > 40 do table.remove(win.history, 1); win.histIdx = win.histIdx - 1 end
end

-- opts: histNav (не додавати в історію), scroll, keepReader, noClassify
function browser.navigate(win, input, opts)
    opts = opts or {}
    if win.broken then return end
    input = tostring(input or "")
    local target = opts.noClassify and input or classify(input)
    if not target then return end

    stopRequest(win)

    -- "https://host" -> "https://host/" (однакові адреси в історії)
    local hostOnly = target:match("^(https?://[^/?#]+)$")
    if hostOnly then target = hostOnly .. "/" end

    -- спеціальні адреси
    local rd = target:match("^about:reader%?u=(.*)$")
    if rd then
        win.reader = true
        target = Net.urldecode(rd)
    end

    if target:match("^about:") then
        if not opts.histNav then pushHistory(win, target) end
        win.restoreScroll = opts.scroll
        if target == "about:net" then
            showMarkdown(win, netMarkdown(win), target, "Діагностика мережі")
        elseif target == "about:help" then
            showMarkdown(win, helpMarkdown(), target, "Довідка")
        else
            showMarkdown(win, homeMarkdown(), "about:home", "FixOS Browser " .. VERSION)
            target = "about:home"
        end
        win.url = target
        if win.restoreScroll then win.scrollY = win.restoreScroll; win.restoreScroll = nil end
        return
    end

    if not target:match("^https?://") then
        showMarkdown(win, "# Непідтримувана адреса\n\nБраузер відкриває лише http:// та https:// адреси.\n\n[На головну](about:home)", "about:error")
        return
    end

    if not Net.available() then
        showMarkdown(win, errorMarkdown(win, {errTitle = "Немає Internet Card",
            errHint = "Встановіть Internet Card у комп'ютер і перезавантажте."}, target), "about:error")
        win.url = target
        win.loadStatus = "Немає Internet Card"
        return
    end

    if not opts.histNav then pushHistory(win, target) end

    local fetchUrl = win.reader and (READER_URL .. target) or target
    win.req          = Net.get(fetchUrl, {})
    win.reqTarget    = target
    win.reqReader    = win.reader
    win.reqScroll    = opts.scroll
    win.loading      = true
    win.parsing      = false
    win.startedAt    = computer.uptime()
    win.loadStatus   = "Підключення до " .. (target:match("^https?://([^/]+)") or target) .. "…"
    win.urlBarFocus  = false
end

-- ============================================================
-- Обробка завершеного завантаження
-- ============================================================
local function looksBinary(body)
    local sample = body:sub(1, 512)
    if sample:find("\0", 1, true) then return true end
    local ctrl = select(2, sample:gsub("[\1-\8\14-\31]", ""))
    return #sample > 0 and ctrl / #sample > 0.1
end

local function pickMode(req, body, reader)
    local ct = req.contentType or ""
    if reader then return "md" end
    if ct:find("html") or ct:find("xhtml") then return "html" end
    if ct:find("markdown") then return "md" end
    if ct:find("^image/") or ct:find("^audio/") or ct:find("^video/")
       or ct:find("pdf") or ct:find("zip") or ct:find("octet%-stream")
       or ct:find("gzip") or ct:find("font") then
        return "binary"
    end
    if ct == "" or ct:find("^text/plain") or ct:find("^application/") or ct:find("^text/") then
        local head = body:sub(1, 1024):lower()
        if head:find("<!doctype html", 1, true) or head:find("<html", 1, true)
           or head:find("<head", 1, true) or head:find("<body", 1, true) then
            return "html"
        end
        if looksBinary(body) then return "binary" end
        local path = (req.url or ""):lower():gsub("[?#].*$", "")
        if path:match("%.md$") or path:match("%.markdown$") then return "md" end
        return "plain"
    end
    return "plain"
end

local function onFetched(win, req)
    local target = win.reqTarget
    local reader = win.reqReader
    win.req = nil

    -- URL після редіректів (для reader показуємо початковий)
    local shownUrl = target
    if not reader and req.url and req.url ~= "" then shownUrl = req.url end
    win.url = shownUrl
    if win.history[win.histIdx] and not reader then win.history[win.histIdx].url = shownUrl end
    win.visited[shownUrl] = true
    win.visited[target] = true

    local body = req.body or ""
    local mode = pickMode(req, body, reader)

    if mode == "binary" then
        local md = table.concat({
            "# Це не текстова сторінка", "",
            "Тип: `" .. ((req.contentType ~= "" and req.contentType) or "невідомо") .. "`",
            "Розмір: " .. math.floor(#body / 1024) .. " КБ" .. (req.truncated and " (обрізано)" or ""), "",
            "Браузер показує лише текст. Зображення, PDF і архіви відкрити неможливо.", "",
            "[Назад на головну](about:home)",
        }, "\n")
        showMarkdown(win, md, shownUrl, "Бінарний файл")
        win.loading = false
        return
    end

    body = Net.toUtf8(body, req.charset)
    local parser
    if mode == "html" then
        parser = Html.newParser(body, shownUrl)
    else
        parser = Html.newTextParser(body, shownUrl, mode == "md" and "md" or "plain")
    end
    parser.mode2 = mode
    parser.hadScript = (mode == "html") and body:find("<script", 1, true) ~= nil
    parser.truncated = req.truncated
    parser.status    = req.status or 200
    parser.bytes     = #body
    parser.notes     = req.notes

    setDoc(win, parser.doc)
    local doc = parser.doc
    if (req.status or 200) >= 400 then
        doc:add("1", "", "", "HTTP " .. tostring(req.status) .. " " .. tostring(req.message or ""))
        doc:gap()
    end

    win.parser = parser
    win.parsing = true
    win.reqScroll2 = win.reqScroll
    win.reqScroll = nil
    win.loadStatus = "Обробка сторінки…"
    win.finalReq = {status = req.status or 200, bytes = #body, elapsed = computer.uptime() - (win.startedAt or 0),
                    notes = req.notes, truncated = req.truncated, redirects = req.redirects}
end

local function onFailed(win, req)
    local target = win.reqTarget or win.url
    win.req = nil
    win.loading = false
    win.parsing = false
    showMarkdown(win, errorMarkdown(win, req, target), "about:error", req.errTitle or "Помилка")
    win.url = target
    win.loadStatus = (req.errTitle or "Помилка")
end

local function finishParsing(win)
    local parser = win.parser
    local doc = win.doc
    local fr = win.finalReq or {}
    win.parser = nil
    win.parsing = false
    win.loading = false

    if parser then
        if parser.truncated then
            doc:gap()
            doc:add("4", "", "", "[Сторінку завантажено частково: ліміт " ..
                math.floor((parser.bytes or 0) / 1024) .. " КБ через обмеження пам'яті]")
        end
        if doc.chars < 120 and parser.hadScript and not win.reqReader then
            doc:gap()
            doc:add("4", "", "", "[Сторінка майже порожня - схоже, їй потрібен JavaScript. Натисніть M (Reader).]")
        end
        if doc.title then win.title = "Browser: " .. doc.title else win.title = "Browser" end
    end

    -- <meta refresh> на майже порожніх сторінках
    if doc.refresh and doc.chars < 300 and win.refreshCount < 3 and not win.reqReader then
        win.refreshCount = win.refreshCount + 1
        local r = doc.refresh
        win.parser = nil
        browser.navigate(win, r, {noClassify = true, histNav = true})
        return
    end
    win.refreshCount = 0

    collectgarbage()

    local kb = math.floor((fr.bytes or 0) / 1024)
    local extra = ""
    if fr.redirects and fr.redirects > 0 then extra = extra .. " | ↪" .. fr.redirects end
    if fr.notes then
        for _, n in ipairs(fr.notes) do
            if n:find("HTTPS не вдався", 1, true) then extra = extra .. " | ⚠ http" end
            if n:find("TCP", 1, true) then extra = extra .. " | TCP" end
        end
    end
    if win.reqReader then extra = extra .. " | Reader" end
    win.loadStatus = string.format("HTTP %d | %d КБ | %d бл. | %.1f с%s",
        fr.status or 200, kb, #doc.blocks, fr.elapsed or 0, extra)

    if win.reqScroll2 then win.scrollY = win.reqScroll2; win.reqScroll2 = nil end
end

-- ============================================================
-- TICK
-- ============================================================
function browser.tick(win)
    if win.broken then return false end
    local changed = false
    local now = computer.uptime()

    -- 1. Мережа
    if win.req then
        local st = win.req:step()
        if st == "done" then
            onFetched(win, win.req); changed = true
        elseif st == "error" then
            onFailed(win, win.req); changed = true
        else
            local r = win.req
            local host = (r.url or ""):match("^https?://([^/]+)") or ""
            if r.phase == "read" or r.phase == "tread" then
                local n = r.bytes or r.rawLen or 0
                win.loadStatus = string.format("Завантаження %s… %d КБ", host, math.floor(n / 1024))
            elseif r.redirects and r.redirects > 0 then
                win.loadStatus = "Перенаправлення → " .. host .. "…"
            else
                win.loadStatus = "Підключення до " .. host .. "…"
            end
            if now - win._lastRedraw > 0.3 then changed = true end
        end
    end

    -- 2. Парсинг порціями
    if win.parser then
        local done = win.parser:step(5000)
        layoutStep(win, 60)
        if done then
            while layoutStep(win, 200) do end
            finishParsing(win)
            changed = true
        else
            local pct = math.floor(100 * win.parser.pos / math.max(1, #win.parser.src))
            win.loadStatus = "Обробка сторінки… " .. math.min(99, pct) .. "%"
            if now - win._lastRedraw > 0.3 then changed = true end
        end
    elseif win.doc and win.laid < #(win.doc.blocks or {}) then
        layoutStep(win, 80); changed = true
    else
        -- зміна ширини вікна (maximize): перебудувати розкладку
        local w = math.max(12, (win._cw or 70) - 1)
        if win.doc and win.layoutW and win.layoutW ~= w then
            layoutStep(win, 80); changed = true
        end
    end

    if changed then win._lastRedraw = now end
    return changed
end

-- ============================================================
-- DRAW
-- ============================================================
local function fgFor(win, T, st, kind)
    if st.link then
        local url = win.doc and win.doc.links and win.doc.links[st.link]
        return (url and win.visited[url]) and VISITED_COL or T.accent
    end
    if kind == "1" then return T.accent end
    if kind == "2" then return T.accentDark end
    if st.code then return CODE_COL end
    if st.strong then return STRONG_COL end
    if st.em then return T.textSecondary end
    if kind == "q" then return T.textSecondary end
    if kind == "c" then return 0x333333 end
    return T.textPrimary
end

local function drawLine(gpu, win, T, x, y, text, kind)
    local st = {strong = (kind == "3" or kind == "4")}
    local col, pos, n = x, 1, #text
    while pos <= n do
        local s = text:find("[\1-\6]", pos)
        local chunk = text:sub(pos, (s or (n + 1)) - 1)
        if #chunk > 0 then
            gpu.setForeground(fgFor(win, T, st, kind))
            gpu.set(col, y, chunk)
            local cl = ulen(chunk)
            if st.link and win.doc.links then
                local url = win.doc.links[st.link]
                if url then
                    win.elements[#win.elements + 1] = {x = col, y = y, w = cl, h = 1, action = "link", url = url}
                end
            end
            col = col + cl
        end
        if not s then break end
        local m = text:byte(s)
        if m == 1 then
            local e = text:find("\2", s + 1, true) or n
            st.link = tonumber(text:sub(s + 1, e - 1))
            pos = e + 1
        else
            if m == 3 then st.link = nil
            elseif m == 4 then st.strong = not st.strong
            elseif m == 5 then st.em = not st.em
            elseif m == 6 then st.code = not st.code end
            pos = s + 1
        end
    end
end

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

    -- ── Панель навігації ─────────────────────────────────
    gpu.setBackground(T.surfaceAlt)
    gpu.fill(cx, y, cw, 1, " ")

    local hasBack = (win.histIdx > 1)
    gpu.setBackground(hasBack and T.accent or T.surfaceInset)
    gpu.setForeground(T.textOnAccent)
    gpu.set(cx, y, "[<] ")
    win.elements[#win.elements + 1] = {x = cx, y = y, w = 4, h = 1, action = "back"}

    local hasFwd = (win.histIdx < #win.history)
    gpu.setBackground(hasFwd and T.accent or T.surfaceInset)
    gpu.set(cx + 4, y, "[>] ")
    win.elements[#win.elements + 1] = {x = cx + 4, y = y, w = 4, h = 1, action = "fwd"}

    gpu.setBackground(win.loading and T.danger or T.accent)
    gpu.setForeground(T.textOnAccent)
    gpu.set(cx + 8, y, win.loading and "[X]" or "[R]")
    win.elements[#win.elements + 1] = {x = cx + 8, y = y, w = 3, h = 1,
                                       action = win.loading and "stop" or "reload"}

    local urlBarX = cx + 12
    local urlBarW = cw - 13
    local urlBg   = win.urlBarFocus and T.accentSubtle or T.surfaceInset
    gpu.setBackground(urlBg)
    gpu.fill(urlBarX, y, urlBarW, 1, " ")
    if win.urlBarFocus and win.urlField then
        -- справжній текстовий курсор: каретка, прокрутка, виділення "fresh"
        TF.draw(gpu, win.urlField, urlBarX + 1, y, urlBarW - 2,
            {fg = T.textPrimary, bg = urlBg, curFg = urlBg, curBg = T.textPrimary,
             selFg = T.textOnAccent, selBg = T.accent}, true)
    else
        gpu.setForeground(T.textSecondary)
        local displayUrl = win.url or ""
        local dl = ulen(displayUrl)
        if dl > urlBarW - 2 then displayUrl = "…" .. usub(displayUrl, dl - (urlBarW - 4), dl) end
        gpu.set(urlBarX + 1, y, displayUrl)
    end
    win.elements[#win.elements + 1] = {x = urlBarX, y = y, w = urlBarW, h = 1, action = "urlbar", x0 = urlBarX + 1}

    -- ── Закладки + Reader ────────────────────────────────
    y = cy + 1
    gpu.setBackground(T.surfaceAlt)
    gpu.fill(cx, y, cw, 1, " ")
    local readerLbl = win.reader and " Reader:ON " or " Reader:off "
    local rW = ulen(readerLbl)
    local bx = cx + 1
    for _, bm in ipairs(BOOKMARKS) do
        local lbl = " " .. bm.name .. " "
        local lw = ulen(lbl)
        if bx + lw <= cx + cw - rW - 2 then
            gpu.setBackground((win.url == bm.url) and T.accentDark or T.accent)
            gpu.setForeground(T.textOnAccent)
            gpu.set(bx, y, lbl)
            win.elements[#win.elements + 1] = {x = bx, y = y, w = lw, h = 1, action = "bookmark", url = bm.url}
            bx = bx + lw + 1
        end
    end
    local rx = cx + cw - rW - 1
    gpu.setBackground(win.reader and T.success or T.surfaceInset)
    gpu.setForeground(win.reader and T.textOnAccent or T.textSecondary)
    gpu.set(rx, y, readerLbl)
    win.elements[#win.elements + 1] = {x = rx, y = y, w = rW, h = 1, action = "reader"}

    -- ── Статус ───────────────────────────────────────────
    y = cy + 2
    local busy = win.loading
    gpu.setBackground(busy and T.accentSubtle or T.surfaceAlt)
    gpu.fill(cx, y, cw, 1, " ")
    if busy then
        UI.spinner(cx + 1, y, math.floor(computer.uptime() * 8), T.accent, T.accentSubtle)
    end
    gpu.setForeground(busy and T.accent or T.textSecondary)
    gpu.setBackground(busy and T.accentSubtle or T.surfaceAlt)
    gpu.set(cx + 3, y, UI.truncate(win.loadStatus or "Готово", cw - 4))

    -- ── Вміст ────────────────────────────────────────────
    y = cy + 3
    local contentH = math.max(1, ch - 4)
    local contentW = cw - 1
    win._contentH = contentH

    local total = #win.lines
    local maxScroll = math.max(0, total - contentH)
    if win.scrollY > maxScroll then win.scrollY = maxScroll end
    if win.scrollY < 0 then win.scrollY = 0 end

    gpu.setBackground(T.surface)
    gpu.fill(cx, y, contentW, contentH, " ")

    for row = 0, contentH - 1 do
        local line = win.lines[win.scrollY + row + 1]
        if line then
            local kind, text = line:sub(1, 1), line:sub(2)
            if kind == "c" then
                gpu.setBackground(T.surfaceAlt)
                gpu.fill(cx, y + row, contentW, 1, " ")
                drawLine(gpu, win, T, cx, y + row, text, kind)
                gpu.setBackground(T.surface)
            elseif kind == "r" then
                gpu.setForeground(T.textDisabled)
                gpu.set(cx, y + row, string.rep("─", contentW))
            elseif kind ~= "b" then
                gpu.setBackground(T.surface)
                drawLine(gpu, win, T, cx, y + row, text, kind)
            end
        end
    end

    UI.drawScrollbar(cx + cw - 1, y, contentH, math.max(contentH, total), contentH, win.scrollY)

    -- ── Підвал ───────────────────────────────────────────
    gpu.setBackground(T.surfaceAlt)
    gpu.fill(cx, cy + ch - 1, cw, 1, " ")
    gpu.setForeground(T.textSecondary)
    local info = string.format("Рядки %d/%d | U адреса  R оновити  M Reader  H дім",
        math.min(win.scrollY + 1, math.max(1, total)), math.max(1, total))
    gpu.set(cx + 1, cy + ch - 1, UI.truncate(info, cw - 2))
end

-- ============================================================
-- CLICK
-- ============================================================
local function goHistory(win, delta)
    local idx = win.histIdx + delta
    if idx < 1 or idx > #win.history then return false end
    if win.history[win.histIdx] then win.history[win.histIdx].scroll = win.scrollY end
    win.histIdx = idx
    local e = win.history[idx]
    browser.navigate(win, e.url, {histNav = true, scroll = e.scroll, noClassify = true})
    return true
end

local function toggleReader(win)
    win.reader = not win.reader
    local u = win.url
    if u and u:match("^https?://") then
        browser.navigate(win, u, {histNav = true, noClassify = true})
    elseif u == "about:net" then
        browser.navigate(win, u, {histNav = true, noClassify = true})
    end
end

function browser.click(win, mx, my, btn)
    if win.broken or not win._ui then return false end
    local UI = win._ui

    for _, e in ipairs(win.elements) do
        if UI.hitTest(e, mx, my) then
            local a = e.action
            if a == "urlbar" then
                if win.urlBarFocus then
                    TF.click(win.urlField, e.x0, mx)          -- каретка в місце кліку
                else
                    TF.set(win.urlField, win.url or "", true) -- виділити все
                    win.urlBarFocus = true
                end
            elseif a == "back" then goHistory(win, -1)
            elseif a == "fwd" then goHistory(win, 1)
            elseif a == "reload" then
                browser.navigate(win, win.url, {histNav = true, noClassify = true})
            elseif a == "stop" then
                stopRequest(win)
                win.loading = false; win.parsing = false
                win.loadStatus = "Зупинено"
            elseif a == "bookmark" then
                win.urlBarFocus = false
                browser.navigate(win, e.url, {noClassify = true})
            elseif a == "reader" then
                toggleReader(win)
            elseif a == "link" then
                win.urlBarFocus = false
                win.visited[e.url] = true
                browser.navigate(win, e.url, {noClassify = true})
            end
            return true
        end
    end

    if win.urlBarFocus then
        win.urlBarFocus = false
        return true
    end
    return false
end

-- ============================================================
-- KEY / PASTE / SCROLL
-- ============================================================
local function scrollBy(win, d)
    local maxS = math.max(0, #win.lines - (win._contentH or 10))
    win.scrollY = math.max(0, math.min(maxS, win.scrollY + d))
end

function browser.paste(win, text)
    if win.broken or type(text) ~= "string" then return false end
    text = text:gsub("[\r\n].*$", ""):gsub("[%z\1-\31\127]", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return false end
    if not win.urlBarFocus then
        TF.set(win.urlField, "", false)
        win.urlBarFocus = true
    end
    TF.insert(win.urlField, text)      -- у позицію каретки (виділений текст замінюється)
    return true
end

function browser.key(win, char, code)
    if win.broken then return false end

    if win.urlBarFocus then
        local handled, action = TF.key(win.urlField, char, code)
        if action == "submit" then
            local u = win.urlField.text
            win.urlBarFocus = false
            browser.navigate(win, u, {})
            return true
        elseif action == "cancel" then
            win.urlBarFocus = false
            return true
        end
        return handled
    end

    -- гарячі клавіші сторінки
    if char == 117 or char == 85 or char == 47 or char == 1075 or char == 1043 then   -- u U / г Г
        browser.focusUrl(win, (char == 47) and "" or (win.url or ""), char ~= 47)
        return true
    elseif char == 114 or char == 82 or char == 1082 or char == 1050 then              -- r R к К
        browser.navigate(win, win.url, {histNav = true, noClassify = true}); return true
    elseif char == 109 or char == 77 or char == 1100 or char == 1068 then              -- m M ь Ь
        toggleReader(win); return true
    elseif char == 104 or char == 72 or char == 1088 or char == 1056 then              -- h H р Р
        browser.navigate(win, "about:home", {noClassify = true}); return true
    elseif char == 32 then scrollBy(win, (win._contentH or 10) - 1); return true
    end

    if code == 1 then
        if win.loading then
            stopRequest(win); win.loading = false; win.parsing = false
            win.loadStatus = "Зупинено"; return true
        end
    elseif code == 200 then scrollBy(win, -1); return true
    elseif code == 208 then scrollBy(win, 1); return true
    elseif code == 201 then scrollBy(win, -((win._contentH or 10) - 1)); return true
    elseif code == 209 then scrollBy(win, (win._contentH or 10) - 1); return true
    elseif code == 199 then win.scrollY = 0; return true
    elseif code == 207 then scrollBy(win, 99999); return true
    elseif code == 14 or code == 203 then return goHistory(win, -1)
    elseif code == 205 then return goHistory(win, 1)
    end
    return false
end

function browser.scroll(win, dir)
    scrollBy(win, dir > 0 and -3 or 3)
    return true
end

return browser
