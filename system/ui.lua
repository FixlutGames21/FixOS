-- ==========================================================
-- FixOS 3.1.2 - system/ui.lua
-- Pixel-Perfect UI Library
--
-- FIXES over 3.1.1:
--   - Shadow draws ONLY below-right, never over window content
--   - centerText uses unicode.len() throughout
--   - PADDING constant respected by every element
--   - drawButton always returns a proper hit-test rect {x,y,w,h}
--   - drawTile uses a contrasting left-strip so dark tiles are visible
--   - drawTabBar calculates tab width from totalWidth so tabs align
--
-- Usage:
--   local UI = dofile("/system/ui.lua")
--   UI.init(gpu)
--   UI.drawWindow(2, 2, 60, 20, "My Window")
-- ==========================================================

local UI = {}

-- ----------------------------------------------------------
-- THEME  (single source of truth for all colors)
-- ----------------------------------------------------------
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

    -- Shadows: only used as solid background fills
    shadow0         = 0xDDDDDD,
    shadow1         = 0xC0C0C0,
    shadow2         = 0xA0A0A0,
    shadow3         = 0x787878,

    success         = 0x10893E,
    warning         = 0xFFB900,
    danger          = 0xE81123,
    info            = 0x0078D7,

    -- Tile colors (Start Menu)
    tileBlue        = 0x0078D7,
    tileOrange      = 0xCA5010,
    -- dark tiles need a lighter shade so they contrast with
    -- the chromeMid (0x2D2D30) menu background
    tileDark        = 0x454545,
    tileGray        = 0x505058,
    tileGreen       = 0x10893E,
    tileCyan        = 0x00838F,

    progressTrack   = 0xE0E0E0,
}

-- ----------------------------------------------------------
-- LAYOUT CONSTANTS
-- ----------------------------------------------------------
UI.PADDING   = 1   -- minimum inner offset from any edge (chars)
UI.TILE_W    = 17  -- strict tile width  (2 tiles + 1 gap fits in 35 cols)
UI.TILE_H    = 4   -- strict tile height
UI.TILE_GAP  = 1   -- gap between tiles in the grid
UI.BTN_H     = 2   -- default button height

-- ----------------------------------------------------------
-- INTERNAL
-- ----------------------------------------------------------
local _gpu = nil

function UI.init(gpuProxy)
    _gpu = gpuProxy
end

-- ----------------------------------------------------------
-- TEXT HELPERS  (unicode.len is the only source of truth)
-- ----------------------------------------------------------

local function ulen(s)
    s = tostring(s)
    if unicode and unicode.len then
        return unicode.len(s)
    end
    return #s
end

local function usub(s, i, j)
    s = tostring(s)
    if unicode and unicode.sub then
        return unicode.sub(s, i, j)
    end
    return s:sub(i, j)
end

-- Exported so programs can measure text for their own layouts.
function UI.textLen(s)  return ulen(s)  end

-- Truncate a string to fit in maxW chars (appends ">" if cut).
function UI.truncate(s, maxW)
    s = tostring(s)
    if ulen(s) <= maxW then return s end
    return usub(s, 1, maxW - 1) .. ">"
end

-- Draw text centered inside a region [x .. x+width-1] on row y.
-- NEVER use #str here; always ulen().
function UI.centerText(x, y, width, str, fg, bg)
    str = tostring(str)
    local len  = ulen(str)
    local spare = width - len
    if spare < 0 then
        str   = usub(str, 1, width - 1) .. ">"
        spare = 0
    end
    local ox = math.floor(spare / 2)
    if bg  then _gpu.setBackground(bg)  end
    _gpu.setForeground(fg)
    _gpu.set(x + ox, y, str)
end

