-- ==========================================================
-- FixOS 3.1.2 - system/desktop.lua
-- FIXES:
--   - Shadow rendered only below/right (not over window body)
--   - centerText uses unicode.len() via UI library
--   - Start Menu tile colors use UI.Theme.tileDark / tileGray
--     instead of raw 0x2D2D30 which was invisible against menu bg
--   - PADDING constant from UI library used throughout
--   - Icon label centering fixed
-- ==========================================================

if not component.isAvailable("gpu") then
    error("No GPU found")
end

local gpu    = component.proxy(component.list("gpu")())
local screen = component.list("screen")()
if not screen then error("No screen") end
gpu.bind(screen)

-- ----------------------------------------------------------
-- BOOT ANIMATION
-- ----------------------------------------------------------
local function showBoot()
    local maxW, maxH = gpu.maxResolution()
    local bw = math.min(80, maxW)
    local bh = math.min(25, maxH)
    gpu.setResolution(bw, bh)

    gpu.setBackground(0x0078D7)
    gpu.fill(1, 1, bw, bh, " ")

    local logo = {
        "  ___ _       ___  ____  ",
        " | __(_)_ __ / _ \\/ ___| ",
        " | _|| \\ \\ // | | \\___ \\ ",
        " |_| |_/_\\_\\\\|_|_|/____/ ",
    }

    gpu.setForeground(0xFFFFFF)
    local ly = math.floor(bh / 2) - 4
    for i, line in ipairs(logo) do
        gpu.set(math.floor((bw - #line) / 2), ly + i - 1, line)
    end

    gpu.setForeground(0xCDE8FF)
    local ed = "3.1.2 - PIXEL PERFECT EDITION"
    gpu.set(math.floor((bw - #ed) / 2), ly + #logo + 1, ed)

    local spinners = { "|", "/", "-", "\\", "|", "/", "-", "\\" }
    local sy = ly + #logo + 3
    local sx = math.floor(bw / 2) - 1
    for f = 1, 24 do
        gpu.setForeground(0xFFFFFF)
        gpu.setBackground(0x0078D7)
        gpu.set(sx, sy, spinners[(f % #spinners) + 1])
        computer.beep(180 + f * 12, 0.01)
        os.sleep(0.04)
    end
    os.sleep(0.15)
end

showBoot()

-- ----------------------------------------------------------
-- RESOLUTION
-- ----------------------------------------------------------
local function loadRes()
    local fs = component.proxy(computer.getBootAddress())
    if fs.exists("/settings.cfg") then
        local h = fs.open("/settings.cfg", "r")
        if h then
            local d = fs.read(h, math.huge); fs.close(h)
            local w2, h2 = d:match("resolution=(%d+)x(%d+)")
            if w2 and h2 then return tonumber(w2), tonumber(h2) end
        end
    end
    return nil, nil
end

do
    local sw, sh = loadRes()
    local mw, mh = gpu.maxResolution()
    gpu.setResolution(math.min(sw or 80, mw), math.min(sh or 25, mh))
end

local W, H = gpu.getResolution()

-- ----------------------------------------------------------
-- LOAD UI LIBRARY
-- ----------------------------------------------------------
local UI = dofile("/system/ui.lua")
UI.init(gpu)
local T  = UI.Theme
local P  = UI.PADDING

-- ----------------------------------------------------------
-- DESKTOP ICONS (tiles, strict 13x6 each)
-- ----------------------------------------------------------
local ICON_W = 13
local ICON_H = 6

local ICONS = {
    { x=3,  y=2,  label="Computer",   icon="[PC]", color=T.tileBlue,   prog="mycomputer" },
    { x=3,  y=9,  label="Explorer",   icon="[F]",  color=T.tileOrange, prog="explorer"   },
    { x=3,  y=16, label="Terminal",   icon="[>]",  color=T.tileDark,   prog="terminal"   },
    { x=18, y=2,  label="Calculator", icon="[=]",  color=T.tileCyan,   prog="calculator" },
    { x=18, y=9,  label="Notepad",    icon="[N]",  color=0x1565C0,     prog="notepad"    },
    { x=18, y=16, label="Settings",   icon="[S]",  color=T.tileGray,   prog="settings"   },
}

-- window size presets
local WIN_SIZES = {
    calculator = {45, 22},
    notepad    = {60, 22},
    settings   = {62, 24},
    mycomputer = {58, 20},
    terminal   = {66, 22},
    explorer   = {62, 22},
}

-- ----------------------------------------------------------
-- STATE
-- ----------------------------------------------------------
local state = {
    running      = true,
    windows      = {},
    focused      = nil,   -- index into windows
    drag         = nil,   -- window being dragged
    dragOX       = 0,
    dragOY       = 0,
    startOpen    = false,
    selIcon      = nil,
    clockTick    = 0,
}

-- ----------------------------------------------------------
-- HELPERS
-- ----------------------------------------------------------
local function truncate(s, n) return UI.truncate(s, n) end

local function loadProgram(name)
    local path = "/system/programs/" .. name .. ".lua"
    local fs   = component.proxy(computer.getBootAddress())
    if not fs.exists(path) then return nil, "not found" end
    local fn, err = loadfile(path)
    if not fn then return nil, err end
    local ok, mod = pcall(fn)
    if not ok then return nil, mod end
    return mod
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false, "not a function" end
    local ok, r = pcall(fn, ...)
    return ok, r
end

-- ----------------------------------------------------------
-- ICON DRAWING
-- ----------------------------------------------------------
local function drawIcon(icon, selected)
    local bg = icon.color
    if selected then
        gpu.setBackground(T.accentSubtle)
        gpu.fill(icon.x - 1, icon.y - 1, ICON_W + 2, ICON_H + 2, " ")
    end
    -- shadow (only below/right, outside the tile)
    UI.shadow(icon.x, icon.y, ICON_W, ICON_H, 1)

    -- tile body
    gpu.setBackground(bg)
    gpu.fill(icon.x, icon.y, ICON_W, ICON_H, " ")

    -- left accent strip
    local r = math.min(255, math.floor(bg/0x10000)+40)
    local g = math.min(255, math.floor((bg%0x10000)/256)+40)
    local b = math.min(255, bg%256+40)
    gpu.setBackground(r*0x10000+g*0x100+b)
    gpu.fill(icon.x, icon.y, 2, ICON_H, " ")

    -- icon glyph (centered)
    gpu.setForeground(T.textOnAccent)
    gpu.setBackground(bg)
    local gy = icon.y + math.floor(ICON_H / 2) - 1
    -- icon centered in tile width
    local glen = #icon.icon
    local gx   = icon.x + math.floor((ICON_W - glen) / 2)
    gpu.set(gx, gy, icon.icon)

    -- label (centered, using UI.centerText which uses unicode.len)
    UI.centerText(icon.x, icon.y + ICON_H - 1, ICON_W, icon.label, T.textOnAccent, bg)
end

-- ----------------------------------------------------------
-- TASKBAR
-- ----------------------------------------------------------
local function drawTaskbar()
    gpu.setBackground(T.chromeMid)
    gpu.fill(1, H, W, 1, " ")

    -- Start button
    local startBg = state.startOpen and T.accent or T.chromeMid
    gpu.setBackground(startBg)
    gpu.setForeground(T.textOnAccent)
    gpu.fill(1, H, 6, 1, " ")
    gpu.set(2, H, " [+] ")

    -- Divider
    gpu.setForeground(T.chromeBorder)
    gpu.setBackground(T.chromeMid)
    gpu.set(7, H, "\xE2\x94\x82")

    -- Window pills
    local px = 9
    for i, win in ipairs(state.windows) do
        if px + 15 < W - 9 then
            local isF = (state.focused == i)
            gpu.setBackground(isF and T.chromeBorder or T.chromeMid)
            gpu.fill(px, H, 14, 1, " ")
            gpu.setForeground(T.textOnDark)
            gpu.set(px + 1, H, truncate(win.title or "?", 12))
            if isF then
                gpu.setForeground(T.accent)
                gpu.set(px,      H, "\xE2\x96\x81")
                gpu.set(px + 13, H, "\xE2\x96\x81")
            end
            px = px + 15
        end
    end

    -- Clock
    local clk = os.date("%H:%M")
    gpu.setBackground(T.chromeMid)
    gpu.setForeground(T.textOnDark)
    gpu.set(W - #clk - 1, H, clk)
    gpu.setForeground(T.chromeBorder)
    gpu.set(W - #clk - 3, H, "\xE2\x94\x82")
end

-- ----------------------------------------------------------
-- DESKTOP
-- ----------------------------------------------------------
local function drawDesktop()
    -- Blue gradient (3 alternating shades)
    for row = 1, H - 1 do
        local shade = 0x0078D7
        if row % 4 == 0 then shade = 0x006BB3
        elseif row % 7 == 0 then shade = 0x0082E0 end
        gpu.setBackground(shade)
        gpu.fill(1, row, W, 1, " ")
    end
    for i, icon in ipairs(ICONS) do
        drawIcon(icon, state.selIcon == i)
    end
end

-- ----------------------------------------------------------
-- WINDOW DRAWING
-- ----------------------------------------------------------
local function drawWindow(win, isFocused)
    -- Use UI.drawWindow which has correct shadow + borders
    local cx, cy, cw, ch = UI.drawWindow(win.x, win.y, win.w, win.h, win.title, isFocused)
    win._cx, win._cy, win._cw, win._ch = cx, cy, cw, ch

    if win.program and win.program.draw then
        local ok, err = safeCall(win.program.draw, win, gpu, cx, cy, cw, ch)
        if not ok then
            gpu.setBackground(T.surface)
            gpu.setForeground(T.danger)
            gpu.set(cx, cy, truncate("Error: " .. tostring(err), cw))
        end
    end
end

-- ----------------------------------------------------------
-- START MENU
-- ----------------------------------------------------------
local START_MENU_TILES = {
    { label="Programs",  icon="[P]", color=T.tileBlue,   action="calculator" },
    { label="Explorer",  icon="[F]", color=T.tileOrange, action="explorer"   },
    { label="Terminal",  icon="[>]", color=T.tileDark,   action="terminal"   },
    { label="Settings",  icon="[S]", color=T.tileGray,   action="settings"   },
    { label="About",     icon="[i]", color=T.info,       action="about"      },
    { label="Update",    icon="[U]", color=T.tileGreen,  action="update"     },
}

local _menuHits   = {}   -- populated each time menu is drawn
local MENU_W      = 2 + (UI.TILE_W + UI.TILE_GAP) * 2 - UI.TILE_GAP + 2
local MENU_H      = 3 + (UI.TILE_H + UI.TILE_GAP) * 3 - UI.TILE_GAP + 4

local function drawStartMenu()
    local mx = 1
    local my = H - MENU_H - 1

    -- Shadow
    UI.shadow(mx, my, MENU_W, MENU_H, 2)

    -- Background
    gpu.setBackground(T.chromeMid)
    gpu.fill(mx, my, MENU_W, MENU_H, " ")

    -- User section
    gpu.setBackground(T.chromeDark)
    gpu.fill(mx, my, MENU_W, 2, " ")
    gpu.setForeground(T.textOnDark)
    gpu.set(mx + 2, my + 1, "[U] FixOS User")

    -- "Apps" label
    gpu.setBackground(T.chromeMid)
    gpu.setForeground(T.textSecondary)
    gpu.set(mx + 2, my + 3, "Apps")

    -- Tile grid
    _menuHits = UI.drawStartMenuGrid(mx + 2, my + 4, START_MENU_TILES)

    -- Power button (full width, at bottom)
    local powerY = my + MENU_H - 2
    gpu.setBackground(T.danger)
    gpu.fill(mx, powerY, MENU_W, 2, " ")
    UI.centerText(mx, powerY + 1, MENU_W, "[X] Shut Down", T.textOnAccent, T.danger)
    table.insert(_menuHits, { x=mx, y=powerY, w=MENU_W, h=2, action="shutdown" })
end

-- ----------------------------------------------------------
-- FULL REDRAW
-- ----------------------------------------------------------
local function redrawAll()
    drawDesktop()
    for i, win in ipairs(state.windows) do
        drawWindow(win, i == state.focused)
    end
    drawTaskbar()
    if state.startOpen then drawStartMenu() end
end

-- ----------------------------------------------------------
-- WINDOW MANAGEMENT
-- ----------------------------------------------------------
local function createWindow(prog)
    local sz     = WIN_SIZES[prog] or {52, 20}
    local ow     = sz[1]; local oh = sz[2]
    local off    = #state.windows * 2
    local wx     = math.min(math.floor((W - ow) / 2) + off, W - ow)
    local wy     = math.max(1, math.min(math.floor((H - oh) / 2) + off, H - 1 - oh))
    local module, err = loadProgram(prog)
    if not module then return end

    local win = { title=prog:sub(1,1):upper()..prog:sub(2), x=wx, y=wy, w=ow, h=oh, program=module }
    if module.init then safeCall(module.init, win) end
    table.insert(state.windows, win)
    state.focused = #state.windows
    return win
end

local function closeTop()
    if #state.windows == 0 then return end
    table.remove(state.windows, state.focused)
    state.focused = #state.windows > 0 and #state.windows or nil
end

local function focusWindow(idx)
    if not state.windows[idx] then return end
    local win = table.remove(state.windows, idx)
    table.insert(state.windows, win)
    state.focused = #state.windows
end

-- ----------------------------------------------------------
-- HIT TESTING
-- ----------------------------------------------------------
local function iconAt(mx, my)
    for i, ic in ipairs(ICONS) do
        if mx >= ic.x and mx < ic.x + ICON_W and
           my >= ic.y and my < ic.y + ICON_H then
            return i
        end
    end
    return nil
end

local function windowAt(mx, my)
    for i = #state.windows, 1, -1 do
        local w = state.windows[i]
        if mx >= w.x and mx < w.x + w.w and
           my >= w.y and my < w.y + w.h then
            return i, w
        end
    end
    return nil, nil
end

local function handleMenuAction(action)
    state.startOpen = false
    if action == "shutdown" then
        gpu.setBackground(T.accent)
        gpu.fill(1,1,W,H," ")
        UI.centerText(1, math.floor(H/2), W, "Shutting down...", T.textOnAccent, T.accent)
        os.sleep(0.5)
        computer.shutdown()
    elseif action == "about" then
        createWindow("settings")
        if state.windows[#state.windows] then
            state.windows[#state.windows].selectedTab = 4
        end
    elseif action == "update" then
        createWindow("settings")
        if state.windows[#state.windows] then
            state.windows[#state.windows].selectedTab = 3
        end
    elseif action then
        createWindow(action)
    end
    redrawAll()
end

-- ----------------------------------------------------------
-- CLOCK  (only redraws the clock cell, not full screen)
-- ----------------------------------------------------------
local function tickClock()
    local now = computer.uptime()
    if now - state.clockTick < 30 then return end
    state.clockTick = now
    local clk = os.date("%H:%M")
    gpu.setBackground(T.chromeMid)
    gpu.setForeground(T.textOnDark)
    gpu.set(W - #clk - 1, H, clk)
end

-- ----------------------------------------------------------
-- MAIN LOOP
-- ----------------------------------------------------------
local function main()
    redrawAll()

    while state.running do
        local ev = { computer.pullSignal(0.03) }
        local t  = ev[1]
        tickClock()

        if t == "touch" then
            local _, _, mx, my, btn = table.unpack(ev)

            if state.startOpen then
                -- Check menu hits first
                local hit = false
                for _, h in ipairs(_menuHits) do
                    if UI.hitTest(h, mx, my) then
                        handleMenuAction(h.action)
                        hit = true
                        break
                    end
                end
                if not hit then
                    state.startOpen = false
                    redrawAll()
                end

            elseif my == H and mx >= 1 and mx <= 6 then
                -- Start button
                state.startOpen = not state.startOpen
                redrawAll()

            else
                local wi, win = windowAt(mx, my)
                if wi then
                    focusWindow(wi)
                    win = state.windows[state.focused]

                    if my == win.y and mx >= win.x + win.w - 3 then
                        -- Close button
                        closeTop()
                        redrawAll()
                    elseif my == win.y then
                        -- Start drag
                        state.drag  = win
                        state.dragOX = mx - win.x
                        state.dragOY = my - win.y
                        redrawAll()
                    else
                        -- Content click
                        local ok, nr = safeCall(win.program and win.program.click, win, mx, my, btn)
                        if nr then redrawAll() end
                    end
                else
                    local ii = iconAt(mx, my)
                    if ii then
                        if state.selIcon == ii then
                            createWindow(ICONS[ii].prog)
                            state.selIcon = nil
                        else
                            state.selIcon = ii
                        end
                        redrawAll()
                    else
                        state.selIcon = nil
                        redrawAll()
                    end
                end
            end

        elseif t == "drag" and state.drag then
            local _, _, mx, my = table.unpack(ev)
            local win = state.drag
            win.x = math.max(0, math.min(W - win.w, mx - state.dragOX))
            win.y = math.max(1, math.min(H - 1 - win.h, my - state.dragOY))
            redrawAll()

        elseif t == "drop" then
            state.drag = nil

        elseif t == "scroll" then
            local _, _, mx, my, dir = table.unpack(ev)
            if state.focused and state.windows[state.focused] then
                local win = state.windows[state.focused]
                if mx >= win.x and mx < win.x + win.w and
                   my >= win.y and my < win.y + win.h then
                    local ok, nr = safeCall(win.program and win.program.scroll, win, dir)
                    if nr then redrawAll() end
                end
            end

        elseif t == "key_down" then
            local _, _, char, code = table.unpack(ev)
            if code == 31 then           -- S key = start menu
                state.startOpen = not state.startOpen
                redrawAll()
            elseif code == 45 then       -- X key = shutdown
                handleMenuAction("shutdown")
            elseif state.focused and state.windows[state.focused] then
                local win = state.windows[state.focused]
                local ok, nr = safeCall(win.program and win.program.key, win, char, code)
                if nr then redrawAll() end
            end
        end
    end
end

local ok, err = pcall(main)
if not ok then
    gpu.setBackground(T.danger)
    gpu.setForeground(T.textOnAccent)
    gpu.fill(1, 1, W, H, " ")
    gpu.set(2, 2, "Desktop crashed:")
    gpu.set(2, 3, UI.truncate(tostring(err), W - 4))
    gpu.set(2, 5, "Press any key to reboot")
    computer.pullSignal()
    computer.shutdown(true)
end
