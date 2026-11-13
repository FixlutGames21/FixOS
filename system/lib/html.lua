-- ==========================================================
-- FixOS 4.2.0 - system/lib/html.lua   (НОВИЙ ФАЙЛ)
-- HTML / Markdown / plain-text -> документ для текстового екрана.
--
-- Документ = список "блоків" (рядків із розміткою), які пізніше
-- розкладаються по ширині вікна (layoutBlock). Інлайнова розмітка
-- кодується керуючими байтами (в тексті сторінки їх немає, бо
-- вони вирізаються):
--     \1<id>\2   початок посилання №id      \3  кінець посилання
--     \4 / \5 / \6   перемикачі: жирний / курсив / код
-- Формат блоку:  <вид> <first> \7 <cont> \7 <текст>
--   вид: p звичайний, 1/2/3/4 заголовки, q цитата, c код/plain,
--        r лінія, b порожній рядок
--   first / cont - префікси першого та наступних рядків (відступи,
--        маркери списку, смужка цитати).
-- Парсинг іде порціями (step), щоб не впертись у ліміт OC
-- "too long without yielding".
-- ==========================================================

local Html = {}
Html.Net = nil          -- заповнює browser.lua (потрібен resolve/urldecode)

Html.MAX_BLOCKS = 6000
Html.MAX_LINKS  = 2500

-- ──────────────────────────────────────────────────────────
-- Unicode-хелпери
-- ──────────────────────────────────────────────────────────
local function ulen(s)
    if unicode and unicode.len then return unicode.len(s) end
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end
Html.ulen = ulen

local function spaces(n) return string.rep(" ", math.max(0, n)) end

local function isWide(cp)
    return (cp >= 0x1100 and cp <= 0x115F) or (cp >= 0x2E80 and cp <= 0xA4CF)
        or (cp >= 0xAC00 and cp <= 0xD7A3) or (cp >= 0xF900 and cp <= 0xFAFF)
        or (cp >= 0xFE30 and cp <= 0xFE6F) or (cp >= 0xFF00 and cp <= 0xFF60)
        or (cp >= 0xFFE0 and cp <= 0xFFE6) or cp >= 0x10000
end

local function isZero(cp)
    return (cp >= 0x300 and cp <= 0x36F) or (cp >= 0x200B and cp <= 0x200F)
        or (cp >= 0x202A and cp <= 0x202E) or (cp >= 0x2060 and cp <= 0x2064)
        or (cp >= 0xFE00 and cp <= 0xFE0F) or cp == 0xFEFF or cp == 0xAD
end

