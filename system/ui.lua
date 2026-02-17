-- ==========================================================
-- FixOS 3.2.0 - system/ui.lua
-- Pixel-Perfect UI Library
-- CHANGES 3.2.0:
--   - UI.drawScrollbar added
--   - drawWindow shadow reduced to depth=1 (no doubling)
--   - shadow depth param always respected
-- ==========================================================

local UI = {}

UI.Theme = {
    accent          = 0x0078D7,
    accentDark      = 0x005A9E,
    accentLight     = 0x429CE3,
    accentSubtle    = 0xCDE8FF,

    surface         = 0xFFFFFF,
    surfaceAlt      = 0xF3F3F3,
    surfaceInset    = 0xE8E8E8,

    chromeDark      = 0x1F1F1F,
    chromeMid       = 0x2D2D30,
    chromeBorder    = 0x3F3F46,
    chromeLight     = 0xF0F0F0,

    textPrimary     = 0x1B1B1B,
    textSecondary   = 0x666666,
    textDisabled    = 0xAAAAAA,
    textOnDark      = 0xF3F3F3,
    textOnAccent    = 0xFFFFFF,

    borderSubtle    = 0xE5E5E5,
    borderStrong    = 0xCCCCCC,
    divider         = 0xDDDDDD,

    shadow0         = 0xDDDDDD,
    shadow1         = 0xC0C0C0,
    shadow2         = 0xA0A0A0,
    shadow3         = 0x787878,

    success         = 0x10893E,
    warning         = 0xFFB900,
    danger          = 0xE81123,
    info            = 0x0078D7,

    tileBlue        = 0x0078D7,
    tileOrange      = 0xCA5010,
    tileDark        = 0x454545,
    tileGray        = 0x505058,
    tileGreen       = 0x10893E,
    tileCyan        = 0x00838F,

    progressTrack   = 0xE0E0E0,
    scrollTrack     = 0xE8E8E8,
    scrollThumb     = 0x0078D7,
}

UI.PADDING  = 1
UI.TILE_W   = 17
UI.TILE_H   = 4
UI.TILE_GAP = 1
UI.BTN_H    = 2

local _gpu = nil

function UI.init(gpuProxy)
    _gpu = gpuProxy
end

local function ulen(s)
    s = tostring(s)
    if unicode and unicode.len then return unicode.len(s) end
    return #s
end

local function usub(s, i, j)
    s = tostring(s)
    if unicode and unicode.sub then return unicode.sub(s, i, j) end
    return s:sub(i, j)
end

function UI.textLen(s) return ulen(s) end

function UI.truncate(s, maxW)
    s = tostring(s)
    if ulen(s) <= maxW then return s end
    return usub(s, 1, maxW - 1) .. ">"
end

function UI.centerText(x, y, width, str, fg, bg)
    str = tostring(str)
    local len   = ulen(str)
    local spare = width - len
    if spare < 0 then
        str   = usub(str, 1, width - 1) .. ">"
        spare = 0
    end
    local ox = math.floor(spare / 2)
    if bg then _gpu.setBackground(bg) end
    _gpu.setForeground(fg)
    _gpu.set(x + ox, y, str)
end

