-- ==========================================================
-- FixOS 4.2.0 - system/lib/net.lua   (НОВИЙ ФАЙЛ)
-- Неблокуючий HTTP(S)-клієнт для Internet Card.
--
-- Що виправлено порівняно зі старим browser.lua:
--   * handle.read() повертає "" коли даних ще немає, і nil лише
--     на кінці відповіді. Раніше "" вважалось кінцем -> сторінки
--     обривались одразу (або приходила порожня).
--   * handle.response() до готовності не 200, а "ще немає".
--     Тепер чекаємо finishConnect() (як MineOS) і лише потім
--     беремо статус.
--   * Редіректи (301/302/303/307/308), зокрема http<->https,
--     які Java сама не слідує.
--   * Ліміт розміру відповіді залежно від вільної RAM.
--   * Нормальні повідомлення про помилки (DNS, SSL/PKIX,
--     блокування сервером, вимкнений HTTP, забагато з'єднань).
--   * Запасний канал: якщо HTTP у конфігу сервера вимкнено,
--     http:// працює через сирий TCP (internet.connect).
--   * Перекодування windows-1251 / latin1 у UTF-8.
-- ==========================================================

local Net = {}

Net.USER_AGENT      = "Mozilla/5.0 (compatible; FixOS-Browser/4.2; OpenComputers)"
Net.MAX_BYTES       = 200 * 1024     -- верхня межа тіла відповіді
Net.MIN_BYTES       = 24 * 1024      -- нижня межа при малій RAM
Net.CONNECT_TIMEOUT = 25             -- сек. очікування з'єднання/відповіді
Net.READ_TIMEOUT    = 20             -- сек. без нових даних
Net.MAX_REDIRECTS   = 6
-- Кожен read() в OC - окремий (непрямий) виклик, що займає цілий тік.
-- Тримаємо мало читань за крок, щоб інтерфейс не "завмирав".
Net.READS_PER_STEP  = 3

local function now() return computer.uptime() end

-- ──────────────────────────────────────────────────────────
-- UTF-8 / URL утиліти
-- ──────────────────────────────────────────────────────────
function Net.u8(cp)
    if cp < 0x80 then return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 4096),
                           0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
    else
        return string.char(0xF0 + math.floor(cp / 262144),
                           0x80 + math.floor(cp / 4096) % 64,
                           0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
    end
end

function Net.urlencode(s)
    return (tostring(s):gsub("[^%w%-%._~]", function(c)
        if c == " " then return "+" end
        return string.format("%%%02X", c:byte())
    end))
end

function Net.urldecode(s)
    s = tostring(s):gsub("%+", " ")
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- Розбір URL -> {scheme, host, port, path (з query), authority}
function Net.parseUrl(url)
    if type(url) ~= "string" then return nil end
    local scheme, rest = url:match("^(%a[%w+.-]*)://(.*)$")
    if not scheme then return nil end
    scheme = scheme:lower()
    local authority, tail = rest:match("^([^/?#]*)(.*)$")
    if not authority or authority == "" then return nil end
    tail = tail:gsub("#.*$", "")
    if tail == "" then tail = "/" end
    if tail:sub(1, 1) == "?" then tail = "/" .. tail end
    local userless = authority:gsub("^.*@", "")
    local host, port = userless:match("^(.-):(%d+)$")
    if not host then host = userless end
    if host == "" then return nil end
    port = tonumber(port) or (scheme == "https" and 443 or 80)
    return {scheme = scheme, host = host, port = port, path = tail,
            authority = authority}
end

local function removeDots(path)
    local out = {}
    for seg in (path .. "/"):gmatch("([^/]*)/") do
        if seg == ".." then
            if #out > 1 then table.remove(out) end
        elseif seg ~= "." then
            out[#out + 1] = seg
        end
    end
    local r = table.concat(out, "/")
    if r:sub(1, 1) ~= "/" then r = "/" .. r end
    if path:sub(-1) == "/" and r:sub(-1) ~= "/" then r = r .. "/" end
    return r
end

-- Абсолютний URL з відносного. Фрагмент (#...) відкидається.
function Net.resolve(base, ref)
    ref = (ref or ""):gsub("^%s+", ""):gsub("%s+$", "")
    ref = ref:gsub("#.*$", "")
    if ref == "" then return base end
    if ref:match("^%a[%w+.-]*:") then return ref end
    local b = Net.parseUrl(base or "")
    if not b then return ref end
    local origin = b.scheme .. "://" .. b.authority
    if ref:sub(1, 2) == "//" then return b.scheme .. ":" .. ref end
    if ref:sub(1, 1) == "/" then
        local p, q = ref:match("^([^?]*)(.*)$")
        return origin .. removeDots(p) .. q
    end
    local bpath, _ = b.path:match("^([^?]*)(.*)$")
    if ref:sub(1, 1) == "?" then return origin .. bpath .. ref end
    local dir = bpath:match("^(.*/)") or "/"
    local p, q = ref:match("^([^?]*)(.*)$")
    return origin .. removeDots(dir .. p) .. q
end

-- Регістронезалежний пошук заголовка. Значення може бути рядком або
-- таблицею значень (так повертає OC).
function Net.header(headers, name)
    if type(headers) ~= "table" then return nil end
    name = name:lower()
    for k, v in pairs(headers) do
        if type(k) == "string" and k:lower() == name then
            if type(v) == "table" then return tostring(v[1] or "") end
            return tostring(v)
        end
    end
    return nil
end

-- ──────────────────────────────────────────────────────────
-- Помилки -> людський текст
-- ──────────────────────────────────────────────────────────
local ERRORS = {
    nocard   = {"Немає Internet Card",
                "Встановіть Internet Card у комп'ютер і перезавантажте."},
    badurl   = {"Некоректна адреса", "Перевірте URL."},
    proto    = {"Непідтримуваний протокол",
                "Internet Card вміє лише http:// та https://."},
    dns      = {"Сайт не знайдено (DNS)",
                "Перевірте написання адреси; сервер має бути в інтернеті."},
    refused  = {"З'єднання відхилено", "Сервер не приймає підключення на цьому порту."},
    timeout  = {"Час очікування вичерпано",
                "Сервер не відповів. Спробуйте ще раз або інший сайт."},
    ssl      = {"Помилка HTTPS/сертифіката (SSL/PKIX)",
                "Стара Java на сервері не довіряє сертифікату сайту. Спробуйте http:// або режим Reader [M]."},
    blocked  = {"Адресу заблоковано налаштуваннями сервера",
                "Адмін обмежив Internet Card (internet.filteringRules / blacklist)."},
    disabled = {"HTTP вимкнено на сервері",
                "У конфігурації OpenComputers вимкнено internet.enableHttp."},
    toomany  = {"Забагато відкритих з'єднань",
                "Internet Card тримає обмежену кількість з'єднань. Закрийте інші вкладки браузера й повторіть."},
    lost     = {"З'єднання розірвано", "Сервер обірвав відповідь. Спробуйте ще раз."},
    redirects= {"Забагато перенаправлень", "Сайт зациклює редіректи."},
    httpoff_https = {"HTTPS недоступний",
                "HTTP вимкнено в конфігу, а TCP-режим вміє лише http://."},
    unknown  = {"Помилка мережі", ""},
}

function Net.classify(msg)
    local m = tostring(msg or ""):lower()
    if m:find("pkix") or m:find("ssl") or m:find("handshake")
       or m:find("certificate") or m:find("tls") then return "ssl" end
    if m:find("unknownhost") or m:find("unknown host") or m:find("nodename")
       or m:find("name or service") or m:find("unresolved") then return "dns" end
    if m:find("refused") then return "refused" end
    if m:find("timed out") or m:find("timeout") then return "timeout" end
    if m:find("not allowed") or m:find("blacklist") or m:find("forbidden")
       or m:find("filter") or m:find("whitelist") then return "blocked" end
    if m:find("unavailable") or m:find("disabled") then return "disabled" end
    if m:find("too many") then return "toomany" end
    if m:find("invalid address") or m:find("malformed") then return "badurl" end
    if m:find("unsupported protocol") then return "proto" end
    if m:find("lost") or m:find("reset") or m:find("closed") or m:find("broken pipe") then
        return "lost"
    end
    return "unknown"
end

function Net.describe(code, raw)
    local e = ERRORS[code] or ERRORS.unknown
    return e[1], e[2], raw
end

-- ──────────────────────────────────────────────────────────
-- Картка / діагностика
-- ──────────────────────────────────────────────────────────
local function getCard()
    local it = component.list("internet")
    local addr = it and it()
    if not addr then return nil end
    return component.proxy(addr), addr
end

function Net.available() return getCard() ~= nil end

function Net.info()
    local card, addr = getCard()
    local i = {present = card ~= nil, address = addr}
    if card then
        local ok, v = pcall(card.isHttpEnabled); if ok then i.http = v end
        ok, v = pcall(card.isTcpEnabled);        if ok then i.tcp  = v end
    end
    return i
end

-- Ліміт тіла відповіді з урахуванням вільної пам'яті: після скачування
-- рядок копіюється ще кілька разів (concat, перекодування, парсинг).
function Net.memoryLimit()
    local limit = Net.MAX_BYTES
    if computer.freeMemory then
        local ok, free = pcall(computer.freeMemory)
        if ok and type(free) == "number" then
            limit = math.min(limit, math.floor(free * 0.30))
        end
    end
    return math.max(Net.MIN_BYTES, limit)
end

-- ──────────────────────────────────────────────────────────
-- Request
-- ──────────────────────────────────────────────────────────
local Request = {}
Request.__index = Request

function Net.get(url, opts)
    opts = opts or {}
    local req = setmetatable({
        url        = url,
        method     = opts.method or "GET",
        post       = opts.post,
        extra      = opts.headers,
        maxBytes   = opts.maxBytes or Net.memoryLimit(),
        redirects  = 0,
        state      = "pending",   -- pending | done | error
        phase      = "init",
        bytes      = 0,
        buf        = {},
        notes      = {},
        started    = now(),
        lastProgress = now(),
        downgraded = false,
    }, Request)
    return req
end

function Request:_touch() self.lastProgress = now() end

function Request:close()
    if self.h then pcall(self.h.close); self.h = nil end
end

function Request:cancel()
    self:close()
    if self.state == "pending" then
        self.state = "error"; self.errCode = "cancel"
        self.errTitle = "Скасовано"; self.errHint = ""
    end
end

function Request:_fail(code, raw)
    self:close()
    self.state = "error"
    self.errCode = code
    self.errRaw  = raw
    self.errTitle, self.errHint = Net.describe(code)
end

function Request:_finish(truncated)
    self:close()
    local body = table.concat(self.buf)
    self.buf = {}
    if #body > self.maxBytes then
        body = body:sub(1, self.maxBytes); truncated = true
    end
    self.body      = body
    self.truncated = truncated or false
    self.finalUrl  = self.url
    local ct = Net.header(self.headers, "content-type") or ""
    self.contentType = (ct:match("^%s*([^;%s]+)") or ""):lower()
    self.charset     = (ct:match("[Cc]harset%s*=%s*\"?([%w_%-:.]+)") or ""):lower()
    self.state = "done"
end

local function buildHeaders(self)
    local h = {
        ["User-Agent"]      = Net.USER_AGENT,
        ["Accept"]          = "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5",
        ["Accept-Language"] = "uk,en;q=0.8",
        ["Accept-Encoding"] = "identity",
    }
    if self.post then h["Content-Type"] = "application/x-www-form-urlencoded" end
    if self.extra then for k, v in pairs(self.extra) do h[k] = v end end
    return h
end

function Request:_redirect(location, status)
    self:close()
    if self.redirects >= Net.MAX_REDIRECTS then
        return self:_fail("redirects")
    end
    self.redirects = self.redirects + 1
    local target = Net.resolve(self.url, location)
    if status == 301 or status == 302 or status == 303 then
        self.method = "GET"; self.post = nil
    end
    self.notes[#self.notes + 1] = "→ " .. target
    self.url = target
    self.buf, self.bytes, self.headers, self.status = {}, 0, nil, nil
    self.phase = "init"
    self:_touch()
end

-- Єдина точка після отримання статусу/заголовків
function Request:_gotResponse(status, message, headers)
    self.status, self.message, self.headers = status, message, headers
    self:_touch()
    local loc = Net.header(headers, "location")
    if loc and loc ~= "" and (status == 301 or status == 302 or status == 303
                              or status == 307 or status == 308) then
        return self:_redirect(loc, status)
    end
    self.phase = self.tcp and "tread" or "read"
end

-- ── HTTP-канал (internet.request) ───────────────────────────
function Request:_httpStart()
    local card, hdrs = self.card, buildHeaders(self)
    local ok, h, reason = pcall(card.request, self.url, self.post, hdrs,
                                self.method ~= "GET" and self.method or nil)
    if not ok then
        -- можливо, сервер не дозволяє власні заголовки: пробуємо без них
        local ok2, h2, r2 = pcall(card.request, self.url, self.post)
        if ok2 and h2 then ok, h, reason = true, h2, nil end
    end
    if not ok then
        local code = Net.classify(h)
        if code == "disabled" and self.u.scheme == "http" then
            return self:_tcpStart()
        end
        return self:_fail(code, tostring(h))
    end
    if not h then
        local code = Net.classify(reason)
        if code == "disabled" and self.u.scheme == "http" then
            return self:_tcpStart()
        end
        return self:_fail(code, tostring(reason or "request failed"))
    end
    self.h = h
    self.phase = "connect"
    self:_touch()
end

function Request:_httpConnect()
    local h = self.h
    local hasFc = false
    local okFc, fc = pcall(function() return h.finishConnect end)
    if okFc and fc then hasFc = true end

    if hasFc then
        local ok, res, msg = pcall(fc)
        if not ok then return self:_fail(Net.classify(res), tostring(res)) end
        if res ~= true then
            if msg then return self:_fail(Net.classify(msg), tostring(msg)) end
            return -- ще підключаємось
        end
    end

    local ok, code, msg, headers = pcall(h.response)
    if not ok then
        self.lastErr = tostring(code)
        if hasFc then return self:_fail(Net.classify(code), tostring(code)) end
        return -- чекаємо (старі версії OC)
    end
    if type(code) ~= "number" then return end -- відповіді ще немає
    self:_gotResponse(code, msg, headers)
end

function Request:_httpRead()
    local h = self.h
    for _ = 1, Net.READS_PER_STEP do
        local ok, chunk, reason = pcall(h.read, math.huge)
        if not ok then
            if self.bytes > 0 or (self.status and self.status >= 400) then
                return self:_finish(self.bytes > 0)
            end
            return self:_fail(Net.classify(chunk), tostring(chunk))
        end
        if chunk == nil then
            if reason and self.bytes == 0 and not (self.status and self.status >= 400) then
                return self:_fail(Net.classify(reason), tostring(reason))
            end
            return self:_finish(false)           -- нормальний EOF
        end
        if #chunk == 0 then return end           -- даних ще немає
        self.buf[#self.buf + 1] = chunk
        self.bytes = self.bytes + #chunk
        self:_touch()
        if self.bytes >= self.maxBytes then return self:_finish(true) end
    end
end

-- ── TCP-канал (запасний, лише http://) ──────────────────────
function Request:_tcpStart()
    self.tcp = true
    if self.u.scheme ~= "http" then return self:_fail("httpoff_https") end
    local ok, s, reason = pcall(self.card.connect, self.u.host, self.u.port)
    if not ok then return self:_fail(Net.classify(s), tostring(s)) end
    if not s then return self:_fail(Net.classify(reason), tostring(reason)) end
    self.h = s
    self.phase = "tconnect"
    self.notes[#self.notes + 1] = "TCP-режим"
    self:_touch()
end

function Request:_tcpConnect()
    local ok, res, msg = pcall(self.h.finishConnect)
    if not ok then return self:_fail(Net.classify(res), tostring(res)) end
    if res ~= true then
        if msg then return self:_fail(Net.classify(msg), tostring(msg)) end
        return
    end
    local u = self.u
    local lines = {
        self.method .. " " .. u.path .. " HTTP/1.1",
        "Host: " .. u.authority:gsub("^.*@", ""),
        "User-Agent: " .. Net.USER_AGENT,
        "Accept: text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5",
        "Accept-Language: uk,en;q=0.8",
        "Accept-Encoding: identity",
        "Connection: close",
    }
    if self.post then
        lines[#lines + 1] = "Content-Type: application/x-www-form-urlencoded"
        lines[#lines + 1] = "Content-Length: " .. #self.post
    end
    self.out = table.concat(lines, "\r\n") .. "\r\n\r\n" .. (self.post or "")
    self.outPos = 1
    self.phase = "tsend"
    self:_touch()
end

function Request:_tcpSend()
    for _ = 1, 8 do
        local chunk = self.out:sub(self.outPos, self.outPos + 4095)
        local ok, n = pcall(self.h.write, chunk)
        if not ok then return self:_fail(Net.classify(n), tostring(n)) end
        n = tonumber(n) or #chunk
        self.outPos = self.outPos + n
        self:_touch()
        if self.outPos > #self.out then
            self.out = nil
            self.raw = {}; self.rawLen = 0; self.hdrDone = false
            self.phase = "tread"
            return
        end
        if n == 0 then return end
    end
end

local function decodeChunked(s)
    local out, pos = {}, 1
    while true do
        local lineEnd = s:find("\r\n", pos, true)
        if not lineEnd then break end
        local size = tonumber(s:sub(pos, lineEnd - 1):match("^%s*(%x+)"), 16)
        if not size or size == 0 then break end
        local from = lineEnd + 2
        out[#out + 1] = s:sub(from, from + size - 1)
        pos = from + size + 2
    end
    return table.concat(out)
end

function Request:_tcpRead()
    for _ = 1, Net.READS_PER_STEP do
        local ok, chunk, reason = pcall(self.h.read, math.huge)
        local eof = false
        if not ok then
            if self.rawLen == 0 then return self:_fail(Net.classify(chunk), tostring(chunk)) end
            eof = true
        elseif chunk == nil then
            if reason and self.rawLen == 0 then
                return self:_fail(Net.classify(reason), tostring(reason))
            end
            eof = true
        elseif #chunk == 0 then
            return
        else
            self.raw[#self.raw + 1] = chunk
            self.rawLen = self.rawLen + #chunk
            self:_touch()
        end

        if not self.hdrDone then
            local all = table.concat(self.raw)
            self.raw = {all}
            local he = all:find("\r\n\r\n", 1, true)
            if he then
                local head = all:sub(1, he - 1)
                local status, msg = head:match("^HTTP/%d%.%d%s+(%d+)%s*([^\r\n]*)")
                if not status then return self:_fail("lost", "bad status line") end
                local headers = {}
                for k, v in head:gmatch("\r\n([^:\r\n]+):%s*([^\r\n]*)") do
                    headers[k] = v
                end
                self.hdrDone = true
                self.raw = {all:sub(he + 4)}
                self.rawLen = #self.raw[1]
                self.chunked = (Net.header(headers, "transfer-encoding") or ""):lower():find("chunked") ~= nil
                self.clen = tonumber(Net.header(headers, "content-length"))
                self:_gotResponse(tonumber(status), msg, headers)
                if self.state ~= "pending" or self.phase ~= "tread" then return end
            elseif eof then
                return self:_fail("lost", "no headers")
            end
        end

        if self.hdrDone then
            local complete = eof
            if not self.chunked and self.clen and self.rawLen >= self.clen then
                complete = true
            end
            if self.rawLen >= self.maxBytes + 4096 then complete = true end
            if complete then
                local body = table.concat(self.raw)
                if self.chunked then body = decodeChunked(body) end
                if self.clen and not self.chunked then body = body:sub(1, self.clen) end
                self.buf = {body}
                return self:_finish(self.rawLen >= self.maxBytes + 4096)
            end
        end
    end
end

-- ── Крок автомата ───────────────────────────────────────────
function Request:_step()
    local ph = self.phase
    if ph == "init" then
        local u = Net.parseUrl(self.url)
        if not u then return self:_fail("badurl", tostring(self.url)) end
        if u.scheme ~= "http" and u.scheme ~= "https" then
            return self:_fail("proto", u.scheme)
        end
        local card = getCard()
        if not card then return self:_fail("nocard") end
        self.card, self.u, self.tcp = card, u, false
        local ok, httpOn = pcall(card.isHttpEnabled)
        if ok and httpOn == false then
            if u.scheme == "https" then return self:_fail("httpoff_https") end
            return self:_tcpStart()
        end
        return self:_httpStart()
    elseif ph == "connect" then return self:_httpConnect()
    elseif ph == "read"    then return self:_httpRead()
    elseif ph == "tconnect" then return self:_tcpConnect()
    elseif ph == "tsend"    then return self:_tcpSend()
    elseif ph == "tread"    then return self:_tcpRead()
    end
end

-- Один крок. Повертає "pending" | "done" | "error"
function Request:step()
    if self.state ~= "pending" then return self.state end
    local ok, err = pcall(self._step, self)
    if not ok then self:_fail("unknown", tostring(err)) end

    if self.state == "pending" then
        local idle = now() - self.lastProgress
        local limit = (self.phase == "read" or self.phase == "tread")
                      and Net.READ_TIMEOUT or Net.CONNECT_TIMEOUT
        if idle > limit then
            if (self.phase == "read" and self.bytes > 0) then
                self:_finish(true)
            elseif self.phase == "tread" and self.rawLen and self.rawLen > 0 and self.hdrDone then
                self.buf = {table.concat(self.raw)}
                self:_finish(true)
            else
                self:_fail("timeout", self.lastErr)
            end
        end
    end

    -- Автоматичний відкат https -> http при помилці сертифіката
    if self.state == "error" and self.errCode == "ssl" and not self.downgraded
       and self.method == "GET" and self.url:sub(1, 8) == "https://" then
        self.downgraded = true
        self.url = "http://" .. self.url:sub(9)
        self.notes[#self.notes + 1] = "HTTPS не вдався, пробую http://"
        self.state, self.phase = "pending", "init"
        self.errCode, self.errTitle, self.errHint = nil, nil, nil
        self.buf, self.bytes = {}, 0
        self:_touch()
    end
    return self.state
end

-- ──────────────────────────────────────────────────────────
-- Перекодування в UTF-8
-- ──────────────────────────────────────────────────────────
local CP1251_LOW = {
    0x0402,0x0403,0x201A,0x0453,0x201E,0x2026,0x2020,0x2021,0x20AC,0x2030,0x0409,0x2039,0x040A,0x040C,0x040B,0x040F,
    0x0452,0x2018,0x2019,0x201C,0x201D,0x2022,0x2013,0x2014,0x003F,0x2122,0x0459,0x203A,0x045A,0x045C,0x045B,0x045F,
    0x00A0,0x040E,0x045E,0x0408,0x00A4,0x0490,0x00A6,0x00A7,0x0401,0x00A9,0x0404,0x00AB,0x00AC,0x00AD,0x00AE,0x0407,
    0x00B0,0x00B1,0x0406,0x0456,0x0491,0x00B5,0x00B6,0x00B7,0x0451,0x2116,0x0454,0x00BB,0x0458,0x0405,0x0455,0x0457,
}

local function fromCp1251(s)
    return (s:gsub("[\128-\255]", function(c)
        local b = c:byte()
        if b >= 0xC0 then return Net.u8(0x0410 + b - 0xC0) end
        return Net.u8(CP1251_LOW[b - 0x7F])
    end))
end

local function fromLatin1(s)
    return (s:gsub("[\128-\255]", function(c)
        local b = c:byte()
        if b < 0xA0 then return "" end
        return Net.u8(b)
    end))
end

-- Визначає кодування (заголовок, потім <meta>) і конвертує в UTF-8.
function Net.toUtf8(body, charset)
    local cs = charset or ""
    if cs == "" then
        local head = body:sub(1, 2048)
        cs = (head:match("[Cc][Hh][Aa][Rr][Ss][Ee][Tt]%s*=%s*[\"']?([%w_%-:.]+)") or ""):lower()
    end
    if not body:find("[\128-\255]") then return body end
    if cs:find("1251") or cs == "cp1251" or cs:find("win%-1251") then
        return fromCp1251(body)
    elseif cs:find("8859%-1$") or cs == "latin1" or cs:find("1252") then
        return fromLatin1(body)
    end
    return body
end

return Net
