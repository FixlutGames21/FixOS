-- ==========================================================
-- FixOS 3.2.1 - system/desktop.lua
-- CHANGES:
--   - Wallpaper color presets (loaded from settings.cfg)
--   - program.tick(win) support for async operations
--   - _G._desktop_state exposed for wallpaper live-update
-- ==========================================================

if not component.isAvailable("gpu") then error("No GPU found") end

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
    local ed = "3.2.1 - PIXEL PERFECT EDITION"
    gpu.set(math.floor((bw - #ed) / 2), ly + #logo + 1, ed)
    local sp = { "|", "/", "-", "\\", "|", "/", "-", "\\" }
    local sy = ly + #logo + 3
    local sx = math.floor(bw / 2) - 1
    for f = 1, 20 do
        gpu.setForeground(0xFFFFFF); gpu.setBackground(0x0078D7)
        gpu.set(sx, sy, sp[(f % #sp) + 1])
        computer.beep(180 + f * 12, 0.01); os.sleep(0.04)
    end
    os.sleep(0.1)
end
showBoot()

-- ----------------------------------------------------------
-- CONFIG LOAD
-- ----------------------------------------------------------
local function loadCfg()
    local fs = component.proxy(computer.getBootAddress())
    local cfg = {resolution=nil, language="en", wallpaper=1}
    if not fs.exists("/settings.cfg") then return cfg end
    local h = fs.open("/settings.cfg","r")
    if not h then return cfg end
    local d = fs.read(h, math.huge); fs.close(h)
    local w2, h2 = d:match("resolution=(%d+)x(%d+)")
    cfg.resW     = tonumber(w2)
    cfg.resH     = tonumber(h2)
    cfg.language = d:match("language=(%a+)") or "en"
    cfg.wallpaper = tonumber(d:match("wallpaper=(%d+)")) or 1
    return cfg
end

local cfg = loadCfg()

do
    local mw, mh = gpu.maxResolution()
    gpu.setResolution(math.min(cfg.resW or 80, mw), math.min(cfg.resH or 25, mh))
end

local W, H = gpu.getResolution()

-- ----------------------------------------------------------
-- UI + LANGUAGE
-- ----------------------------------------------------------
local UI   = dofile("/system/ui.lua")
UI.init(gpu)
local T  = UI.Theme
local P  = UI.PADDING

local Lang = dofile("/system/lang.lua")
Lang.load(cfg.language)
_G.Lang = Lang

-- ----------------------------------------------------------
-- WALLPAPER PRESETS (must match settings.lua WALLPAPERS table)
-- ----------------------------------------------------------
local WALLPAPERS = {
    {top=0x0078D7, bot=0x005A9E},
    {top=0x1A1A2E, bot=0x16213E},
    {top=0x1B5E20, bot=0x2E7D32},
    {top=0x4A148C, bot=0x6A1B9A},
    {top=0xB71C1C, bot=0xE64A19},
    {top=0x424242, bot=0x616161},
    {top=0x006064, bot=0x00838F},
    {top=0x0C0C0C, bot=0x1A1A1A},
}

-- ----------------------------------------------------------
-- STATE
-- ----------------------------------------------------------
local state = {
    running      = true,
    windows      = {},
    focused      = nil,
    drag         = nil,
    dragOX       = 0,
    dragOY       = 0,
    startOpen    = false,
    selIcon      = nil,
    clockTick    = 0,
    wallpaperIdx = cfg.wallpaper or 1,
}
-- Expose state globally so programs (settings) can change wallpaper live
_G._desktop_state = state

-- ----------------------------------------------------------
-- ICONS
-- ----------------------------------------------------------
local ICON_W = 13
local ICON_H = 6

local ICONS = {
    { x=3,  y=2,  label=Lang.t("app.computer"),   icon="[PC]", color=T.tileBlue,   prog="mycomputer" },
    { x=3,  y=9,  label=Lang.t("app.explorer"),   icon="[F]",  color=T.tileOrange, prog="explorer"   },
    { x=3,  y=16, label=Lang.t("app.terminal"),   icon="[>]",  color=T.tileDark,   prog="terminal"   },
    { x=18, y=2,  label=Lang.t("app.calculator"), icon="[=]",  color=T.tileCyan,   prog="calculator" },
    { x=18, y=9,  label=Lang.t("app.notepad"),    icon="[N]",  color=0x1565C0,     prog="notepad"    },
    { x=18, y=16, label=Lang.t("app.settings"),   icon="[S]",  color=T.tileGray,   prog="settings"   },
    { x=33, y=2,  label="Browser",                icon="[W]",  color=0x00695C,     prog="browser"    },
}

local WIN_SIZES = {
    calculator = {45, 22},
    notepad    = {60, 22},
    settings   = {64, 24},
    mycomputer = {58, 20},
    terminal   = {66, 22},
    explorer   = {64, 22},
    browser    = {72, 22},
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
    return pcall(fn, ...)
end

-- ----------------------------------------------------------
-- WALLPAPER DRAW
-- ----------------------------------------------------------
local function drawWallpaper()
    local wp  = WALLPAPERS[math.max(1, math.min(#WALLPAPERS, state.wallpaperIdx or 1))]
    local top = wp.top
    local bot = wp.bot

    local function interp(c1, c2, t)
        local r1,g1,b1 = math.floor(c1/0x10000), math.floor((c1%0x10000)/256), c1%256
        local r2,g2,b2 = math.floor(c2/0x10000), math.floor((c2%0x10000)/256), c2%256
        local r = math.floor(r1 + (r2-r1)*t)
        local g = math.floor(g1 + (g2-g1)*t)
        local b = math.floor(b1 + (b2-b1)*t)
        return r*0x10000 + g*0x100 + b
    end

    local rows = H - 1
    for row = 1, rows do
        local t = (row - 1) / math.max(1, rows - 1)
        gpu.setBackground(interp(top, bot, t))
        gpu.fill(1, row, W, 1, " ")
    end
end

-- ----------------------------------------------------------
-- ICON DRAW (no shadow)
-- ----------------------------------------------------------
local function drawIcon(icon, selected)
    local bg = icon.color
    if selected then
        gpu.setBackground(T.accentSubtle)
        gpu.fill(icon.x - 1, icon.y - 1, ICON_W + 2, ICON_H + 2, " ")
    end

    gpu.setBackground(bg); gpu.fill(icon.x, icon.y, ICON_W, ICON_H, " ")

    local r = math.min(255, math.floor(bg/0x10000)+40)
    local g = math.min(255, math.floor((bg%0x10000)/256)+40)
    local b = math.min(255, bg%256+40)
    gpu.setBackground(r*0x10000+g*0x100+b)
    gpu.fill(icon.x, icon.y, 2, ICON_H, " ")

    gpu.setForeground(T.textOnAccent); gpu.setBackground(bg)
    local gy   = icon.y + math.floor(ICON_H/2) - 1
    local gx   = icon.x + math.floor((ICON_W - #icon.icon)/2)
    gpu.set(gx, gy, icon.icon)
    UI.centerText(icon.x, icon.y + ICON_H - 1, ICON_W, icon.label, T.textOnAccent, bg)
end

-- ----------------------------------------------------------
-- TASKBAR
-- ----------------------------------------------------------
local function drawTaskbar()
    gpu.setBackground(T.chromeMid); gpu.fill(1, H, W, 1, " ")

    local startLabel = " " .. Lang.t("desktop.start") .. " "
    local startBg    = state.startOpen and T.accent or T.chromeMid
    local startW     = math.max(6, #startLabel + 2)
    gpu.setBackground(startBg); gpu.setForeground(T.textOnAccent)
    gpu.fill(1, H, startW, 1, " "); gpu.set(2, H, startLabel)

    gpu.setForeground(T.chromeBorder); gpu.setBackground(T.chromeMid)
    gpu.set(startW + 1, H, "\xE2\x94\x82")

    local px = startW + 3
    for i, win in ipairs(state.windows) do
        if px + 15 < W - 9 then
            local isF = (state.focused == i)
            gpu.setBackground(isF and T.chromeBorder or T.chromeMid)
            gpu.fill(px, H, 14, 1, " ")
            gpu.setForeground(T.textOnDark); gpu.set(px + 1, H, truncate(win.title or "?", 12))
            if isF then
                gpu.setForeground(T.accent)
                gpu.set(px, H, "\xE2\x96\x81"); gpu.set(px+13, H, "\xE2\x96\x81")
            end
            px = px + 15
        end
    end

    local clk = os.date("%H:%M")
    gpu.setBackground(T.chromeMid); gpu.setForeground(T.textOnDark)
    gpu.set(W - #clk - 1, H, clk)
    gpu.setForeground(T.chromeBorder); gpu.set(W - #clk - 3, H, "\xE2\x94\x82")
end

-- ----------------------------------------------------------
-- DESKTOP
-- ----------------------------------------------------------
local function drawDesktop()
    drawWallpaper()
    for i, icon in ipairs(ICONS) do drawIcon(icon, state.selIcon == i) end
end

-- ----------------------------------------------------------
-- WINDOW
-- ----------------------------------------------------------
local function drawWindow(win, isFocused)
    local cx, cy, cw, ch = UI.drawWindow(win.x, win.y, win.w, win.h, win.title, isFocused)
    win._cx, win._cy, win._cw, win._ch = cx, cy, cw, ch
    if win.program and win.program.draw then
        local ok, err = safeCall(win.program.draw, win, gpu, cx, cy, cw, ch)
        if not ok then
            gpu.setBackground(T.surface); gpu.setForeground(T.danger)
            gpu.set(cx, cy, truncate("Error: "..tostring(err), cw))
        end
    end
end

-- ----------------------------------------------------------
-- START MENU
-- ----------------------------------------------------------
local START_MENU_TILES = {
    { label=Lang.t("app.programs"),  icon="[P]", color=T.tileBlue,   action="calculator" },
    { label=Lang.t("app.explorer"),  icon="[F]", color=T.tileOrange, action="explorer"   },
    { label=Lang.t("app.terminal"),  icon="[>]", color=T.tileDark,   action="terminal"   },
    { label=Lang.t("app.settings"),  icon="[S]", color=T.tileGray,   action="settings"   },
    { label="Browser",               icon="[W]", color=0x00695C,     action="browser"    },
    { label=Lang.t("app.update"),    icon="[U]", color=T.tileGreen,  action="update"     },
}

local _menuHits = {}
local MENU_W    = 2 + (UI.TILE_W + UI.TILE_GAP) * 2 - UI.TILE_GAP + 2
local MENU_H    = 3 + (UI.TILE_H + UI.TILE_GAP) * 3 - UI.TILE_GAP + 4

local function drawStartMenu()
    local mx = 1; local my = H - MENU_H - 1
    gpu.setBackground(T.chromeMid); gpu.fill(mx, my, MENU_W, MENU_H, " ")
    gpu.setBackground(T.chromeDark); gpu.fill(mx, my, MENU_W, 2, " ")
    gpu.setForeground(T.textOnDark); gpu.set(mx + 2, my + 1, "[U] " .. Lang.t("desktop.user"))
    gpu.setBackground(T.chromeMid); gpu.setForeground(T.textSecondary)
    gpu.set(mx + 2, my + 3, Lang.t("desktop.apps"))
    _menuHits = UI.drawStartMenuGrid(mx + 2, my + 4, START_MENU_TILES)
    local powerY = my + MENU_H - 2
    gpu.setBackground(T.danger); gpu.fill(mx, powerY, MENU_W, 2, " ")
    UI.centerText(mx, powerY + 1, MENU_W, "[X] " .. Lang.t("desktop.shutdown"), T.textOnAccent, T.danger)
    table.insert(_menuHits, {x=mx, y=powerY, w=MENU_W, h=2, action="shutdown"})
end

-- ----------------------------------------------------------
-- FULL REDRAW
-- ----------------------------------------------------------
local function redrawAll()
    drawDesktop()
    for i, win in ipairs(state.windows) do drawWindow(win, i == state.focused) end
    drawTaskbar()
    if state.startOpen then drawStartMenu() end
end

-- ----------------------------------------------------------
-- WINDOW MANAGEMENT
-- ----------------------------------------------------------
local function createWindow(prog)
    local sz  = WIN_SIZES[prog] or {52, 20}
    local ow  = sz[1]; local oh = sz[2]
    local off = #state.windows * 2
    local wx  = math.min(math.floor((W-ow)/2)+off, W-ow)
    local wy  = math.max(1, math.min(math.floor((H-oh)/2)+off, H-1-oh))
    local module, err = loadProgram(prog)
    if not module then return end
    local win = {title=prog:sub(1,1):upper()..prog:sub(2), x=wx, y=wy, w=ow, h=oh, program=module}
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
        if mx >= ic.x and mx < ic.x+ICON_W and my >= ic.y and my < ic.y+ICON_H then
            return i
        end
    end
end

local function windowAt(mx, my)
    for i = #state.windows, 1, -1 do
        local w = state.windows[i]
        if mx >= w.x and mx < w.x+w.w and my >= w.y and my < w.y+w.h then
            return i, w
        end
    end
    return nil, nil
end

local function handleMenuAction(action)
    state.startOpen = false
    if action == "shutdown" then
        gpu.setBackground(T.accent); gpu.fill(1,1,W,H," ")
        UI.centerText(1, math.floor(H/2), W, Lang.t("desktop.shutdown").."...", T.textOnAccent, T.accent)
        os.sleep(0.5); computer.shutdown()
    elseif action == "about" then
        createWindow("settings")
        if state.windows[#state.windows] then state.windows[#state.windows].selectedTab = 4 end
    elseif action == "update" then
        createWindow("settings")
        if state.windows[#state.windows] then state.windows[#state.windows].selectedTab = 3 end
    elseif action then
        createWindow(action)
    end
    redrawAll()
end

-- ----------------------------------------------------------
-- CLOCK
-- ----------------------------------------------------------
local function tickClock()
    local now = computer.uptime()
    if now - state.clockTick < 28 then return end
    state.clockTick = now
    local clk = os.date("%H:%M")
    gpu.setBackground(T.chromeMid); gpu.setForeground(T.textOnDark)
    gpu.set(W - #clk - 1, H, clk)
end

-- ----------------------------------------------------------
-- MAIN LOOP
-- ----------------------------------------------------------
local function main()
    redrawAll()

    while state.running do
        local ev = { computer.pullSignal(0.02) }
        local t  = ev[1]
        tickClock()

        -- Call tick() on all windows that have it (for async ops)
        local needRedraw = false
        for _, win in ipairs(state.windows) do
            if win.program and win.program.tick then
                local ok, nr = safeCall(win.program.tick, win)
                if ok and nr then needRedraw = true end
            end
        end
        -- Check if wallpaper changed live
        if state._lastWallpaper ~= state.wallpaperIdx then
            state._lastWallpaper = state.wallpaperIdx
            needRedraw = true
        end
        if needRedraw then redrawAll() end

        if t == "touch" then
            local _, _, mx, my, btn = table.unpack(ev)

            if state.startOpen then
                local hit = false
                for _, h in ipairs(_menuHits) do
                    if UI.hitTest(h, mx, my) then
                        handleMenuAction(h.action); hit = true; break
                    end
                end
                if not hit then state.startOpen = false; redrawAll() end

            elseif my == H and mx >= 1 and mx <= 10 then
                state.startOpen = not state.startOpen; redrawAll()

            else
                local wi, win = windowAt(mx, my)
                if wi then
                    focusWindow(wi)
                    win = state.windows[state.focused]
                    if my == win.y and mx >= win.x + win.w - 3 then
                        closeTop(); redrawAll()
                    elseif my == win.y then
                        state.drag = win; state.dragOX = mx-win.x; state.dragOY = my-win.y
                        redrawAll()
                    else
                        local ok, nr = safeCall(win.program and win.program.click, win, mx, my, btn)
                        if nr then redrawAll() end
                    end
                else
                    local ii = iconAt(mx, my)
                    if ii then
                        if state.selIcon == ii then
                            createWindow(ICONS[ii].prog); state.selIcon = nil
                        else
                            state.selIcon = ii
                        end
                        redrawAll()
                    else
                        state.selIcon = nil; redrawAll()
                    end
                end
            end

        elseif t == "drag" and state.drag then
            local _, _, mx, my = table.unpack(ev)
            local win = state.drag
            win.x = math.max(0, math.min(W-win.w, mx-state.dragOX))
            win.y = math.max(1, math.min(H-1-win.h, my-state.dragOY))
            redrawAll()

        elseif t == "drop" then
            state.drag = nil

        elseif t == "scroll" then
            local _, _, mx, my, dir = table.unpack(ev)
            if state.focused and state.windows[state.focused] then
                local win = state.windows[state.focused]
                if mx >= win.x and mx < win.x+win.w and my >= win.y and my < win.y+win.h then
                    local ok, nr = safeCall(win.program and win.program.scroll, win, dir)
                    if nr then redrawAll() end
                end
            end

        elseif t == "key_down" then
            local _, _, char, code = table.unpack(ev)
            if state.focused and state.windows[state.focused] then
                local win = state.windows[state.focused]
                local ok, nr = safeCall(win.program and win.program.key, win, char, code)
                if nr then redrawAll() end
            end
        end
    end
end

local ok, err = pcall(main)
if not ok then
    gpu.setBackground(T.danger); gpu.setForeground(T.textOnAccent)
    gpu.fill(1,1,W,H," ")
    gpu.set(2,2,"Desktop crashed:")
    gpu.set(2,3,UI.truncate(tostring(err), W-4))
    gpu.set(2,5,"Press any key to reboot")
    computer.pullSignal(); computer.shutdown(true)
end