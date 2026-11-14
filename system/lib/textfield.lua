-- ==========================================================
-- FixOS 4.3.1 - system/lib/textfield.lua   (НОВИЙ ФАЙЛ)
-- Однорядкове текстове поле з нормальним курсором (кареткою):
--   * ← → Home End - рух, Backspace/Delete - видалення в місці каретки
--   * вставка і введення (в т.ч. кирилиці) в позицію каретки
--   * клік мишею ставить каретку в потрібну позицію
--   * горизонтальна прокрутка, коли текст ширший за поле
--   * режим "fresh" (як виділений текст): перший символ замінює все,
--     Backspace/Delete стирає все, стрілки знімають виділення
--   * усе рахується в СИМВОЛАХ Unicode, а не в байтах
-- ==========================================================

local TF = {}

local function ulen(s)
    if unicode and unicode.len then return unicode.len(s) end
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end

local function usub(s, i, j)
    if unicode and unicode.sub then return unicode.sub(s, i, j) end
    -- запасний варіант без unicode: посимвольно
    local t = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do t[#t + 1] = ch end
    return table.concat(t, "", math.max(1, i), math.min(#t, j or #t))
end

local function u8(cp)
    if cp < 0x80 then return string.char(cp)
    elseif cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
    end
    return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
                       0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

-- opts: max (символів), filter (шаблон Lua для одного символу, напр. "[%x#]")
function TF.new(text, opts)
    opts = opts or {}
    text = text or ""
    return {text = text, pos = ulen(text), scroll = 0, fresh = false,
            max = opts.max or 200, filter = opts.filter}
end

function TF.set(f, text, fresh)
    f.text, f.pos, f.scroll = text or "", ulen(text or ""), 0
    f.fresh = fresh and true or false
end

function TF.length(f) return ulen(f.text) end

local function accept(f, ch)
    if f.filter and not ch:match(f.filter) then return false end
    return true
end

-- Вставка рядка в позицію каретки (фільтр, ліміт, керуючі символи вирізаються)
function TF.insert(f, str)
    str = tostring(str):gsub("[%z\1-\31\127]", "")
    if str == "" then return false end
    if f.fresh then f.text, f.pos, f.fresh = "", 0, false end
    local changed = false
    for ch in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if accept(f, ch) and ulen(f.text) < f.max then
            f.text = usub(f.text, 1, f.pos) .. ch .. usub(f.text, f.pos + 1)
            f.pos = f.pos + 1
            changed = true
        end
    end
    return changed
end

-- Обробка клавіші. Повертає handled, action ("submit" | "cancel" | nil)
function TF.key(f, char, code)
    if code == 28 or code == 156 then return true, "submit" end
    if code == 1 then return true, "cancel" end

    if code == 203 then f.fresh = false; f.pos = math.max(0, f.pos - 1); return true end
    if code == 205 then f.fresh = false; f.pos = math.min(ulen(f.text), f.pos + 1); return true end
    if code == 199 then f.fresh = false; f.pos = 0; return true end
    if code == 207 then f.fresh = false; f.pos = ulen(f.text); return true end

    if code == 14 then                                   -- Backspace
        if f.fresh then TF.set(f, "", false); return true end
        if f.pos > 0 then
            f.text = usub(f.text, 1, f.pos - 1) .. usub(f.text, f.pos + 1)
            f.pos = f.pos - 1
        end
        return true
    end
    if code == 211 then                                  -- Delete
        if f.fresh then TF.set(f, "", false); return true end
        if f.pos < ulen(f.text) then
            f.text = usub(f.text, 1, f.pos) .. usub(f.text, f.pos + 2)
        end
        return true
    end
    if char == 1 then f.fresh = true; return true end     -- Ctrl+A: виділити все
    if char and char >= 32 and char ~= 127 then
        TF.insert(f, u8(char))
        return true
    end
    return false
end

-- Тримає каретку в межах видимої ширини w
local function fitScroll(f, w)
    if f.pos < f.scroll then f.scroll = f.pos end
    if f.pos > f.scroll + w - 1 then f.scroll = f.pos - (w - 1) end
    local len = ulen(f.text)
    if f.scroll > math.max(0, len - w + 1) then f.scroll = math.max(0, len - w + 1) end
    if f.scroll < 0 then f.scroll = 0 end
end

-- Малює поле. Повертає екранну X-координату каретки.
-- colors = {fg=, bg=, curFg=, curBg=, selFg=, selBg=}
function TF.draw(gpu, f, x, y, w, colors, active)
    colors = colors or {}
    local fg, bg = colors.fg or 0x000000, colors.bg or 0xFFFFFF
    local curFg, curBg = colors.curFg or bg, colors.curBg or fg
    fitScroll(f, w)
    local visible = usub(f.text, f.scroll + 1, f.scroll + w)
    gpu.setBackground(bg); gpu.setForeground(fg)
    gpu.fill(x, y, w, 1, " ")
    if f.fresh and active and visible ~= "" then
        gpu.setBackground(colors.selBg or curBg); gpu.setForeground(colors.selFg or curFg)
        gpu.set(x, y, visible)
        return x + math.min(w - 1, ulen(visible))
    end
    gpu.set(x, y, visible)
    local cx = x + (f.pos - f.scroll)
    if active and cx < x + w then
        local under = usub(f.text, f.pos + 1, f.pos + 1)
        if under == "" then under = " " end
        gpu.setBackground(curBg); gpu.setForeground(curFg)
        gpu.set(cx, y, under)
    end
    return cx
end

-- Клік мишею: ставить каретку (x0 - перша колонка поля)
function TF.click(f, x0, mx)
    f.fresh = false
    f.pos = math.max(0, math.min(ulen(f.text), (mx - x0) + f.scroll))
end

return TF