-- Перевіряє UTF-8, прибирає нульової ширини символи, а широкі
-- (CJK/емодзі) замінює на "?", бо вони ламають сітку екрана.
function Html.clean(s)
    if not s:find("[\128-\255]") then return s end
    return (s:gsub("[\128-\255][\128-\191]*", function(seq)
        local b = seq:byte(1)
        local n, cp
        if b < 0xC2 then return "?"
        elseif b < 0xE0 then n, cp = 2, b - 0xC0
        elseif b < 0xF0 then n, cp = 3, b - 0xE0
        elseif b < 0xF5 then n, cp = 4, b - 0xF0
        else return "?" end
        if #seq < n then return "?" end
        for i = 2, n do cp = cp * 64 + (seq:byte(i) - 128) end
        local rest = (#seq > n) and "?" or ""
        if (n == 3 and cp < 0x800) or (n == 4 and cp < 0x10000)
           or (cp >= 0xD800 and cp <= 0xDFFF) or cp > 0x10FFFF then
            return "?" .. rest
        end
        if isZero(cp) then return rest end
        if isWide(cp) then return "?" .. rest end
        return seq:sub(1, n) .. rest
    end))
end

local ENT = {
    nbsp=" ", amp="&", lt="<", gt=">", quot='"', apos="'", mdash="—",
    ndash="–", hellip="…", copy="©", reg="®", trade="™", bull="•",
    laquo="«", raquo="»", ldquo="“", rdquo="”", lsquo="‘", rsquo="’",
    sbquo="‚", bdquo="„", middot="·", times="×", divide="÷", deg="°",
    plusmn="±", euro="€", pound="£", yen="¥", cent="¢", sect="§",
    para="¶", larr="←", rarr="→", uarr="↑", darr="↓", harr="↔",
    check="✓", infin="∞", ne="≠", le="≤", ge="≥", micro="µ", hearts="♥",
    shy="", zwj="", zwnj="", ensp=" ", emsp=" ", thinsp=" ", lrm="", rlm="",
}

local function u8(cp)
    return Html.Net and Html.Net.u8(cp) or "?"
end

local function decodeEntities(s)
    if not s:find("&", 1, true) then return s end
    s = s:gsub("&#[xX](%x+);", function(h) return u8(tonumber(h, 16) or 63) end)
    s = s:gsub("&#(%d+);", function(d)
        local n = tonumber(d)
        if not n or n > 0x10FFFF then return "?" end
        return u8(n)
    end)
    s = s:gsub("&(%a[%w]*);", function(e) return ENT[e] or ENT[e:lower()] or ("&" .. e .. ";") end)
    return s
end
Html.decodeEntities = decodeEntities

local BAD_CTRL = "[\0-\8\14-\31\127]"

-- ──────────────────────────────────────────────────────────
-- Документ
-- ──────────────────────────────────────────────────────────
local BLANK = "b\7\7"

local Doc = {}
Doc.__index = Doc

local function newDoc()
    return setmetatable({blocks = {}, links = {}, linkIndex = {},
                         title = nil, chars = 0, truncated = false,
                         refresh = nil}, Doc)
end

function Doc:addLink(url)
    local id = self.linkIndex[url]
    if id then return id end
    if #self.links >= Html.MAX_LINKS then return nil end
    id = #self.links + 1
    self.links[id] = url
    self.linkIndex[url] = id
    return id
end

function Doc:add(kind, first, cont, text)
    if #self.blocks >= Html.MAX_BLOCKS then
        if not self.truncated then
            self.truncated = true
            self.blocks[#self.blocks + 1] = "4\7\7" .. "[… сторінку обрізано: забагато вмісту]"
        end
        return false
    end
    self.blocks[#self.blocks + 1] = kind .. (first or "") .. "\7" .. (cont or "") .. "\7" .. (text or "")
    return true
end

function Doc:gap()
    local b = self.blocks
    if #b > 0 and b[#b] ~= BLANK then self:add("b", "", "", "") end
end

-- Правила переписування посилань пошукових систем (прямий URL замість редіректу)
local function fixLink(url)
    local q = url:match("^https?://[%w%.]*duckduckgo%.com/l/%?(.*)$")
    if q then
        local target = q:match("uddg=([^&]+)")
        if target and Html.Net then return Html.Net.urldecode(target) end
    end
    return url
end

local function navigable(url)
    return url:match("^https?://") or url:match("^about:")
end

-- ──────────────────────────────────────────────────────────
-- HTML-парсер
-- ──────────────────────────────────────────────────────────
local Parser = {}
Parser.__index = Parser

local SKIP = {script=true, style=true, svg=true, template=true, noscript=true,
              iframe=true, canvas=true, select=true, object=true, head=false}

local BLOCK = {div=true, section=true, article=true, header=true, footer=true,
               nav=true, main=true, aside=true, form=true, fieldset=true,
               address=true, figure=true, figcaption=true, details=true,
               summary=true, center=true, body=true, caption=true,
               thead=true, tbody=true, tfoot=true, html=true, dl=true,
               menu=true, dir=true, legend=true}

local STRONG = {b=true, strong=true, th=false}
local EM     = {i=true, em=true, cite=true, dfn=true, var=true, u=true}
local CODE   = {code=true, kbd=true, samp=true, tt=true}

function Html.newParser(src, baseUrl)
    local p = setmetatable({
        src = src, pos = 1, base = baseUrl or "", doc = newDoc(),
        buf = {}, hasText = false, spacePending = false,
        lst = {}, quote = 0, dd = false,
        heading = nil, pending = nil, link = nil,
        strong = 0, em = 0, code = 0, cells = 0, finished = false,
    }, Parser)
    return p
end

function Parser:openers()
    local o = {}
    if self.link then o[#o + 1] = "\1" .. self.link .. "\2" end
    if self.strong > 0 then o[#o + 1] = "\4" end
    if self.em > 0 then o[#o + 1] = "\5" end
    if self.code > 0 then o[#o + 1] = "\6" end
    return o
end

function Parser:flush()
    local text = table.concat(self.buf)
    self.buf = self:openers()
    self.hasText = false
    self.spacePending = false

    local stripped = text:gsub("\1%d+\2", ""):gsub("[\3-\6]", "")
    if stripped:match("^[%s]*$") then return end

    text = text:gsub("^[ \n]+", ""):gsub("[ \n]+$", "")
    text = text:gsub(" *\n *", "\n"):gsub("\n\n\n+", "\n\n")

    local lst = self.lst
    local outer = 0
    for i = 1, #lst - 1 do outer = outer + lst[i].pad end
    local inner = (#lst > 0) and lst[#lst].pad or 0
    if self.dd then outer = outer + 2 end
    if outer + inner > 24 then outer = math.max(0, 24 - inner) end
    local bars = (self.quote > 0) and string.rep("│ ", math.min(self.quote, 3)) or ""
    local first = bars .. spaces(outer) .. (self.pending or spaces(inner))
    local cont  = bars .. spaces(outer + inner)
    self.pending = nil

    local kind = self.heading or ((self.quote > 0) and "q" or "p")
    self.doc:add(kind, first, cont, text)
end

function Parser:emit(s)
    self.buf[#self.buf + 1] = s
    self.hasText = true
    self.doc.chars = self.doc.chars + #s
end

function Parser:text(raw)
    local s = decodeEntities(raw)
    s = s:gsub(BAD_CTRL, "")
    s = Html.clean(s)
    if s:match("^%s*$") then
        if self.hasText then self.spacePending = true end
        return
    end
    local lead  = s:match("^%s") ~= nil
    local trail = s:match("%s$") ~= nil
    s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if self.hasText and (lead or self.spacePending) then s = " " .. s end
    self:emit(s)
    self.spacePending = trail
end

local function parseAttrs(str)
    local attrs, pos, n = {}, 1, #str
    while pos <= n do
        local s, e, name = str:find("^%s*([%a_:][%w:_%-]*)", pos)
        if not s then
            pos = pos + 1
        else
            pos = e + 1
            local val = ""
            local s2, e2 = str:find("^%s*=%s*", pos)
            if s2 then
                pos = e2 + 1
                local q = str:sub(pos, pos)
                if q == '"' or q == "'" then
                    local close = str:find(q, pos + 1, true) or (n + 1)
                    val = str:sub(pos + 1, close - 1)
                    pos = close + 1
                else
                    local _, e3, v = str:find("^([^%s]*)", pos)
                    val = v or ""
                    pos = (e3 or pos) + 1
                end
            end
            attrs[name:lower()] = val
        end
    end
    return attrs
end

local function findTagEnd(src, from)
    local pos = from
    for _ = 1, 10 do
        local gt = src:find(">", pos, true)
        if not gt then return nil end
        local seg = src:sub(from, gt)
        if not seg:find("[\"']") then return gt end
        local _, dq = seg:gsub('"', "")
        local _, sq = seg:gsub("'", "")
        if dq % 2 == 0 and sq % 2 == 0 then return gt end
        pos = gt + 1
    end
    return src:find(">", from, true)
end

local function ci(name)   -- регістронезалежний шаблон
    return (name:gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end))
end

-- Позиція після закриваючого тега </name> (або кінець рядка)
function Parser:skipBlock(name, from)
    local s, e = self.src:find("</" .. ci(name) .. "%s*>", from)
    if not s then
        s = self.src:find("</" .. ci(name), from)
        if not s then return #self.src + 1, nil end
        local gt = self.src:find(">", s, true)
        return (gt or #self.src) + 1, s
    end
    return e + 1, s
end

function Parser:pushLink(href)
    href = decodeEntities(href):gsub("^%s+", ""):gsub("%s+$", "")
    if href == "" or href:sub(1, 1) == "#" then return end
    local url = Html.Net.resolve(self.base, href)
    url = fixLink(url)
    if not navigable(url) then return end
    local id = self.doc:addLink(url)
    if not id then return end
    if self.link then self.buf[#self.buf + 1] = "\3" end
    self.link = id
    self.buf[#self.buf + 1] = "\1" .. id .. "\2"
end

function Parser:endLink()
    if self.link then
        self.buf[#self.buf + 1] = "\3"
        self.link = nil
    end
end

function Parser:openTag(name, attrStr, gt)
    local src, doc = self.src, self.doc

    if SKIP[name] then
        return (self:skipBlock(name, gt + 1))
    end

    if name == "title" then
        local nextPos, closeAt = self:skipBlock("title", gt + 1)
        if closeAt and not doc.title then
            local t = decodeEntities(src:sub(gt + 1, closeAt - 1))
            t = Html.clean(t:gsub(BAD_CTRL, ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
            if t ~= "" then doc.title = t end
        end
        return nextPos
    end

    if name == "p" then self:flush(); doc:gap()
    elseif BLOCK[name] then self:flush()
    elseif name:match("^h[1-6]$") then
        self:flush(); doc:gap()
        local lv = tonumber(name:sub(2))
        self.heading = (lv <= 3) and tostring(lv) or "4"
    elseif name == "ul" or name == "ol" then
        self:flush()
        if #self.lst == 0 then doc:gap() end
        self.lst[#self.lst + 1] = {ordered = (name == "ol"), n = 0, pad = 0}
    elseif name == "li" then
        self:flush()
        if #self.lst == 0 then self.lst[1] = {ordered = false, n = 0, pad = 0} end
        local L = self.lst[#self.lst]
        L.n = L.n + 1
        local prefix = L.ordered and (L.n .. ". ") or "• "
        L.pad = ulen(prefix)
        self.pending = prefix
    elseif name == "dt" then
        self:flush(); self.dd = false
        self.strong = self.strong + 1; self.buf[#self.buf + 1] = "\4"
    elseif name == "dd" then
        self:flush(); self.dd = true
    elseif name == "blockquote" then
        doc:gap(); self:flush(); self.quote = self.quote + 1
    elseif name == "pre" then
        doc:gap(); self:flush()
        local nextPos, closeAt = self:skipBlock("pre", gt + 1)
        local body = src:sub(gt + 1, (closeAt or (#src + 1)) - 1)
        body = body:gsub("<[^>]*>", "")
        body = decodeEntities(body):gsub(BAD_CTRL, ""):gsub("\r", ""):gsub("\t", "    ")
        body = Html.clean(body):gsub("^\n", ""):gsub("\n+$", "")
        for line in (body .. "\n"):gmatch("([^\n]*)\n") do
            if not doc:add("c", "", "", line) then break end
            doc.chars = doc.chars + #line
        end
        doc:gap()
        return nextPos
    elseif name == "hr" then
        self:flush(); doc:add("r", "", "", "")
    elseif name == "br" then
        self.buf[#self.buf + 1] = "\n"; self.spacePending = false
    elseif name == "a" then
        local at = parseAttrs(attrStr)
        if at.href then self:pushLink(at.href) end
    elseif STRONG[name] then
        self.strong = self.strong + 1
        if self.strong == 1 then self.buf[#self.buf + 1] = "\4" end
    elseif EM[name] then
        self.em = self.em + 1
        if self.em == 1 then self.buf[#self.buf + 1] = "\5" end
    elseif CODE[name] then
        self.code = self.code + 1
        if self.code == 1 then self.buf[#self.buf + 1] = "\6" end
    elseif name == "img" then
        local at = parseAttrs(attrStr)
        local alt = at.alt and decodeEntities(at.alt):gsub("%s+", " ") or ""
        alt = Html.clean(alt:gsub(BAD_CTRL, ""))
        if alt ~= "" and alt ~= " " then
            if self.hasText and self.spacePending then self:emit(" ") end
            self:emit("‹" .. alt .. "›")
            self.spacePending = true
        elseif self.link then
            self:emit("‹img›"); self.spacePending = true
        end
    elseif name == "table" then
        doc:gap(); self:flush(); self.cells = 0
    elseif name == "tr" then
        self:flush(); self.cells = 0
    elseif name == "td" or name == "th" then
        if self.cells > 0 then self:emit(" │ "); self.spacePending = false end
        self.cells = self.cells + 1
    elseif name == "base" then
        local at = parseAttrs(attrStr)
        if at.href and at.href:match("^https?://") then self.base = at.href end
    elseif name == "meta" then
        local at = parseAttrs(attrStr)
        if (at["http-equiv"] or ""):lower() == "refresh" and at.content then
            local u = at.content:match("[Uu][Rr][Ll]%s*=%s*['\"]?([^'\";]+)")
            if u then doc.refresh = Html.Net.resolve(self.base, decodeEntities(u)) end
        end
    end
end

function Parser:closeTag(name)
    local doc = self.doc
    if name == "p" then self:flush(); doc:gap()
    elseif name:match("^h[1-6]$") then self:flush(); self.heading = nil; doc:gap()
    elseif name == "ul" or name == "ol" then
        self:flush(); self.lst[#self.lst] = nil
        if #self.lst == 0 then doc:gap() end
    elseif name == "li" then self:flush()
    elseif name == "dt" then
        if self.strong > 0 then self.strong = self.strong - 1; self.buf[#self.buf + 1] = "\4" end
        self:flush()
    elseif name == "dd" then self:flush(); self.dd = false
    elseif name == "blockquote" then
        self:flush(); self.quote = math.max(0, self.quote - 1); doc:gap()
    elseif name == "a" then self:endLink()
    elseif STRONG[name] then
        self.strong = math.max(0, self.strong - 1)
        if self.strong == 0 then self.buf[#self.buf + 1] = "\4" end
    elseif EM[name] then
        self.em = math.max(0, self.em - 1)
        if self.em == 0 then self.buf[#self.buf + 1] = "\5" end
    elseif CODE[name] then
        self.code = math.max(0, self.code - 1)
        if self.code == 0 then self.buf[#self.buf + 1] = "\6" end
    elseif name == "table" then self:flush(); doc:gap()
    elseif name == "tr" then self:flush(); self.cells = 0
    elseif BLOCK[name] then self:flush()
    end
end

function Parser:tag(lt)
    local src = self.src
    local c2 = src:sub(lt + 1, lt + 1)
    if c2 == "!" then
        if src:sub(lt, lt + 3) == "<!--" then
            local _, e = src:find("-->", lt + 4, true)
            return (e or #src) + 1
        end
        local gt = src:find(">", lt, true)
        return (gt or #src) + 1
    elseif c2 == "?" then
        local gt = src:find(">", lt, true)
        return (gt or #src) + 1
    elseif c2 == "/" then
        local name, e = src:match("^</%s*([%a][%w:%-]*)()", lt)
        if not name then return lt + 2 end
        local gt = src:find(">", e, true)
        self:closeTag(name:lower())
        return (gt or #src) + 1
    end
    local name, e = src:match("^<([%a][%w:%-]*)()", lt)
    if not name then
        self:text("<")
        return lt + 1
    end
    local gt = findTagEnd(src, e)
    if not gt then
        return #src + 1
    end
    local np = self:openTag(name:lower(), src:sub(e, gt - 1), gt)
    return np or (gt + 1)
end

function Parser:finish()
    self.finished = true
    self:flush()
    local b = self.doc.blocks
    while #b > 0 and b[#b] == BLANK do b[#b] = nil end
end

-- Обробити порцію даних. Повертає true коли все готово.
function Parser:step(budget)
    if self.finished then return true end
    local src = self.src
    local n = #src
    local stopAt = self.pos + (budget or 6000)
    local pos = self.pos
    while pos <= n and pos <= stopAt and not self.doc.truncated do
        local lt = src:find("<", pos, true)
        if not lt then
            self:text(src:sub(pos)); pos = n + 1; break
        end
        if lt > pos then self:text(src:sub(pos, lt - 1)) end
        pos = self:tag(lt)
    end
    self.pos = pos
    if pos > n or self.doc.truncated then
        self:finish()
        return true
    end
    return false
end

-- ──────────────────────────────────────────────────────────
-- Markdown / plain text
-- ──────────────────────────────────────────────────────────
local TextParser = {}
TextParser.__index = TextParser

function Html.newTextParser(src, baseUrl, mode)
    return setmetatable({
        src = src, pos = 1, base = baseUrl or "", mode = mode or "plain",
        doc = newDoc(), para = {}, fence = false, finished = false,
    }, TextParser)
end

function TextParser:link(url)
    url = fixLink(Html.Net.resolve(self.base, url))
    if not navigable(url) then return nil end
    return self.doc:addLink(url)
end

function TextParser:inline(s)
    local doc = self.doc
    s = s:gsub("!%[([^%]]*)%]%(([^)]*)%)", function(alt)
        if alt == "" then return "" end
        return "‹" .. alt .. "›"
    end)
    s = s:gsub("%[([^%]]+)%]%(([^)%s]+)[^)]*%)", function(text, url)
        local id = self:link(url)
        if not id then return text end
        return "\1" .. id .. "\2" .. text .. "\3"
    end)
    s = s:gsub("%*%*([^*]+)%*%*", "\4%1\4")
    s = s:gsub("`([^`]+)`", "\6%1\6")
    return s
end

function TextParser:linkify(s)
    return (s:gsub("https?://[^%s<>\"')%]]+", function(url)
        local trail = url:match("[%.,;:!?]+$") or ""
        if trail ~= "" then url = url:sub(1, #url - #trail) end
        local id = self:link(url)
        if not id then return url .. trail end
        return "\1" .. id .. "\2" .. url .. "\3" .. trail
    end))
end

function TextParser:flushPara()
    if #self.para == 0 then return end
    local text = table.concat(self.para, " ")
    self.para = {}
    text = text:gsub("%s+", " ")
    self.doc:add("p", "", "", text)
    self.doc.chars = self.doc.chars + #text
end

local function prep(line)
    line = line:gsub("\r", ""):gsub(BAD_CTRL, ""):gsub("\t", "    ")
    return Html.clean(line)
end

function TextParser:line(raw)
    local doc = self.doc
    local line = prep(raw)

    if self.mode == "plain" then
        local t = self:linkify(line)
        doc:add("c", "", "", t)
        doc.chars = doc.chars + #line
        return
    end

    -- markdown
    if line:match("^%s*```") or line:match("^%s*~~~") then
        self:flushPara(); self.fence = not self.fence; return
    end
    if self.fence then doc:add("c", "", "", line); doc.chars = doc.chars + #line; return end

    if line:match("^%s*$") then
        self:flushPara(); doc:gap(); return
    end
    local hashes, htext = line:match("^%s*(#+)%s+(.-)%s*#*%s*$")
    if hashes then
        self:flushPara(); doc:gap()
        local lv = math.min(#hashes, 6)
        doc:add(lv <= 3 and tostring(lv) or "4", "", "", self:inline(htext))
        doc.chars = doc.chars + #htext
        doc:gap(); return
    end
    if line:match("^%s*%-%-%-+%s*$") or line:match("^%s*%*%*%*+%s*$") or line:match("^%s*___+%s*$") then
        self:flushPara(); doc:add("r", "", "", ""); return
    end
    local sp, rest = line:match("^(%s*)[%-%*%+]%s+(.+)$")
    local prefix
    if sp then prefix = "• " else
        local sp2, num, rest2 = line:match("^(%s*)(%d+)[%.%)]%s+(.+)$")
        if sp2 then sp, rest, prefix = sp2, rest2, num .. ". " end
    end
    if sp then
        self:flushPara()
        local ind = spaces(math.min(8, math.floor(#sp / 2) * 2))
        doc:add("p", ind .. prefix, ind .. spaces(ulen(prefix)), self:inline(rest))
        doc.chars = doc.chars + #rest
        return
    end
    local q = line:match("^%s*>%s?(.*)$")
    if q then
        self:flushPara()
        doc:add("q", "│ ", "│ ", self:inline(q)); doc.chars = doc.chars + #q
        return
    end
    if line:match("^%s*|") then
        self:flushPara()
        if line:match("^[%s|:%-]+$") then return end
        local cells = line:gsub("^%s*|", ""):gsub("|%s*$", ""):gsub("%s*|%s*", " │ ")
        doc:add("p", "", "  ", self:inline(cells)); doc.chars = doc.chars + #cells
        return
    end
    self.para[#self.para + 1] = self:inline((line:gsub("^%s+", ""):gsub("%s+$", "")))
    doc.chars = doc.chars + #line
end

function TextParser:step(budget)
    if self.finished then return true end
    local src, n = self.src, #self.src
    local count, limit = 0, budget and math.max(40, math.floor(budget / 40)) or 200
    while self.pos <= n and count < limit and not self.doc.truncated do
        local e = src:find("\n", self.pos, true)
        local line = src:sub(self.pos, (e or (n + 1)) - 1)
        self.pos = (e or n) + 1
        self:line(line)
        count = count + 1
    end
    if self.pos > n or self.doc.truncated then
        self.finished = true
        if self.mode ~= "plain" then self:flushPara() end
        local b = self.doc.blocks
        while #b > 0 and b[#b] == BLANK do b[#b] = nil end
        return true
    end
    return false
end

-- ──────────────────────────────────────────────────────────
-- Розкладка по ширині
-- ──────────────────────────────────────────────────────────
local function openersOf(st)
    local o = ""
    if st.link then o = o .. "\1" .. st.link .. "\2" end
    if st.strong then o = o .. "\4" end
    if st.em then o = o .. "\5" end
    if st.code then o = o .. "\6" end
    return o
end

local function applyMarkers(st, s)
    for m, d in s:gmatch("([\1\3\4\5\6])(%d*)") do
        if m == "\1" then st.link = tonumber(d)
        elseif m == "\3" then st.link = nil
        elseif m == "\4" then st.strong = not st.strong
        elseif m == "\5" then st.em = not st.em
        else st.code = not st.code end
    end
end

local function visLen(w)
    if w:find("[\1-\6]") then
        w = w:gsub("\1%d+\2", "")
        w = w:gsub("[\3-\6]", "")
    end
    return ulen(w)
end

-- Посимвольне розбиття (для довгих слів і блоків 'c').
-- line/lw/st передаються по значенню, повертаються оновленими.
local function placeChars(word, width, line, lw, st, cont, contW, kind, out)
    local i, n = 1, #word
    while i <= n do
        local b = word:byte(i)
        if b == 1 then
            local e = word:find("\2", i, true) or n
            local m = word:sub(i, e)
            applyMarkers(st, m); line[#line + 1] = m; i = e + 1
        elseif b >= 3 and b <= 6 then
            local m = word:sub(i, i)
            applyMarkers(st, m); line[#line + 1] = m; i = i + 1
        else
            local len = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
            local ch = word:sub(i, i + len - 1); i = i + len
            if lw >= width then
                out[#out + 1] = kind .. table.concat(line)
                line = {cont .. openersOf(st)}; lw = contW
            end
            line[#line + 1] = ch; lw = lw + 1
        end
    end
    return line, lw
end

local function wrapText(text, width, first, cont, kind, out)
    local firstW, contW = ulen(first), ulen(cont)
    if firstW > width - 8 then first, cont, firstW, contW = "", "", 0, 0 end
    if contW > width - 8 then cont, contW = "", 0 end
    local st = {}
    local isFirst = true

    for seg in (text .. "\n"):gmatch("([^\n]*)\n") do
        local prefix, pw = cont, contW
        if isFirst then prefix, pw = first, firstW; isFirst = false end
        local line, lw, hasWord = {prefix .. openersOf(st)}, pw, false

        for word in seg:gmatch("[^ ]+") do
            local vl = visLen(word)
            local need = vl + (hasWord and 1 or 0)
            if lw + need > width and hasWord then
                out[#out + 1] = kind .. table.concat(line)
                line = {cont .. openersOf(st)}; lw = contW; hasWord = false
                need = vl
            end
            if vl > width - lw then
                if hasWord then line[#line + 1] = " "; lw = lw + 1 end
                line, lw = placeChars(word, width, line, lw, st, cont, contW, kind, out)
            else
                if hasWord then line[#line + 1] = " " end
                line[#line + 1] = word
                lw = lw + need
                applyMarkers(st, word)
            end
            hasWord = true
        end
        out[#out + 1] = kind .. table.concat(line)
    end
end

local function hardWrap(text, width, first, cont, kind, out)
    local firstW, contW = ulen(first), ulen(cont)
    local st = {}
    if text == "" then out[#out + 1] = kind .. first; return end
    local line, lw = {first}, firstW
    line, lw = placeChars(text, width, line, lw, st, cont, contW, kind, out)
    out[#out + 1] = kind .. table.concat(line)
end

-- Додає в out готові рядки ("<вид><текст>") для одного блоку.
function Html.layoutBlock(block, width, out)
    width = math.max(12, width)
    local kind = block:sub(1, 1)
    if kind == "b" or kind == "r" then out[#out + 1] = kind; return end
    local s1 = block:find("\7", 2, true)
    local s2 = s1 and block:find("\7", s1 + 1, true)
    if not s2 then return end
    local first = block:sub(2, s1 - 1)
    local cont  = block:sub(s1 + 1, s2 - 1)
    local text  = block:sub(s2 + 1)
    if kind == "c" then hardWrap(text, width, first, cont, kind, out)
    else wrapText(text, width, first, cont, kind, out) end
end

-- Інструменти для відображення
function Html.stripMarkers(s)
    s = s:gsub("\1%d+\2", "")
    return (s:gsub("[\3-\6]", ""))
end

return Html