-- ----------------------------------------------------------
-- SHADOW
-- Draws a solid drop-shadow ONLY outside the rect
-- (below the bottom edge and right of the right edge).
-- depth = 1..3  controls how many pixels of shadow.
-- ----------------------------------------------------------
function UI.shadow(x, y, w, h, depth)
    depth = math.max(1, math.min(depth or 2, 3))
    local colors = { UI.Theme.shadow0, UI.Theme.shadow1, UI.Theme.shadow2, UI.Theme.shadow3 }

    for i = 1, depth do
        local c = colors[i + 1] or colors[#colors]

        -- Strip BELOW the rect (outside)
        _gpu.setBackground(c)
        _gpu.fill(x + i, y + h + (i - 1), w, 1, " ")

        -- Strip to the RIGHT of the rect (outside)
        _gpu.fill(x + w + (i - 1), y + i, 1, h, " ")
    end
end

-- ----------------------------------------------------------
-- drawWindow
-- Returns cx, cy, cw, ch  (usable client area).
-- ----------------------------------------------------------
function UI.drawWindow(x, y, w, h, title, focused)
    if focused == nil then focused = true end
    local P = UI.PADDING

    -- Shadow drawn first, entirely outside the window rect
    UI.shadow(x, y, w, h, 2)

    -- Window body
    _gpu.setBackground(UI.Theme.surface)
    _gpu.fill(x, y, w, h, " ")

    -- Title bar (1 row)
    local titleBg = focused and UI.Theme.accent or UI.Theme.chromeMid
    _gpu.setBackground(titleBg)
    _gpu.fill(x, y, w, 1, " ")

    -- Title text: leave 9 chars on right for controls, P on left
    local ctrlW    = 9          -- " - " + " [] " + " X "
    local titleW   = w - ctrlW - P
    UI.centerText(x + P, y, titleW, title, UI.Theme.textOnAccent, titleBg)

    -- Window controls  (right-aligned in title bar)
    local cx0 = x + w - ctrlW
    _gpu.setBackground(titleBg)
    _gpu.setForeground(UI.Theme.textOnDark)
    _gpu.set(cx0,     y, " - ")       -- minimise
    _gpu.set(cx0 + 3, y, " [] ")      -- maximise ([] = ASCII square)

    _gpu.setBackground(UI.Theme.danger)
    _gpu.setForeground(UI.Theme.textOnAccent)
    _gpu.set(cx0 + 6, y, " X ")      -- close

    -- Thin divider below title bar
    _gpu.setForeground(UI.Theme.borderSubtle)
    _gpu.setBackground(UI.Theme.surface)
    for col = 0, w - 1 do
        _gpu.set(x + col, y + 1, "\xE2\x94\x80")  -- U+2500 box-drawing
    end

    -- Left and right borders
    for row = 2, h - 2 do
        _gpu.set(x,         y + row, "\xE2\x94\x82")  -- U+2502
        _gpu.set(x + w - 1, y + row, "\xE2\x94\x82")
    end

    -- Bottom border
    _gpu.set(x,         y + h - 1, "\xE2\x94\x94")   -- U+2514 L
    _gpu.set(x + w - 1, y + h - 1, "\xE2\x94\x98")   -- U+2518 J
    for col = 1, w - 2 do
        _gpu.set(x + col, y + h - 1, "\xE2\x94\x80")
    end

    -- Return client area (inside borders + PADDING)
    local clientX = x + 1 + P
    local clientY = y + 2              -- below title + divider
    local clientW = w - 2 - P * 2
    local clientH = h - 4             -- title + divider + bottom + 1 spare
    return clientX, clientY, clientW, clientH
end

-- ----------------------------------------------------------
-- drawButton
-- style: "accent" | "secondary" | "danger" | "success" | "ghost"
-- Returns a hit-test rect  {x, y, w, h}.
-- ----------------------------------------------------------
function UI.drawButton(x, y, w, h, label, style, enabled)
    style   = style   or "accent"
    enabled = (enabled == nil) and true or enabled
    h       = h       or UI.BTN_H

    local bg, fg, topBar

    if not enabled then
        bg, fg, topBar = UI.Theme.surfaceInset, UI.Theme.textDisabled, nil
    elseif style == "accent" then
        bg, fg, topBar = UI.Theme.accent,   UI.Theme.textOnAccent, UI.Theme.accentDark
    elseif style == "secondary" then
        bg, fg, topBar = UI.Theme.surfaceAlt, UI.Theme.textPrimary, UI.Theme.borderStrong
    elseif style == "danger" then
        bg, fg, topBar = UI.Theme.danger,   UI.Theme.textOnAccent, 0xC00E1A
    elseif style == "success" then
        bg, fg, topBar = UI.Theme.success,  UI.Theme.textOnAccent, 0x0B6B31
    elseif style == "ghost" then
        bg, fg, topBar = UI.Theme.surface,  UI.Theme.accent,       UI.Theme.borderSubtle
    else
        bg, fg, topBar = UI.Theme.accent,   UI.Theme.textOnAccent, UI.Theme.accentDark
    end

    -- Shadow (solid fill, below and right, only when enabled)
    if enabled and h >= 1 then
        _gpu.setBackground(UI.Theme.shadow1)
        _gpu.fill(x + 1, y + h, w, 1, " ")
        _gpu.fill(x + w, y + 1, 1, h, " ")
    end

    -- Button body
    _gpu.setBackground(bg)
    _gpu.fill(x, y, w, h, " ")

    -- Top accent bar (1 px, same bg column as button)
    if topBar then
        _gpu.setBackground(topBar)
        _gpu.fill(x, y, w, 1, " ")
    end

    -- Centered label (unicode.len — the whole point)
    local labelRow = y + math.floor(h / 2)
    if topBar then labelRow = y + math.max(1, math.floor(h / 2)) end
    UI.centerText(x, labelRow, w, label, fg, bg)

    return { x = x, y = y, w = w, h = h }
end

-- ----------------------------------------------------------
-- drawProgressBar
-- percent = 0.0 .. 1.0
-- ----------------------------------------------------------
function UI.drawProgressBar(x, y, w, percent, barColor)
    percent  = math.max(0, math.min(1, percent or 0))
    barColor = barColor or UI.Theme.accent

    -- Track
    _gpu.setBackground(UI.Theme.progressTrack)
    _gpu.fill(x, y, w, 1, " ")

    -- Fill
    local filled = math.floor(w * percent)
    if filled > 0 then
        _gpu.setBackground(barColor)
        _gpu.fill(x, y, filled, 1, " ")
    end

    -- Leading dot at the frontier (shows motion)
    if filled > 0 and filled < w then
        _gpu.setForeground(UI.Theme.accentLight)
        _gpu.setBackground(UI.Theme.progressTrack)
        _gpu.set(x + filled, y, "\xE2\x97\x8F")  -- U+25CF solid circle
    end

    -- Percentage label, always centered, fg adapts to background
    local pct   = math.floor(percent * 100) .. "%"
    local plen  = ulen(pct)
    local lx    = x + math.floor((w - plen) / 2)
    local onBar = (lx < x + filled)
    _gpu.setForeground(onBar and UI.Theme.textOnAccent or UI.Theme.textSecondary)
    _gpu.setBackground(onBar and barColor              or UI.Theme.progressTrack)
    _gpu.set(lx, y, pct)
end

-- ----------------------------------------------------------
-- drawCard
-- Returns inner content rect  cx, cy, cw, ch.
-- ----------------------------------------------------------
function UI.drawCard(x, y, w, h, headerText, headerColor)
    headerColor = headerColor or UI.Theme.accent

    -- Card body
    _gpu.setBackground(UI.Theme.surfaceAlt)
    _gpu.fill(x, y, w, h, " ")

    -- Border
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
    _gpu.set(x,         y,         "\xE2\x94\x8C")  -- U+250C
    _gpu.set(x + w - 1, y,         "\xE2\x94\x90")  -- U+2510
    _gpu.set(x,         y + h - 1, "\xE2\x94\x94")  -- U+2514
    _gpu.set(x + w - 1, y + h - 1, "\xE2\x94\x98")  -- U+2518

    -- Header bar (overwrites top border)
    if headerText then
        _gpu.setBackground(headerColor)
        _gpu.fill(x + 1, y, w - 2, 1, " ")
        UI.centerText(x + 1, y, w - 2, headerText, UI.Theme.textOnAccent, headerColor)
    end

    -- Inner content area
    local P = UI.PADDING
    return x + P + 1, y + 1, w - (P + 1) * 2, h - 2
end

-- ----------------------------------------------------------
-- drawTile  (Start Menu)
-- All tiles share TILE_W x TILE_H for a strict grid.
-- A 2-px left accent strip ensures dark tiles stand out.
-- ----------------------------------------------------------
function UI.drawTile(x, y, label, icon, color, hover)
    color = color or UI.Theme.tileBlue
    local W, H = UI.TILE_W, UI.TILE_H

    -- Hover: lighten slightly
    local tileBg = color
    if hover then
        local r = math.min(255, math.floor(color / 0x10000)        + 20)
        local g = math.min(255, math.floor((color % 0x10000) / 256) + 20)
        local b = math.min(255, color % 256                         + 20)
        tileBg  = r * 0x10000 + g * 0x100 + b
    end

    -- Tile body
    _gpu.setBackground(tileBg)
    _gpu.fill(x, y, W, H, " ")

    -- Left accent strip (2 cols, slightly lighter than tile)
    -- This makes even near-black tiles visible against the dark menu bg.
    local r2  = math.min(255, math.floor(tileBg / 0x10000)        + 40)
    local g2  = math.min(255, math.floor((tileBg % 0x10000) / 256) + 40)
    local b2  = math.min(255, tileBg % 256                         + 40)
    local strip = r2 * 0x10000 + g2 * 0x100 + b2
    _gpu.setBackground(strip)
    _gpu.fill(x, y, 2, H, " ")

    -- Icon on the middle row, after the strip
    local iconRow = y + math.floor(H / 2)
    _gpu.setForeground(UI.Theme.textOnAccent)
    _gpu.setBackground(tileBg)
    _gpu.set(x + 2 + UI.PADDING, iconRow, tostring(icon or " "))

    -- Label after the icon (truncated to fit)
    local labelX = x + 2 + UI.PADDING + ulen(tostring(icon or " ")) + 1
    local labelW = W - (labelX - x) - UI.PADDING
    _gpu.set(labelX, iconRow, UI.truncate(tostring(label), labelW))

    return { x = x, y = y, w = W, h = H }
end

-- ----------------------------------------------------------
-- drawStartMenuGrid
-- Renders a 2-column tile grid.
-- tiles = list of {label, icon, color, action}
-- Returns hit-test list (each entry has .action).
-- ----------------------------------------------------------
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

-- ----------------------------------------------------------
-- drawTabBar
-- Tab widths are derived from totalWidth so they always fill
-- the bar exactly (last tab absorbs any rounding remainder).
-- Returns hit-test list.
-- ----------------------------------------------------------
function UI.drawTabBar(x, y, totalWidth, tabs, activeIndex)
    local n     = #tabs
    local baseW = math.floor(totalWidth / n)
    local hits  = {}

    for i, label in ipairs(tabs) do
        -- Last tab absorbs the remainder pixel(s)
        local tabW  = (i == n) and (x + totalWidth - (x + (i-1)*baseW)) or baseW
        local tx    = x + (i - 1) * baseW
        local isAct = (i == activeIndex)
        local bg    = isAct and UI.Theme.accent    or UI.Theme.surfaceInset
        local fg    = isAct and UI.Theme.textOnAccent or UI.Theme.textSecondary

        _gpu.setBackground(bg)
        _gpu.fill(tx, y, tabW, 1, " ")
        UI.centerText(tx, y, tabW, label, fg, bg)

        table.insert(hits, { x = tx, y = y, w = tabW, h = 1, index = i })
    end

    return hits
end

-- ----------------------------------------------------------
-- drawTaskbar
-- Returns startRect and list of window pill rects.
-- ----------------------------------------------------------
function UI.drawTaskbar(screenW, screenH, windows, startOpen, clockText)
    local y   = screenH
    local bar = UI.Theme.chromeMid

    _gpu.setBackground(bar)
    _gpu.fill(1, y, screenW, 1, " ")

    -- Start button
    local startBg = startOpen and UI.Theme.accent or bar
    _gpu.setBackground(startBg)
    _gpu.setForeground(UI.Theme.textOnAccent)
    _gpu.fill(1, y, 6, 1, " ")
    _gpu.set(2, y, " [+] ")   -- ASCII approximation of Windows logo

    -- Divider
    _gpu.setForeground(UI.Theme.chromeBorder)
    _gpu.setBackground(bar)
    _gpu.set(7, y, "\xE2\x94\x82")

    -- Window pills
    local pills = {}
    local px    = 9
    for i, win in ipairs(windows or {}) do
        if px + 15 < screenW - 8 then
            local isF   = win.focused
            local pillBg = isF and UI.Theme.chromeBorder or bar
            _gpu.setBackground(pillBg)
            _gpu.fill(px, y, 14, 1, " ")
            _gpu.setForeground(UI.Theme.textOnDark)
            _gpu.set(px + 1, y, UI.truncate(win.title or "?", 12))
            if isF then
                _gpu.setForeground(UI.Theme.accent)
                _gpu.set(px,      y, "\xE2\x96\x81")   -- U+2581 lower-1/8 block
                _gpu.set(px + 13, y, "\xE2\x96\x81")
            end
            table.insert(pills, { x = px, y = y, w = 14, h = 1, index = i })
            px = px + 15
        end
    end

    -- Clock (right-aligned)
    local clock = clockText or ""
    local clen  = ulen(clock)
    _gpu.setBackground(bar)
    _gpu.setForeground(UI.Theme.textOnDark)
    _gpu.set(screenW - clen - 1, y, clock)

    -- Tray divider
    _gpu.setForeground(UI.Theme.chromeBorder)
    _gpu.set(screenW - clen - 3, y, "\xE2\x94\x82")

    local startRect = { x = 1, y = y, w = 6, h = 1 }
    return startRect, pills
end

-- ----------------------------------------------------------
-- drawStatusBanner  (full-width, 1 row)
-- status: "success" | "warning" | "danger" | "info"
-- ----------------------------------------------------------
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

-- ----------------------------------------------------------
-- drawDivider  (horizontal rule)
-- ----------------------------------------------------------
function UI.drawDivider(x, y, w, color)
    _gpu.setForeground(color or UI.Theme.divider)
    _gpu.setBackground(UI.Theme.surface)
    for col = 0, w - 1 do
        _gpu.set(x + col, y, "\xE2\x94\x80")
    end
end

-- ----------------------------------------------------------
-- spinner  (call repeatedly with an incrementing frame int)
-- ----------------------------------------------------------
function UI.spinner(x, y, frame, color, bg)
    local frames = { "|", "/", "-", "\\", "|", "/", "-", "\\" }
    _gpu.setForeground(color or UI.Theme.accent)
    _gpu.setBackground(bg or UI.Theme.surface)
    _gpu.set(x, y, frames[(frame % #frames) + 1])
end

-- ----------------------------------------------------------
-- hitTest
-- ----------------------------------------------------------
function UI.hitTest(rect, mx, my)
    return mx >= rect.x
       and mx <  rect.x + rect.w
       and my >= rect.y
       and my <  rect.y + rect.h
end

-- ----------------------------------------------------------
-- clearScreen
-- ----------------------------------------------------------
function UI.clearScreen(screenW, screenH, bg)
    _gpu.setBackground(bg or UI.Theme.surface)
    _gpu.fill(1, 1, screenW, screenH, " ")
end

return UI