-- Shadow: depth=0 draws nothing, depth=1 draws one strip only
function UI.shadow(x, y, w, h, depth)
    depth = math.max(0, math.min(depth or 1, 3))
    if depth == 0 then return end
    local colors = { UI.Theme.shadow1, UI.Theme.shadow2, UI.Theme.shadow3 }
    for i = 1, depth do
        local c = colors[i] or colors[#colors]
        _gpu.setBackground(c)
        _gpu.fill(x + i,     y + h + (i - 1), w, 1, " ")
        _gpu.fill(x + w + (i - 1), y + i,     1, h, " ")
    end
end

-- drawWindow: shadow depth=1 to avoid doubling effect
function UI.drawWindow(x, y, w, h, title, focused)
    if focused == nil then focused = true end
    local P = UI.PADDING

    -- Thin shadow (depth=1, no doubling)
    UI.shadow(x, y, w, h, 1)

    _gpu.setBackground(UI.Theme.surface)
    _gpu.fill(x, y, w, h, " ")

    local titleBg = focused and UI.Theme.accent or UI.Theme.chromeMid
    _gpu.setBackground(titleBg)
    _gpu.fill(x, y, w, 1, " ")

    local ctrlW  = 9
    local titleW = w - ctrlW - P
    UI.centerText(x + P, y, titleW, title, UI.Theme.textOnAccent, titleBg)

    local cx0 = x + w - ctrlW
    _gpu.setBackground(titleBg)
    _gpu.setForeground(UI.Theme.textOnDark)
    _gpu.set(cx0,     y, " - ")
    _gpu.set(cx0 + 3, y, " [] ")

    _gpu.setBackground(UI.Theme.danger)
    _gpu.setForeground(UI.Theme.textOnAccent)
    _gpu.set(cx0 + 6, y, " X ")

    _gpu.setForeground(UI.Theme.borderSubtle)
    _gpu.setBackground(UI.Theme.surface)
    for col = 0, w - 1 do
        _gpu.set(x + col, y + 1, "\xE2\x94\x80")
    end

    for row = 2, h - 2 do
        _gpu.set(x,         y + row, "\xE2\x94\x82")
        _gpu.set(x + w - 1, y + row, "\xE2\x94\x82")
    end

    _gpu.set(x,         y + h - 1, "\xE2\x94\x94")
    _gpu.set(x + w - 1, y + h - 1, "\xE2\x94\x98")
    for col = 1, w - 2 do
        _gpu.set(x + col, y + h - 1, "\xE2\x94\x80")
    end

    local clientX = x + 1 + P
    local clientY = y + 2
    local clientW = w - 2 - P * 2
    local clientH = h - 4
    return clientX, clientY, clientW, clientH
end

-- Vertical scrollbar
-- total   = total number of items
-- visible = number of visible items
-- offset  = current scroll offset (0-based)
function UI.drawScrollbar(x, y, h, total, visible, offset)
    if total <= visible or h < 2 then return end
    local T = UI.Theme
    _gpu.setBackground(T.scrollTrack)
    _gpu.fill(x, y, 1, h, " ")
    local thumbH = math.max(1, math.floor(h * visible / total))
    local maxOff = math.max(1, total - visible)
    local thumbY = math.floor((h - thumbH) * offset / maxOff)
    thumbY = math.max(0, math.min(h - thumbH, thumbY))
    _gpu.setBackground(T.scrollThumb)
    _gpu.fill(x, y + thumbY, 1, thumbH, " ")
end

function UI.drawButton(x, y, w, h, label, style, enabled)
    style   = style   or "accent"
    enabled = (enabled == nil) and true or enabled
    h       = h       or UI.BTN_H

    local bg, fg, topBar

    if not enabled then
        bg, fg, topBar = UI.Theme.surfaceInset, UI.Theme.textDisabled, nil
    elseif style == "accent" then
        bg, fg, topBar = UI.Theme.accent,     UI.Theme.textOnAccent, UI.Theme.accentDark
    elseif style == "secondary" then
        bg, fg, topBar = UI.Theme.surfaceAlt, UI.Theme.textPrimary,  UI.Theme.borderStrong
    elseif style == "danger" then
        bg, fg, topBar = UI.Theme.danger,     UI.Theme.textOnAccent, 0xC00E1A
    elseif style == "success" then
        bg, fg, topBar = UI.Theme.success,    UI.Theme.textOnAccent, 0x0B6B31
    elseif style == "ghost" then
        bg, fg, topBar = UI.Theme.surface,    UI.Theme.accent,       UI.Theme.borderSubtle
    else
        bg, fg, topBar = UI.Theme.accent,     UI.Theme.textOnAccent, UI.Theme.accentDark
    end

    if enabled and h >= 1 then
        _gpu.setBackground(UI.Theme.shadow1)
        _gpu.fill(x + 1, y + h, w, 1, " ")
        _gpu.fill(x + w, y + 1, 1, h, " ")
    end

    _gpu.setBackground(bg)
    _gpu.fill(x, y, w, h, " ")

    if topBar then
        _gpu.setBackground(topBar)
        _gpu.fill(x, y, w, 1, " ")
    end

    local labelRow = y + math.floor(h / 2)
    if topBar then labelRow = y + math.max(1, math.floor(h / 2)) end
    UI.centerText(x, labelRow, w, label, fg, bg)

    return { x = x, y = y, w = w, h = h }
end

function UI.drawProgressBar(x, y, w, percent, barColor)
    percent  = math.max(0, math.min(1, percent or 0))
    barColor = barColor or UI.Theme.accent

    _gpu.setBackground(UI.Theme.progressTrack)
    _gpu.fill(x, y, w, 1, " ")

    local filled = math.floor(w * percent)
    if filled > 0 then
        _gpu.setBackground(barColor)
        _gpu.fill(x, y, filled, 1, " ")
    end

    if filled > 0 and filled < w then
        _gpu.setForeground(UI.Theme.accentLight)
        _gpu.setBackground(UI.Theme.progressTrack)
        _gpu.set(x + filled, y, "\xE2\x97\x8F")
    end

    local pct  = math.floor(percent * 100) .. "%"
    local plen = ulen(pct)
    local lx   = x + math.floor((w - plen) / 2)
    local onB  = (lx < x + filled)
    _gpu.setForeground(onB and UI.Theme.textOnAccent or UI.Theme.textSecondary)
    _gpu.setBackground(onB and barColor              or UI.Theme.progressTrack)
    _gpu.set(lx, y, pct)
end

function UI.drawCard(x, y, w, h, headerText, headerColor)
    headerColor = headerColor or UI.Theme.accent

    _gpu.setBackground(UI.Theme.surfaceAlt)
    _gpu.fill(x, y, w, h, " ")

    _gpu.setForeground(UI.Theme.borderSubtle)
    _gpu.setBackground(UI.Theme.surfaceAlt)
    for col = 0, w - 1 do
        _gpu.set(x + col, y,         "\xE2\x94\x80")
        _gpu.set(x + col, y + h - 1, "\xE2\x94\x80")
    end
    for row = 1, h - 2 do
        _gpu.set(x,         y + row, "\xE2\x94\x82")
        _gpu.set(x + w - 1, y + row, "\xE2\x94\x82")
    end
    _gpu.set(x,         y,         "\xE2\x94\x8C")
    _gpu.set(x + w - 1, y,         "\xE2\x94\x90")
    _gpu.set(x,         y + h - 1, "\xE2\x94\x94")
    _gpu.set(x + w - 1, y + h - 1, "\xE2\x94\x98")

    if headerText then
        _gpu.setBackground(headerColor)
        _gpu.fill(x + 1, y, w - 2, 1, " ")
        UI.centerText(x + 1, y, w - 2, headerText, UI.Theme.textOnAccent, headerColor)
    end

    local P = UI.PADDING
    return x + P + 1, y + 1, w - (P + 1) * 2, h - 2
end

function UI.drawTile(x, y, label, icon, color, hover)
    color = color or UI.Theme.tileBlue
    local W, H = UI.TILE_W, UI.TILE_H

    local tileBg = color
    if hover then
        local r = math.min(255, math.floor(color / 0x10000)        + 20)
        local g = math.min(255, math.floor((color % 0x10000) / 256) + 20)
        local b = math.min(255, color % 256                         + 20)
        tileBg  = r * 0x10000 + g * 0x100 + b
    end

    _gpu.setBackground(tileBg)
    _gpu.fill(x, y, W, H, " ")

    local r2    = math.min(255, math.floor(tileBg / 0x10000)        + 40)
    local g2    = math.min(255, math.floor((tileBg % 0x10000) / 256) + 40)
    local b2    = math.min(255, tileBg % 256                         + 40)
    local strip = r2 * 0x10000 + g2 * 0x100 + b2
    _gpu.setBackground(strip)
    _gpu.fill(x, y, 2, H, " ")

    local iconRow = y + math.floor(H / 2)
    _gpu.setForeground(UI.Theme.textOnAccent)
    _gpu.setBackground(tileBg)
    _gpu.set(x + 2 + UI.PADDING, iconRow, tostring(icon or " "))

    local labelX = x + 2 + UI.PADDING + ulen(tostring(icon or " ")) + 1
    local labelW = W - (labelX - x) - UI.PADDING
    _gpu.set(labelX, iconRow, UI.truncate(tostring(label), labelW))

    return { x = x, y = y, w = W, h = H }
end

function UI.drawStartMenuGrid(originX, originY, tiles)
    local hits = {}
    local col, row = 0, 0
    for _, tile in ipairs(tiles) do
        local tx = originX + col * (UI.TILE_W + UI.TILE_GAP)
        local ty = originY + row * (UI.TILE_H + UI.TILE_GAP)
        local btn = UI.drawTile(tx, ty, tile.label, tile.icon, tile.color, false)
        btn.action = tile.action
        table.insert(hits, btn)
        col = col + 1
        if col >= 2 then col = 0; row = row + 1 end
    end
    return hits
end

function UI.drawTabBar(x, y, totalWidth, tabs, activeIndex)
    local n     = #tabs
    local baseW = math.floor(totalWidth / n)
    local hits  = {}

    for i, label in ipairs(tabs) do
        local tabW  = (i == n) and (x + totalWidth - (x + (i-1)*baseW)) or baseW
        local tx    = x + (i - 1) * baseW
        local isAct = (i == activeIndex)
        local bg    = isAct and UI.Theme.accent       or UI.Theme.surfaceInset
        local fg    = isAct and UI.Theme.textOnAccent or UI.Theme.textSecondary

        _gpu.setBackground(bg)
        _gpu.fill(tx, y, tabW, 1, " ")
        UI.centerText(tx, y, tabW, label, fg, bg)

        table.insert(hits, { x = tx, y = y, w = tabW, h = 1, index = i })
    end
    return hits
end

function UI.drawStatusBanner(x, y, w, message, status)
    local bgMap   = { success=UI.Theme.success, warning=UI.Theme.warning,
                      danger=UI.Theme.danger,   info=UI.Theme.info }
    local iconMap = { success="[OK]", warning="[!!]", danger="[XX]", info="[i]" }
    local bg      = bgMap[status]   or UI.Theme.info
    local icon    = iconMap[status] or "[i]"
    local msg     = icon .. " " .. UI.truncate(message, w - ulen(icon) - 3)

    _gpu.setBackground(bg)
    _gpu.fill(x, y, w, 1, " ")
    _gpu.setForeground(UI.Theme.textOnAccent)
    _gpu.set(x + UI.PADDING, y, msg)
end

function UI.drawDivider(x, y, w, color)
    _gpu.setForeground(color or UI.Theme.divider)
    _gpu.setBackground(UI.Theme.surface)
    for col = 0, w - 1 do
        _gpu.set(x + col, y, "\xE2\x94\x80")
    end
end

function UI.spinner(x, y, frame, color, bg)
    local frames = { "|", "/", "-", "\\", "|", "/", "-", "\\" }
    _gpu.setForeground(color or UI.Theme.accent)
    _gpu.setBackground(bg or UI.Theme.surface)
    _gpu.set(x, y, frames[(frame % #frames) + 1])
end

function UI.hitTest(rect, mx, my)
    return mx >= rect.x
       and mx <  rect.x + rect.w
       and my >= rect.y
       and my <  rect.y + rect.h
end

function UI.clearScreen(screenW, screenH, bg)
    _gpu.setBackground(bg or UI.Theme.surface)
    _gpu.fill(1, 1, screenW, screenH, " ")
end

return UI