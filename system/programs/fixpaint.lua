-- ==========================================================
-- FixOS 4.3.0 - system/programs/fixpaint.lua   (НОВИЙ ФАЙЛ)
-- FixPaint - растровий редактор для екрана OpenComputers.
--
-- Полотно малюється "напівблоками" (символ ▀): кожна клітинка
-- екрана = 2 квадратні пікселі (верхній - колір символу,
-- нижній - колір фону). Колір пікселя - довільний 0xRRGGBB.
--
--   Інструменти: олівець, гумка, лінія, прямокутник, еліпс,
--                заливка, піпетка. Товщина 1-5, суцільні фігури.
--   Ліва кнопка - основний колір, права - фоновий.
--   Скасувати/повторити (зміни, а не знімки - економить RAM).
--   Файли: /pictures/*.fpt (стиснення RLE, текстовий формат).
--
-- Для малювання мишею desktop.lua передає події drag/drop.
-- КУРСОР. За замовчуванням - режим КЛІТИНОК: координати миші такі
-- самі, як у всій системі (вони точно збігаються з тим, що ви бачите),
-- пензель займає клітинку цілком (2 пікселі).
-- Кнопка "Точно" вмикає точний режим екрана T3 (півклітинки = окремі
-- пікселі). У цьому режимі деякі екрани віддають координати зі зсувом
-- (клік лягає на клітинку вище/лівіше), тому при вмиканні запускається
-- КАЛІБРУВАННЯ: 3 кліки по мітках. Поправка зберігається у
-- /system/fixpaint.cfg і застосовується в desktop.lua до всіх подій
-- миші, поки точний режим увімкнено (тож і заголовок вікна, і кнопки
-- влучають правильно).
-- Окрім того є РУЧНИЙ ЗСУВ курсора в пікселях полотна (кнопка "Курсор",
-- клавіша N): +x - вправо, +y - вниз. За замовчуванням (+1, +2): клік
-- реєструється на клітинку лівіше й вище за курсор (виміряно за скріншотом),
-- тож пікселі ставляться на 1 колонку правіше та 1 клітинку (2 пікселі)
-- нижче. Зсув діє в обох режимах (у режимі клітинок вертикальний зсув діє
-- кроками по 2 пікселі - це одна клітинка). Кнопка "Калібрувати" вимірює
-- зсув автоматично: 3 кліки по мітках (в режимі клітинок - цілі клітинки).
-- ==========================================================

local paint = {}

local PICTURES_DIR = "/pictures"
local SIDE_W       = 17
local MAX_UNDO_ENTRIES = 60000   -- триплетів*3 у стеку скасування
local MAX_DIM      = 160

local PAL = {
    0x000000, 0x404040, 0x808080, 0xC0C0C0, 0xFFFFFF, 0x8B4513, 0x800000, 0xFF0000,
    0xFF8000, 0xFFFF00, 0x80FF00, 0x00A000, 0x008080, 0x00FFFF, 0x0080FF, 0x0000FF,
    0x4B0082, 0x8000FF, 0xFF00FF, 0xFF80C0, 0xFFA080, 0xD2B48C, 0x808000, 0x004000,
    0x000080, 0x4682B4, 0xFFDDBB, 0xFFD700, 0xF5F5DC, 0x400000, 0x000040, 0x400040,
}

local TOOLS = {
    {id = "pencil",  label = "Олівець",    key = "B"},
    {id = "eraser",  label = "Гумка",      key = "E"},
    {id = "line",    label = "Лінія",      key = "L"},
    {id = "rect",    label = "Прямокутник",key = "R"},
    {id = "ellipse", label = "Еліпс",      key = "O"},
    {id = "fill",    label = "Заливка",    key = "F"},
    {id = "picker",  label = "Піпетка",    key = "I"},
}

local HALF = "\xE2\x96\x80"   -- ▀

-- ============================================================
-- Чисті алгоритми (використовуються й тестами)
-- ============================================================
local core = {}
paint._core = core

function core.bresenham(x0, y0, x1, y1, fn)
    local dx, dy = math.abs(x1 - x0), math.abs(y1 - y0)
    local sx = (x0 < x1) and 1 or -1
    local sy = (y0 < y1) and 1 or -1
    local err = dx - dy
    while true do
        fn(x0, y0)
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 > -dy then err = err - dy; x0 = x0 + sx end
        if e2 < dx then err = err + dx; y0 = y0 + sy end
    end
end

function core.rectOutline(x0, y0, x1, y1, fn)
    if x0 > x1 then x0, x1 = x1, x0 end
    if y0 > y1 then y0, y1 = y1, y0 end
    for x = x0, x1 do fn(x, y0); fn(x, y1) end
    for y = y0 + 1, y1 - 1 do fn(x0, y); fn(x1, y) end
end

function core.rectFilled(x0, y0, x1, y1, fn)
    if x0 > x1 then x0, x1 = x1, x0 end
    if y0 > y1 then y0, y1 = y1, y0 end
    for y = y0, y1 do for x = x0, x1 do fn(x, y) end end
end

function core.ellipse(x0, y0, x1, y1, filled, fn)
    if x0 > x1 then x0, x1 = x1, x0 end
    if y0 > y1 then y0, y1 = y1, y0 end
    local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    local a, b = (x1 - x0) / 2, (y1 - y0) / 2
    if a < 0.5 or b < 0.5 then core.bresenham(x0, y0, x1, y1, fn); return end
    local floor = math.floor
    for y = y0, y1 do
        local t = (y - cy) / b
        local w = a * math.sqrt(math.max(0, 1 - t * t))
        local xl, xr = floor(cx - w + 0.5), floor(cx + w + 0.5)
        if filled then
            for x = xl, xr do fn(x, y) end
        else
            fn(xl, y); fn(xr, y)
        end
    end
    if not filled then
        for x = x0, x1 do
            local t = (x - cx) / a
            local h = b * math.sqrt(math.max(0, 1 - t * t))
            fn(x, floor(cy - h + 0.5)); fn(x, floor(cy + h + 0.5))
        end
    end
end

-- Заливка (4-зв'язна). Повертає кількість змінених пікселів.
function core.floodFill(px, W, H, x, y, newColor, setFn)
    if x < 0 or y < 0 or x >= W or y >= H then return 0 end
    local start = y * W + x + 1
    local target = px[start]
    if target == newColor then return 0 end
    local stack, sp, n = {start}, 1, 0
    while sp > 0 do
        local i = stack[sp]; sp = sp - 1
        if px[i] == target then
            setFn(i, newColor); n = n + 1
            local cx = (i - 1) % W
            if cx > 0     then sp = sp + 1; stack[sp] = i - 1 end
            if cx < W - 1 then sp = sp + 1; stack[sp] = i + 1 end
            if i > W      then sp = sp + 1; stack[sp] = i - W end
            if i <= W * (H - 1) then sp = sp + 1; stack[sp] = i + W end
        end
    end
    return n
end

-- Формат .fpt: "FPNT1 w h" + по рядку на кожен рядок пікселів: "кількість*RRGGBB ..."
function core.encode(px, W, H)
    local out = {"FPNT1 " .. W .. " " .. H}
    for y = 0, H - 1 do
        local row, run, cur = {}, 0, nil
        for x = 1, W do
            local c = px[y * W + x]
            if c == cur then run = run + 1
            else
                if cur then row[#row + 1] = run .. "*" .. string.format("%06X", cur) end
                cur, run = c, 1
            end
        end
        row[#row + 1] = run .. "*" .. string.format("%06X", cur)
        out[#out + 1] = table.concat(row, " ")
    end
    return table.concat(out, "\n") .. "\n"
end

function core.decode(text)
    local W, H = text:match("^FPNT1 (%d+) (%d+)")
    W, H = tonumber(W), tonumber(H)
    if not W or not H or W < 1 or H < 1 or W > MAX_DIM or H > MAX_DIM then
        return nil, "Невірний заголовок або розмір (макс. " .. MAX_DIM .. ")"
    end
    local px, y = {}, 0
    local first = true
    for line in text:gmatch("[^\r\n]+") do
        if first then first = false
        else
            local x = 0
            for count, hex in line:gmatch("(%d+)%*(%x+)") do
                local n, c = tonumber(count), tonumber(hex, 16)
                if x + n > W then return nil, "Рядок " .. (y + 1) .. " довший за ширину" end
                for _ = 1, n do px[y * W + x + 1] = c; x = x + 1 end
            end
            if x ~= W then return nil, "Рядок " .. (y + 1) .. " має " .. x .. " пікселів замість " .. W end
            y = y + 1
            if y > H then return nil, "Забагато рядків" end
        end
    end
    if y ~= H then return nil, "Рядків " .. y .. " замість " .. H end
    return px, W, H
end

-- ============================================================
-- Полотно: запис змін (для скасування)
-- ============================================================
local function newCanvas(win, W, H)
    win.W, win.H = W, H
    win.px = {}
    for i = 1, W * H do win.px[i] = 0xFFFFFF end
    win.ox, win.oy = 0, 0
    win.undo, win.redo, win.undoSize = {}, {}, 0
    win.stroke, win.dirty = {}, {}
    win.drawing = nil
    win.modified = false
end

local function setPx(win, x, y, color)
    if x < 0 or y < 0 or x >= win.W or y >= win.H then return end
    local i = y * win.W + x + 1
    local old = win.px[i]
    if old == color then return end
    local s = win.stroke
    s[#s + 1] = i; s[#s + 1] = old; s[#s + 1] = color
    win.px[i] = color
    win.dirty[#win.dirty + 1] = i
end

local function stamp(win, x, y, color)
    local n = win.size
    local lo = -math.floor((n - 1) / 2)
    local hi = lo + n - 1
    for dy = lo, hi do
        for dx = lo, hi do setPx(win, x + dx, y + dy, color) end
    end
end

-- Режим клітинок: пензель вирівняний по клітинках (кожна = 2 пікселі по вертикалі).
-- cr - абсолютний рядок клітинок. Розмір n пікселів у ширину і ~n у висоту.
local function stampCell(win, x, cr, color)
    local n = win.size
    local lo = -math.floor((n - 1) / 2)
    local hi = lo + n - 1
    local n2 = math.ceil(n / 2)
    local clo = -math.floor((n2 - 1) / 2)
    local chi = clo + n2 - 1
    for dc = clo, chi do
        for h = 0, 1 do
            local py = 2 * (cr + dc) + h
            for dx = lo, hi do setPx(win, x + dx, py, color) end
        end
    end
end

local function revertStroke(win)
    local s = win.stroke
    for k = #s - 2, 1, -3 do
        win.px[s[k]] = s[k + 1]
        win.dirty[#win.dirty + 1] = s[k]
    end
    win.stroke = {}
end

local function commitStroke(win)
    local s = win.stroke
    if #s == 0 then return false end
    win.undo[#win.undo + 1] = s
    win.undoSize = win.undoSize + #s
    win.redo = {}
    while win.undoSize > MAX_UNDO_ENTRIES and #win.undo > 1 do
        win.undoSize = win.undoSize - #table.remove(win.undo, 1)
    end
    win.stroke = {}
    win.modified = true
    return true
end

local function undo(win)
    local s = table.remove(win.undo)
    if not s then return false end
    for k = #s - 2, 1, -3 do win.px[s[k]] = s[k + 1] end
    win.undoSize = win.undoSize - #s
    win.redo[#win.redo + 1] = s
    win.modified = true
    return true
end

local function redo(win)
    local s = table.remove(win.redo)
    if not s then return false end
    for k = 1, #s, 3 do win.px[s[k]] = s[k + 2] end
    win.undo[#win.undo + 1] = s
    win.undoSize = win.undoSize + #s
    win.modified = true
    return true
end

paint._internal = {setPx = setPx, stamp = stamp, stampCell = stampCell, commitStroke = commitStroke, undo = undo, redo = redo,
                   newCanvas = newCanvas, revertStroke = revertStroke}

-- ============================================================
-- Файли
-- ============================================================
local function getFs() return component.proxy(computer.getBootAddress()) end

local TF
local function loadTF()
    if TF then return TF end
    if not _G._FixTF then _G._FixTF = dofile("/system/lib/textfield.lua") end
    TF = _G._FixTF
    return TF
end

local function ensureDir(fs)
    if not fs.exists(PICTURES_DIR) then fs.makeDirectory(PICTURES_DIR) end
end

local function saveFile(win, path)
    local fs = getFs()
    ensureDir(fs)
    local data = core.encode(win.px, win.W, win.H)
    local h = fs.open(path, "w")
    if not h then return false, "Не вдалося відкрити файл для запису" end
    local ok = true
    for i = 1, #data, 4096 do
        if fs.write(h, data:sub(i, i + 4095)) == false then ok = false; break end
    end
    fs.close(h)
    if not ok then return false, "Помилка запису (диск повний?)" end
    win.filepath = path
    win.modified = false
    return true
end

local function loadFile(win, path)
    local fs = getFs()
    local h = fs.open(path, "r")
    if not h then return false, "Файл не знайдено" end
    local parts = {}
    while true do
        local chunk = fs.read(h, 4096)
        if not chunk then break end
        parts[#parts + 1] = chunk
    end
    fs.close(h)
    local px, W, H = core.decode(table.concat(parts))
    if not px then return false, W end
    newCanvas(win, W, H)
    win.px = px
    win.filepath = path
    return true
end

local function listPictures()
    local fs = getFs()
    local out = {}
    if fs.exists(PICTURES_DIR) then
        for _, name in ipairs(fs.list(PICTURES_DIR) or {}) do
            if name:match("%.fpt$") then out[#out + 1] = name end
        end
    end
    table.sort(out)
    return out
end

paint._files = {save = saveFile, load = loadFile, list = listPictures}

-- ============================================================
-- Допоміжне
-- ============================================================
local function ulen(s)
    if unicode and unicode.len then return unicode.len(s) end
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end

local function toolName(id)
    for _, t in ipairs(TOOLS) do if t.id == id then return t.label end end
    return id
end

local function findScreen()
    local okG, gaddr = pcall(function() return component.list("gpu")() end)
    if not okG or not gaddr then return nil end
    local gpu = component.proxy(gaddr)
    local ok, saddr = pcall(gpu.getScreen)
    if not ok or not saddr then return nil end
    return component.proxy(saddr)
end

-- ============================================================
-- Точний режим миші та калібрування
-- ============================================================
local CFG_PATH = "/system/fixpaint.cfg"

paint._cfg = {}
function paint._cfg.load()
    local cfg = {}
    local fs = getFs()
    if not fs.exists(CFG_PATH) then return cfg end
    local h = fs.open(CFG_PATH, "r")
    if not h then return cfg end
    local parts = {}
    while true do
        local c = fs.read(h, 1024)
        if not c then break end
        parts[#parts + 1] = c
    end
    fs.close(h)
    local text = table.concat(parts)
    cfg.precise = text:match("precise=(%d)") == "1"
    cfg.offX = tonumber(text:match("offx=(%-?[%d%.]+)"))
    cfg.offY = tonumber(text:match("offy=(%-?[%d%.]+)"))
    cfg.ver = tonumber(text:match("ver=(%d+)")) or 0
    cfg.nudgeX = tonumber(text:match("nudgex=(%-?%d+)"))
    cfg.nudgeY = tonumber(text:match("nudgey=(%-?%d+)"))
    return cfg
end

function paint._cfg.save(win)
    local fs = getFs()
    local h = fs.open(CFG_PATH, "w")
    if not h then return false end
    fs.write(h, string.format("ver=4\nprecise=%d\noffx=%.3f\noffy=%.3f\nnudgex=%d\nnudgey=%d\n",
        win.precise and 1 or 0, win.offX or 0, win.offY or 0, win.nudgeX or 0, win.nudgeY or 0))
    fs.close(h)
    return true
end

-- Поправка для desktop.lua: він додає її до сирих координат кожної події миші
local function publishOffsets(win)
    if win.precise then _G._FixPrecise = {offX = win.offX or 0, offY = win.offY or 0, owner = win}
    elseif _G._FixPrecise and _G._FixPrecise.owner == win then _G._FixPrecise = nil end
end

function paint.setOffsets(win, ox, oy)
    win.offX, win.offY = ox, oy
    publishOffsets(win)
end

-- Увімкнути/вимкнути точний режим екрана. Повертає ok, помилка
function paint.setPrecise(win, on)
    if on then
        if win.precise then return true end
        local scr = win._screen or findScreen()
        if not scr then return false, "Екран не знайдено" end
        local okP, prev = pcall(scr.isPrecise)
        local okS, res = pcall(scr.setPrecise, true)
        if not okS or res == false then
            return false, "Екран не підтримує точний режим (потрібен T3)"
        end
        win._screen = scr
        if win._prevPrecise == nil then win._prevPrecise = (okP and prev) or false end
        win.precise, win.cellMode = true, false
        publishOffsets(win)
        return true
    end
    if win._screen and win.precise then pcall(win._screen.setPrecise, win._prevPrecise or false) end
    win.precise, win.cellMode = false, true
    publishOffsets(win)
    return true
end

-- Калібрування: 3 мітки; користувач клацає в центр кожної
local function startCalibration(win)
    local vw, vh = win._vw or 56, win._vh or 17
    win.calib = {step = 1, samples = {}, mode = win.precise and "precise" or "cell",
        targets = {{5, 5}, {math.max(8, vw - 6), math.max(7, vh - 4)}, {math.floor(vw / 2), math.floor(vh / 2) + 1}}}
    win.status = nil
end

local function finishCalibration(win)
    local c = win.calib
    local n = #c.samples
    if c.mode == "cell" then
        -- цілі клітинки: різниця між міткою та клітинкою, яку отримала програма
        local d0 = c.samples[1]
        local same = true
        for _, smp in ipairs(c.samples) do
            if smp.dx ~= d0.dx or smp.dy ~= d0.dy then same = false end
        end
        win.calib = nil
        if not same then
            startCalibration(win)
            win.status = "Кліки потрапили в різні клітинки відносно міток. Цільтеся точно в центр мітки."
            return
        end
        win.nudgeX = math.max(-8, math.min(8, d0.dx))
        win.nudgeY = math.max(-8, math.min(8, 2 * d0.dy))
        paint._cfg.save(win)
        win.status = string.format("Калібрування збережено: зсув x=%+d y=%+d пікселів (%+d кол., %+d кл.)",
            win.nudgeX, win.nudgeY, d0.dx, d0.dy)
        return
    end
    local sx, sy, minx, maxx, miny, maxy = 0, 0, math.huge, -math.huge, math.huge, -math.huge
    local allQuant = true
    for _, smp in ipairs(c.samples) do
        sx = sx + smp.dx; sy = sy + smp.dy
        minx = math.min(minx, smp.dx); maxx = math.max(maxx, smp.dx)
        miny = math.min(miny, smp.dy); maxy = math.max(maxy, smp.dy)
        if not smp.quant then allQuant = false end
    end
    if allQuant then
        win.calib = nil
        paint.setPrecise(win, false)
        paint._cfg.save(win)
        win.status = "Екран віддає лише цілі клітинки - точний режим не працює. Увімкнено режим клітинок."
        return
    end
    if (maxx - minx) > 0.7 or (maxy - miny) > 0.7 then
        win.calib = nil
        startCalibration(win)
        win.status = string.format("Занадто великий розкид (%.2f; %.2f). Цільтеся точно в центр мітки.", maxx - minx, maxy - miny)
        return
    end
    local ox = (win.offX or 0) + sx / n
    local oy = (win.offY or 0) + sy / n
    -- майже ціле значення (типовий зсув на клітинку) - округлити
    if math.abs(ox - math.floor(ox + 0.5)) <= 0.15 then ox = math.floor(ox + 0.5) end
    if math.abs(oy - math.floor(oy + 0.5)) <= 0.15 then oy = math.floor(oy + 0.5) end
    paint.setOffsets(win, ox, oy)
    paint._cfg.save(win)
    win.calib = nil
    win.status = string.format("Калібрування збережено: зсув x=%+.2f y=%+.2f клітинки", ox, oy)
end

local function frac(v) return v - math.floor(v) end
local function isQuant(v)
    local f = frac(v)
    return f < 1e-6 or f > 1 - 1e-6 or math.abs(f - 0.5) < 1e-6
end

local function calibrationClick(win, mx, my, rx, ry)
    local c = win.calib
    if c.mode == "cell" then
        local t = c.targets[c.step]
        c.samples[#c.samples + 1] = {dx = (win._vx + t[1]) - math.floor(mx), dy = (win._vy + t[2]) - math.floor(my)}
        c.step = c.step + 1
        if c.step > #c.targets then finishCalibration(win) end
        return
    end
    if not rx or not ry then return end
    local t = c.targets[c.step]
    local cxm, cym = win._vx + t[1] + 0.5, win._vy + t[2] + 0.5
    -- rx/ry вже містять поточну поправку desktop.lua
    c.samples[#c.samples + 1] = {dx = cxm - rx, dy = cym - ry, quant = isQuant(rx) and isQuant(ry)}
    c.step = c.step + 1
    if c.step > #c.targets then finishCalibration(win) end
end

-- Кнопка "Точно": вмикає/вимикає точний режим
local function togglePrecise(win)
    if win.precise then
        paint.setPrecise(win, false)
        paint._cfg.save(win)
        win.status = "Режим клітинок: клік займає клітинку цілком."
        return
    end
    local ok, err = paint.setPrecise(win, true)
    if not ok then win.status = err; return end
    startCalibration(win)
end

-- ============================================================
-- INIT / CLOSE
-- ============================================================
function paint.init(win, initData)
    win.title    = "FixPaint"
    win.tool     = "pencil"
    win.size     = 1
    win.fg, win.bg = 0x000000, 0xFFFFFF
    win.fillShapes = false
    win.elements = {}
    win.modal    = nil
    win.status   = nil
    win.px_pos   = nil
    win.cellMode = true
    win.precise  = false
    win.offX, win.offY = 0, 0
    win.calib    = nil
    win.filepath = nil

    -- збережене калібрування точного режиму (якщо користувач його вмикав)
    local cfg = paint._cfg.load()
    -- зсув курсора, пікселі полотна (вправо / вниз). Конфіги старіших версій
    -- (без ver=4) мали неправильні значення за замовчуванням - скидаємо їх.
    if (cfg.ver or 0) >= 4 then
        win.nudgeX, win.nudgeY = cfg.nudgeX or 1, cfg.nudgeY or 2
    else
        win.nudgeX, win.nudgeY = 1, 2
    end
    if cfg.precise then
        win.offX, win.offY = cfg.offX or 0, cfg.offY or 0
        paint.setPrecise(win, true)
    end

    newCanvas(win, 56, 32)   -- уточнюється при першому малюванні (авто-розмір)
    win._autoSize = true

    if initData and initData.filepath then
        local ok, err = loadFile(win, initData.filepath)
        if ok then win._autoSize = false else win.status = tostring(err) end
    end
end

function paint.close(win)
    paint.setPrecise(win, false)
end

-- ============================================================
-- Малювання на екран
-- ============================================================
local GRAY = 0xB0B0B0

local function pixelAtScreen(win, x, y)
    if x < 0 or y < 0 or x >= win.W or y >= win.H then return GRAY end
    return win.px[y * win.W + x + 1]
end

local function drawCell(win, gpu, c, r)
    -- c, r: 0-based клітинка у вікні перегляду
    local x, y = win.ox + c, win.oy + r * 2
    local top, bot = pixelAtScreen(win, x, y), pixelAtScreen(win, x, y + 1)
    local sx, sy = win._vx + c, win._vy + r
    if top == bot then
        gpu.setBackground(top); gpu.set(sx, sy, " ")
    else
        gpu.setForeground(top); gpu.setBackground(bot); gpu.set(sx, sy, HALF)
    end
end

local function renderCanvas(win, gpu)
    local vw, vh = win._vw, win._vh
    for r = 0, vh - 1 do
        local c = 0
        while c < vw do
            local x, y = win.ox + c, win.oy + r * 2
            local top, bot = pixelAtScreen(win, x, y), pixelAtScreen(win, x, y + 1)
            local run = 1
            while c + run < vw do
                local x2 = win.ox + c + run
                if pixelAtScreen(win, x2, y) ~= top or pixelAtScreen(win, x2, y + 1) ~= bot then break end
                run = run + 1
            end
            if top == bot then
                gpu.setBackground(top)
                gpu.set(win._vx + c, win._vy + r, string.rep(" ", run))
            else
                gpu.setForeground(top); gpu.setBackground(bot)
                gpu.set(win._vx + c, win._vy + r, string.rep(HALF, run))
            end
            c = c + run
        end
    end
end

-- Оновити на екрані лише змінені клітинки (без повного перемальовування вікна)
local function flushDirty(win)
    local gpu = win._gpu
    local d = win.dirty
    win.dirty = {}
    if not gpu or win.modal or #d == 0 then return end
    local seen = {}
    for _, i in ipairs(d) do
        local x = (i - 1) % win.W
        local y = math.floor((i - 1) / win.W)
        local c, r = x - win.ox, math.floor((y - win.oy) / 2)
        if c >= 0 and c < win._vw and r >= 0 and r < win._vh then
            local key = r * 1000 + c
            if not seen[key] then seen[key] = true; drawCell(win, gpu, c, r) end
        end
    end
end

-- ============================================================
-- DRAW
-- ============================================================
local function addEl(win, x, y, w, action, extra)
    local e = {x = x, y = y, w = w, h = 1, action = action}
    if extra then for k, v in pairs(extra) do e[k] = v end end
    win.elements[#win.elements + 1] = e
end

local function drawModal(win, gpu, UI, T, cx, cy, cw, ch)
    local m = win.modal
    local bw = math.min(cw - 4, 62)
    local rows = 2 + #m.lines
    if m.input then rows = rows + 2 end
    if m.list then rows = rows + math.min(8, math.max(1, #m.list.items)) + 1 end
    -- кнопки розкладаються по рядах, щоб не виходити за межі вікна
    local btnRows, cur, curW = {}, {}, 0
    for i, b in ipairs(m.buttons) do
        local w = math.max(8, ulen(b.label) + 4)
        if curW > 0 and curW + 1 + w > bw - 4 then btnRows[#btnRows + 1] = cur; cur = {}; curW = 0 end
        cur[#cur + 1] = {i = i, w = w}
        curW = curW + (curW > 0 and 1 or 0) + w
    end
    if #cur > 0 then btnRows[#btnRows + 1] = cur end
    rows = rows + 1 + #btnRows
    local bx = cx + math.floor((cw - bw) / 2)
    local by = cy + math.max(0, math.floor((ch - rows) / 2))

    gpu.setBackground(T.surface); gpu.fill(bx, by, bw, rows, " ")
    gpu.setBackground(T.accent); gpu.fill(bx, by, bw, 1, " ")
    gpu.setForeground(T.textOnAccent); gpu.set(bx + 1, by, UI.truncate(m.title, bw - 2))
    gpu.setBackground(T.surface)
    local y = by + 2
    gpu.setForeground(T.textPrimary)
    for _, l in ipairs(m.lines) do gpu.set(bx + 2, y, UI.truncate(l, bw - 4)); y = y + 1 end
    if m.input then
        y = y + 1
        gpu.setBackground(T.accentSubtle); gpu.fill(bx + 2, y - 1, bw - 4, 1, " ")
        loadTF().draw(gpu, m.input, bx + 3, y - 1, bw - 6,
            {fg = T.textPrimary, bg = T.accentSubtle, curFg = T.accentSubtle, curBg = T.textPrimary,
             selFg = T.textOnAccent, selBg = T.accent}, true)
        addEl(win, bx + 2, y - 1, bw - 4, "modalInput", {x0 = bx + 3})
        gpu.setBackground(T.surface)
        y = y + 1
    end
    if m.list then
        local items = m.list.items
        local visible = math.min(8, math.max(1, #items))
        if #items == 0 then
            gpu.setForeground(T.textSecondary); gpu.set(bx + 2, y, "(у /pictures немає .fpt файлів)")
        end
        local first = math.max(0, math.min(m.list.sel - 1 - 3, #items - visible))
        first = math.max(0, first)
        for row = 1, math.min(visible, #items - first) do
            local idx = first + row
            local sel = idx == m.list.sel
            gpu.setBackground(sel and T.accentSubtle or T.surface)
            gpu.fill(bx + 2, y, bw - 4, 1, " ")
            gpu.setForeground(T.textPrimary)
            gpu.set(bx + 3, y, UI.truncate(items[idx], bw - 6))
            addEl(win, bx + 2, y, bw - 4, "modalPick", {index = idx})
            y = y + 1
        end
        y = by + rows - 3 - 0
        gpu.setBackground(T.surface)
    end
    -- кнопки
    for ri, row in ipairs(btnRows) do
        local bxn = bx + 2
        local byn = by + rows - #btnRows + (ri - 1)
        for _, it in ipairs(row) do
            local b = m.buttons[it.i]
            UI.drawButton(bxn, byn, it.w, 1, b.label, b.style or "secondary", true)
            addEl(win, bxn, byn, it.w, "modalBtn", {index = it.i})
            bxn = bxn + it.w + 1
        end
    end
end

function paint.draw(win, gpu, cx, cy, cw, ch)
    if not win._ui then
        win._ui = dofile("/system/ui.lua")
        win._ui.init(gpu)
    end
    local UI, T = win._ui, win._ui.Theme
    win._gpu = gpu
    win.elements = {}

    gpu.setBackground(T.surfaceInset); gpu.fill(cx, cy, cw, ch, " ")

    -- геометрія
    win._vx, win._vy = cx, cy + 1
    win._vw = cw - SIDE_W - 1
    win._vh = ch - 2
    local sideX = cx + cw - SIDE_W

    -- авто-розмір полотна під вікно (лише для нового порожнього зображення)
    if win._autoSize and #win.undo == 0 and not win.filepath then
        local W, H = math.min(MAX_DIM, win._vw), math.min(MAX_DIM, win._vh * 2)
        if W ~= win.W or H ~= win.H then newCanvas(win, W, H) end
    end
    local maxOx = math.max(0, win.W - win._vw)
    local maxOy = math.max(0, win.H - win._vh * 2)
    if win.ox > maxOx then win.ox = maxOx end
    if win.oy > maxOy then win.oy = maxOy end
    win.oy = win.oy - (win.oy % 2)

    -- панель команд
    gpu.setBackground(T.surfaceAlt); gpu.fill(cx, cy, cw, 1, " ")
    local bx = cx
    local function cmd(label, w, action, enabled)
        UI.drawButton(bx, cy, w, 1, label, "secondary", enabled ~= false)
        addEl(win, bx, cy, w, action, {enabled = enabled ~= false})
        bx = bx + w + 1
    end
    cmd("Нове", 6, "new")
    cmd("Відкрити", 10, "open")
    cmd("Зберегти", 10, "save")
    cmd("↶ Скас.", 9, "undo", #win.undo > 0)
    cmd("↷ Повт.", 9, "redo", #win.redo > 0)
    cmd(win.precise and "Точно:ТАК" or "Точно:НІ", 11, "togglePrecise")
    cmd("Курсор", 8, "cursorDlg")

    -- полотно
    renderCanvas(win, gpu)

    -- бічна панель
    gpu.setBackground(T.surface); gpu.fill(sideX - 1, cy + 1, SIDE_W + 1, ch - 1, " ")
    local y = cy + 1
    for _, t in ipairs(TOOLS) do
        local active = (win.tool == t.id)
        gpu.setBackground(active and T.accent or T.surfaceAlt)
        gpu.fill(sideX, y, SIDE_W, 1, " ")
        gpu.setForeground(active and T.textOnAccent or T.textPrimary)
        gpu.set(sideX + 1, y, UI.truncate(t.label, SIDE_W - 4))
        gpu.setForeground(active and T.accentSubtle or T.textDisabled)
        gpu.set(sideX + SIDE_W - 2, y, t.key)
        addEl(win, sideX, y, SIDE_W, "tool", {tool = t.id})
        y = y + 1
    end
    y = y + 0
    gpu.setBackground(T.surface)
    gpu.setForeground(win.fillShapes and T.success or T.textSecondary)
    gpu.set(sideX, y, (win.fillShapes and "[x]" or "[ ]") .. " Суцільні")
    addEl(win, sideX, y, SIDE_W, "toggleFill")
    y = y + 2

    gpu.setForeground(T.textSecondary); gpu.setBackground(T.surface)
    gpu.set(sideX, y, "Товщина")
    UI.drawButton(sideX + 8, y, 3, 1, "-", "secondary", win.size > 1)
    addEl(win, sideX + 8, y, 3, "sizeDown", {enabled = win.size > 1})
    gpu.setBackground(T.surface); gpu.setForeground(T.textPrimary)
    gpu.set(sideX + 12, y, tostring(win.size))
    UI.drawButton(sideX + 14, y, 3, 1, "+", "secondary", win.size < 5)
    addEl(win, sideX + 14, y, 3, "sizeUp", {enabled = win.size < 5})
    y = y + 2

    -- палітра 8x4
    for i, color in ipairs(PAL) do
        local col, row = (i - 1) % 8, math.floor((i - 1) / 8)
        local px, py = sideX + col * 2, y + row
        gpu.setBackground(color); gpu.fill(px, py, 2, 1, " ")
        if color == win.fg then
            gpu.setForeground(color == 0x000000 and 0xFFFFFF or 0x000000)
            gpu.set(px, py, "•")
        end
        addEl(win, px, py, 2, "color", {color = color})
    end
    y = y + 5

    gpu.setBackground(T.surface); gpu.setForeground(T.textSecondary)
    gpu.set(sideX, y, "Осн")
    gpu.setBackground(win.fg); gpu.fill(sideX + 4, y, 3, 1, " ")
    gpu.setBackground(T.surface); gpu.set(sideX + 8, y, "Фон")
    gpu.setBackground(win.bg); gpu.fill(sideX + 12, y, 3, 1, " ")
    addEl(win, sideX, y, 7, "customFg")
    addEl(win, sideX + 8, y, 7, "customBg")
    gpu.setBackground(T.surface); gpu.setForeground(T.textDisabled)
    gpu.set(sideX, y + 1, string.format("#%06X  K - свій", win.fg))

    -- статус
    gpu.setBackground(T.surfaceAlt); gpu.fill(cx, cy + ch - 1, cw, 1, " ")
    gpu.setForeground(T.textSecondary)
    local name = win.filepath and win.filepath:match("[^/]+$") or "без назви"
    local pos = win.px_pos and string.format("  x:%d y:%d", win.px_pos[1], win.px_pos[2]) or ""
    local info = string.format("%s · %dx%d%s · %s%s%s", toolName(win.tool), win.W, win.H, pos, name,
        win.modified and " *" or "", win.cellMode and " · клітинки" or " · точно")
    if win.status then info = win.status end
    gpu.set(cx + 1, cy + ch - 1, UI.truncate(info, cw - 2))

    if win.calib then
        local c = win.calib
        local t = c.targets[c.step]
        if t then
            gpu.setBackground(T.warning); gpu.fill(win._vx, win._vy, win._vw, 3, " ")
            gpu.setForeground(0x1B1B1B)
            gpu.set(win._vx + 1, win._vy, UI.truncate(string.format("Калібрування курсора: мітка %d з %d", c.step, #c.targets), win._vw - 2))
            gpu.set(win._vx + 1, win._vy + 1, UI.truncate("Клацніть у ЦЕНТР червоної клітинки кінчиком курсора.", win._vw - 2))
            gpu.set(win._vx + 1, win._vy + 2, UI.truncate(c.mode == "cell" and "Esc - скасувати." or "Esc - скасувати (повернеться режим клітинок).", win._vw - 2))
            gpu.setBackground(T.danger); gpu.setForeground(T.textOnAccent)
            gpu.set(win._vx + t[1], win._vy + t[2], "+")
        end
    end

    if win.modal then drawModal(win, gpu, UI, T, cx, cy, cw, ch) end
end

-- ============================================================
-- Модальні вікна
-- ============================================================
local function closeModal(win) win.modal = nil end

local function msgModal(win, title, lines, onOk)
    win.modal = {title = title, lines = lines, buttons = {
        {label = "OK", style = "accent", fn = function() closeModal(win); if onOk then onOk() end end}}}
end

local function confirmModal(win, title, lines, onYes)
    win.modal = {title = title, lines = lines, buttons = {
        {label = "Так", style = "accent", fn = function() closeModal(win); onYes() end},
        {label = "Скасувати", fn = function() closeModal(win) end}}}
end

local function newImage(win, W, H)
    if W == 0 then
        W, H = math.min(MAX_DIM, win._vw or 56), math.min(MAX_DIM, (win._vh or 16) * 2)
        win._autoSize = true
    else
        win._autoSize = false
    end
    newCanvas(win, W, H)
    win.filepath = nil
    win.status = nil
end

local function doNew(win)
    local function sizeBtn(label, W, H)
        return {label = label, style = "accent", fn = function() closeModal(win); newImage(win, W, H) end}
    end
    win.modal = {title = "Нове зображення", lines = {"Оберіть розмір полотна (пікселі):"},
        buttons = {sizeBtn("Авто", 0, 0), sizeBtn("32x24", 32, 24), sizeBtn("64x40", 64, 40),
                   sizeBtn("96x64", 96, 64), {label = "Скасувати", fn = function() closeModal(win) end}}}
end

local function askUnsaved(win, action)
    if win.modified then
        confirmModal(win, "Незбережені зміни", {"Поточне зображення змінено й не збережено.", "Продовжити без збереження?"}, action)
    else
        action()
    end
end

local function doSave(win)
    local default = win.filepath and win.filepath:match("([^/]+)%.fpt$") or "image"
    win.modal = {title = "Зберегти зображення", lines = {"Ім'я файлу (буде збережено в " .. PICTURES_DIR .. "):"},
        input = (function() local f = loadTF().new(default, {filter = "[%w_%-%. ]", max = 40}); f.fresh = true; return f end)(),
        buttons = {
            {label = "Зберегти", style = "accent", fn = function()
                local name = win.modal.input.text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%.fpt$", "")
                if name == "" then return end
                local ok, err = saveFile(win, PICTURES_DIR .. "/" .. name .. ".fpt")
                closeModal(win)
                win.status = ok and ("Збережено: " .. win.filepath) or ("Помилка: " .. tostring(err))
            end},
            {label = "Скасувати", fn = function() closeModal(win) end}}}
end

local function doOpen(win)
    local items = listPictures()
    win.modal = {title = "Відкрити зображення", lines = {}, list = {items = items, sel = 1},
        buttons = {
            {label = "Відкрити", style = "accent", fn = function()
                local name = items[win.modal.list.sel]
                if not name then return end
                closeModal(win)
                local ok, err = loadFile(win, PICTURES_DIR .. "/" .. name)
                win._autoSize = false
                win.status = ok and ("Відкрито: " .. name) or ("Помилка: " .. tostring(err))
            end},
            {label = "Скасувати", fn = function() closeModal(win) end}}}
end

local function doColor(win, which)
    win.modal = {title = "Власний колір", lines = {"Введіть HEX-код (RRGGBB), напр. FF8800:"},
        input = (function()
            local f = loadTF().new(string.format("%06X", which == "bg" and win.bg or win.fg), {filter = "[%x#]", max = 7})
            f.fresh = true; return f
        end)(),
        buttons = {
            {label = "OK", style = "accent", fn = function()
                local hex = win.modal.input.text:gsub("#", "")
                local c = (#hex == 6) and tonumber(hex, 16)
                if c then
                    if which == "bg" then win.bg = c else win.fg = c end
                    closeModal(win)
                end
            end},
            {label = "Скасувати", fn = function() closeModal(win) end}}}
end

local function modalButton(win, i)
    local b = win.modal and win.modal.buttons[i]
    if b then b.fn() end
end

local function doCursor(win)
    local m = {title = "Налаштування курсора", lines = {}, buttons = {}}
    local function lines()
        local l = {
            "Режим: " .. (win.precise and "точний (піксель)" or "клітинки"),
            string.format("Зсув курсора: x=%+d  y=%+d  (пікселі полотна)", win.nudgeX, win.nudgeY),
            "+x - вправо, +y - вниз. Стрілки на клавіатурі = кнопки.",
        }
        if not win.precise then
            l[#l + 1] = "Клітинки: вертикальний зсув діє по 2 пікселі. Для 1 пікселя - «Точно»."
        end
        return l
    end
    local function refresh() m.lines = lines(); paint._cfg.save(win) end
    local function nudge(dx, dy)
        return function()
            win.nudgeX = math.max(-8, math.min(8, win.nudgeX + dx))
            win.nudgeY = math.max(-8, math.min(8, win.nudgeY + dy))
            refresh()
        end
    end
    m.lines = lines()
    m.buttons = {
        {label = "< ліворуч", fn = nudge(-1, 0)},
        {label = "праворуч >", fn = nudge(1, 0)},
        {label = "^ вгору", fn = nudge(0, -1)},
        {label = "v вниз", fn = nudge(0, 1)},
        {label = "Скинути", fn = function() win.nudgeX, win.nudgeY = 0, 0; refresh() end},
        {label = "Калібрувати", fn = function() closeModal(win); startCalibration(win) end},
        {label = "Закрити", style = "accent", fn = function() closeModal(win) end},
    }
    m.enterIndex = 7
    m.onKey = function(char, code)
        if code == 203 then m.buttons[1].fn(); return true end
        if code == 205 then m.buttons[2].fn(); return true end
        if code == 200 then m.buttons[3].fn(); return true end
        if code == 208 then m.buttons[4].fn(); return true end
        return false
    end
    win.modal = m
end

paint._modals = {new = doNew, save = doSave, open = doOpen, cursor = doCursor}

-- ============================================================
-- Миша
-- ============================================================
local function applyShape(win, d, x, y)
    local color = d.color
    local sx, sy = d.sx, d.sy
    local fill = function(px, py) stamp(win, px, py, color) end
    if d.tool == "line" then
        core.bresenham(sx, sy, x, y, fill)
    elseif d.tool == "rect" then
        if win.fillShapes then core.rectFilled(sx, sy, x, y, function(px, py) setPx(win, px, py, color) end)
        else core.rectOutline(sx, sy, x, y, fill) end
    elseif d.tool == "ellipse" then
        core.ellipse(sx, sy, x, y, win.fillShapes, win.fillShapes and function(px, py) setPx(win, px, py, color) end or fill)
    end
end

-- ── Курсор ────────────────────────────────────────────────
-- Екранна позиція -> піксель полотна.
-- Повертає x, y, cell. y завжди в пікселях; у режимі клітинок y = верхній
-- піксель клітинки. clamp: затискати до меж перегляду (для drag поза вікном).
-- forceCell: тримати режим, у якому розпочато штрих.
local function pointerPixel(win, mx, my, rx, ry, clamp, forceCell)
    local c = math.floor(mx) - win._vx
    local r = math.floor(my) - win._vy
    local inside = c >= 0 and r >= 0 and c < win._vw and r < win._vh
    if not inside then
        if not clamp then return nil end
        c = math.max(0, math.min(win._vw - 1, c))
        r = math.max(0, math.min(win._vh - 1, r))
    end
    local cell
    if forceCell ~= nil then cell = forceCell else cell = not win.precise end
    local y = win.oy + r * 2
    if not cell and inside and ry then
        y = y + ((frac(ry) >= 0.5) and 1 or 0)
    end
    return win.ox + c + (win.nudgeX or 0), y + (win.nudgeY or 0), cell
end

local function applyShape(win, d, x, y)
    local color, cell = d.color, d.cell
    local sx, sy = d.sx, d.sy
    local plot = function(px, py)
        if cell then stampCell(win, px, math.floor(py / 2), color) else stamp(win, px, py, color) end
    end
    local solid = function(px, py) setPx(win, px, py, color) end
    local ya, yb = math.min(sy, y), math.max(sy, y)
    local extra = cell and 1 or 0           -- нижній піксель останньої клітинки
    if d.tool == "line" then
        core.bresenham(sx, sy, x, y, plot)
    elseif d.tool == "rect" then
        if win.fillShapes then core.rectFilled(sx, ya, x, yb + extra, solid)
        else core.rectOutline(sx, sy, x, y, plot) end
    elseif d.tool == "ellipse" then
        if win.fillShapes then core.ellipse(sx, ya, x, yb + extra, true, solid)
        else core.ellipse(sx, sy, x, y, false, plot) end
    end
end

local function beginStroke(win, x, y, btn, cell)
    local tool = win.tool
    local color = (btn == 1) and win.bg or win.fg
    win.px_pos = {x, y}
    if (tool == "picker" or tool == "fill") and (x < 0 or y < 0 or x >= win.W or y >= win.H) then
        return false
    end
    if tool == "picker" then
        if btn == 1 then win.bg = win.px[y * win.W + x + 1] or win.bg
        else win.fg = win.px[y * win.W + x + 1] or win.fg end
        return true
    elseif tool == "fill" then
        core.floodFill(win.px, win.W, win.H, x, y, color, function(i, c)
            local s = win.stroke
            s[#s + 1] = i; s[#s + 1] = win.px[i]; s[#s + 1] = c
            win.px[i] = c
        end)
        commitStroke(win)
        return true            -- потрібне повне перемальовування
    elseif tool == "pencil" or tool == "eraser" then
        if tool == "eraser" then color = win.bg end
        win.drawing = {tool = tool, color = color, lx = x, ly = y, cell = cell}
        if cell then stampCell(win, x, math.floor(y / 2), color) else stamp(win, x, y, color) end
    else
        win.drawing = {tool = tool, color = color, sx = x, sy = y, cell = cell}
        applyShape(win, win.drawing, x, y)
    end
    flushDirty(win)
    return false
end

function paint.click(win, mx, my, btn, rx, ry)
    if not win._ui then return false end
    local UI = win._ui

    -- калібрування курсора перехоплює всі кліки
    if win.calib then
        calibrationClick(win, mx, my, rx, ry)
        return true
    end

    -- модальне вікно перехоплює все
    if win.modal then
        for _, e in ipairs(win.elements) do
            if UI.hitTest(e, mx, my) then
                if e.action == "modalBtn" then modalButton(win, e.index)
                elseif e.action == "modalInput" and win.modal.input then loadTF().click(win.modal.input, e.x0, mx)
                elseif e.action == "modalPick" and win.modal.list then win.modal.list.sel = e.index end
                return true
            end
        end
        return true
    end

    for _, e in ipairs(win.elements) do
        if e.enabled ~= false and UI.hitTest(e, mx, my) then
            local a = e.action
            win.status = nil
            if a == "tool" then win.tool = e.tool
            elseif a == "toggleFill" then win.fillShapes = not win.fillShapes
            elseif a == "sizeDown" then win.size = math.max(1, win.size - 1)
            elseif a == "sizeUp" then win.size = math.min(5, win.size + 1)
            elseif a == "color" then
                if btn == 1 then win.bg = e.color else win.fg = e.color end
            elseif a == "customFg" then doColor(win, "fg")
            elseif a == "customBg" then doColor(win, "bg")
            elseif a == "new" then askUnsaved(win, function() doNew(win) end)
            elseif a == "open" then askUnsaved(win, function() doOpen(win) end)
            elseif a == "save" then doSave(win)
            elseif a == "undo" then undo(win)
            elseif a == "redo" then redo(win)
            elseif a == "togglePrecise" then togglePrecise(win)
            elseif a == "cursorDlg" then paint._modals.cursor(win) end
            return true
        end
    end

    local x, y, cell = pointerPixel(win, mx, my, rx, ry, false, nil)
    if x then
        win.status = nil
        return beginStroke(win, x, y, btn, cell)
    end
    return false
end

function paint.drag(win, mx, my, btn, rx, ry)
    local d = win.drawing
    if not d or win.modal or win.calib then return false end
    local x, y = pointerPixel(win, mx, my, rx, ry, true, d.cell)
    win.px_pos = {x, y}
    if d.tool == "pencil" or d.tool == "eraser" then
        if x ~= d.lx or y ~= d.ly then
            core.bresenham(d.lx, d.ly, x, y, function(px, py)
                if d.cell then stampCell(win, px, math.floor(py / 2), d.color)
                else stamp(win, px, py, d.color) end
            end)
            d.lx, d.ly = x, y
        end
    else
        revertStroke(win)
        applyShape(win, d, x, y)
    end
    flushDirty(win)
    return false
end

function paint.drop(win, mx, my, btn, rx, ry)
    local d = win.drawing
    if not d then return false end
    win.drawing = nil
    local changed = commitStroke(win)
    flushDirty(win)
    return changed          -- перемалювати панель (кнопки Скас./Повт., зірочка)
end

-- ============================================================
-- Клавіатура
-- ============================================================
function paint.key(win, char, code)
    if win.calib then
        if code == 1 then
            local wasCell = win.calib.mode == "cell"
            win.calib = nil
            if wasCell then
                win.status = "Калібрування скасовано."
            else
                paint.setPrecise(win, false)
                paint._cfg.save(win)
                win.status = "Калібрування скасовано. Режим клітинок."
            end
        end
        return true
    end
    if win.modal then
        local m = win.modal
        if code == 1 then closeModal(win); return true end
        if code == 28 or code == 156 then modalButton(win, m.enterIndex or 1); return true end
        if m.onKey and m.onKey(char, code) then return true end
        if m.input then
            loadTF().key(m.input, char, code)
            return true
        elseif m.list then
            if code == 200 then m.list.sel = math.max(1, m.list.sel - 1); return true end
            if code == 208 then m.list.sel = math.min(math.max(1, #m.list.items), m.list.sel + 1); return true end
        end
        return true
    end

    -- Ctrl+Z / Ctrl+Y / Ctrl+S / Ctrl+O / Ctrl+N
    if char == 26 then undo(win); return true end
    if char == 25 then redo(win); return true end
    if char == 19 then doSave(win); return true end
    if char == 15 then askUnsaved(win, function() doOpen(win) end); return true end
    if char == 14 then askUnsaved(win, function() doNew(win) end); return true end

    local ch = char and char >= 32 and char < 127 and string.char(char):upper() or nil
    if ch then
        for _, t in ipairs(TOOLS) do
            if t.key == ch then win.tool = t.id; return true end
        end
        if ch == "K" then doColor(win, "fg"); return true end
        if ch == "P" then togglePrecise(win); return true end
        if ch == "N" then doCursor(win); return true end
        if ch == "C" then startCalibration(win); return true end
        if ch == "[" or ch == "-" then win.size = math.max(1, win.size - 1); return true end
        if ch == "]" or ch == "+" or ch == "=" then win.size = math.min(5, win.size + 1); return true end
        if ch == "U" then undo(win); return true end
        if ch == "Y" then redo(win); return true end
    end

    -- прокрутка великого полотна
    if code == 200 then win.oy = math.max(0, win.oy - 4); return true
    elseif code == 208 then win.oy = math.min(math.max(0, win.H - (win._vh or 16) * 2), win.oy + 4); return true
    elseif code == 203 then win.ox = math.max(0, win.ox - 4); return true
    elseif code == 205 then win.ox = math.min(math.max(0, win.W - (win._vw or 56)), win.ox + 4); return true
    end
    return false
end

function paint.paste(win, text)
    if win.modal and win.modal.input then
        local line = text:gsub("[\r\n].*$", "")
        loadTF().insert(win.modal.input, line)
        return true
    end
    return false
end

function paint.scroll(win, dir)
    if win.modal then
        local l = win.modal.list
        if l then l.sel = math.max(1, math.min(math.max(1, #l.items), l.sel + (dir > 0 and -1 or 1))) end
        return true
    end
    win.oy = math.max(0, math.min(math.max(0, win.H - (win._vh or 16) * 2), win.oy + (dir > 0 and -4 or 4)))
    return true
end

return paint
