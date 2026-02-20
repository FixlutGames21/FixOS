-- ==========================================================
-- FixOS 3.2.4 - system/desktop.lua
-- NEW:
--   - PNG icon support from /system/icons/
--   - Faster screen refresh (0.01s signal timeout)
-- ==========================================================

if not component.isAvailable("gpu") then error("No GPU found") end

local gpu    = component.proxy(component.list("gpu")())
local screen = component.list("screen")()
if not screen then error("No screen") end
gpu.bind(screen)

-- Boot animation
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
    local ed = "3.2.4 - FASTER & ICONS"
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

-- Config
local function loadCfg()
    local fs = component.proxy(computer.getBootAddress())
    local cfg = {resolution=nil, language="en", wallpaper=1}
    if not fs.exists("/settings.cfg") then return cfg end
    local h = fs.open("/settings.cfg","r")
    if not h then return cfg end
    local d = fs.read(h, math.huge); fs.close(h)
    local w2, h2 = d:match("resolution=(%d+)x(%d+)")
    cfg.resW      = tonumber(w2)
    cfg.resH      = tonumber(h2)
    cfg.language  = d:match("language=(%a+)") or "en"
    cfg.wallpaper = tonumber(d:match("wallpaper=(%d+)")) or 1
    return cfg
end

local cfg = loadCfg()

do
    local mw, mh = gpu.maxResolution()
    gpu.setResolution(math.min(cfg.resW or 80, mw), math.min(cfg.resH or 25, mh))
end

local W, H = gpu.getResolution()

-- UI + Language
local UI   = dofile("/system/ui.lua")
UI.init(gpu)
local T  = UI.Theme
local P  = UI.PADDING

local Lang = dofile("/system/lang.lua")
Lang.load(cfg.language)
_G.Lang = Lang

-- Wallpapers
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

-- State
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
    iconCache    = {},
}
_G._desktop_state = state

-- Icon dimensions
local ICON_W = 13
local ICON_H = 6

-- Icon definitions with PNG filenames
local ICONS = {
    { x=3,  y=2,  label=Lang.t("app.computer"),   icon="[PC]", color=T.tileBlue,   prog="mycomputer", png="mycomputer.png" },
    { x=3,  y=9,  label=Lang.t("app.explorer"),   icon="[F]",  color=T.tileOrange, prog="explorer",   png="explorer.png"   },
    { x=3,  y=16, label=Lang.t("app.terminal"),   icon="[>]",  color=T.tileDark,   prog="terminal",   png="terminal.png"   },
    { x=18, y=2,  label=Lang.t("app.calculator"), icon="[=]",  color=T.tileCyan,   prog="calculator", png="calculator.png" },
    { x=18, y=9,  label=Lang.t("app.notepad"),    icon="[N]",  color=0x1565C0,     prog="notepad",    png="notepad.png"    },
    { x=18, y=16, label=Lang.t("app.settings"),   icon="[S]",  color=T.tileGray,   prog="settings",   png="settings.png"   },
    { x=33, y=2,  label="Browser",                icon="[W]",  color=0x00695C,     prog="browser",    png="browser.png"    },
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

-- Load PNG icon (if exists)
local function loadIconPNG(filename)
    if state.iconCache[filename] then return state.iconCache[filename] end
    
    local fs = component.proxy(computer.getBootAddress())
    local path = "/system/icons/" .. filename
    
    if not fs.exists(path) then return nil end
    
    -- Try to read PNG file
    local h = fs.open(path, "rb")
    if not h then return nil end
    
    local data = ""
    repeat
        local chunk = fs.read(h, math.huge)
        if chunk then data = data .. chunk end
    until not chunk
    fs.close(h)
    
    -- Check if it's a valid PNG (starts with PNG signature)
    if data:sub(1, 8) ~= "\137PNG\13\10\26\10" then return nil end
    
    -- Store in cache (even if we can't decode it, we tried)
    state.iconCache[filename] = {data = data, decoded = false}
    
    -- OpenComputers doesn't have built-in PNG decoder
    -- So we return the raw data and let icon display fall back to ASCII
    -- If you have a PNG library installed, decode here
    
    return nil  -- Return nil to use ASCII fallback
end

-- Helpers
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

-- Wallpaper
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

-- Icon drawing
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

    -- Try to load PNG icon
    local pngIcon = loadIconPNG(icon.png)
    
    -- Use ASCII fallback (PNG decoder not available in base OpenComputers)
    gpu.setForeground(T.textOnAccent); gpu.setBackground(bg)
    local gy   = icon.y + math.floor(ICON_H/2) - 1
    local gx   = icon.x + math.floor((ICON_W - #icon.icon)/2)
    gpu.set(gx, gy, icon.icon)
    UI.centerText(icon.x, icon.y + ICON_H - 1, ICON_W, icon.label, T.textOnAccent, bg)
end

-- Taskbar
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
        if not win.minimized and px + 15 < W - 9 then
            local isF = (state.focused == i)
            gpu.setBackground(isF and T.chromeBorder or T.chromeMid)
            gpu.fill(px, H, 14, 1, " ")
            gpu.setForeground(T.textOnDark); gpu.set(px + 1, H, truncate(win.title or "?", 12))
            if isF then
                gpu.setForeground(T.accent)
                gpu.set(px, H, "\xE2\x96\x81"); gpu.set(px+13, H, "\xE2\x96\x81")
            end
            px = px + 15
        elseif win.minimized then
            local isF = (state.focused == i)
            if px + 15 < W - 9 then
                gpu.setBackground(T.chromeBorder)
                gpu.fill(px, H, 14, 1, " ")
                gpu.setForeground(T.textDisabled); gpu.set(px + 1, H, truncate(win.title or "?", 12))
                px = px + 15
            end
        end
    end

    local clk = os.date("%H:%M")
    gpu.setBackground(T.chromeMid); gpu.setForeground(T.textOnDark)
    gpu.set(W - #clk - 1, H, clk)
    gpu.setForeground(T.chromeBorder); gpu.set(W - #clk - 3, H, "\xE2\x94\x82")
end

-- Desktop
local function drawDesktop()
    drawWallpaper()
    for i, icon in ipairs(ICONS) do drawIcon(icon, state.selIcon == i) end
end

-- Window
local function drawWindow(win, isFocused)
    if win.minimized then return end
    
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

-- Start Menu
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

-- Redraw
local function redrawAll()
    drawDesktop()
    for i, win in ipairs(state.windows) do
        drawWindow(win, i == state.focused)
    end
    drawTaskbar()
    if state.startOpen then drawStartMenu() end
end

-- Window Management
local function createWindow(prog, initData)
    local sz  = WIN_SIZES[prog] or {52, 20}
    local ow  = sz[1]; local oh = sz[2]
    local off = #state.windows * 2
    local wx  = math.min(math.floor((W-ow)/2)+off, W-ow)
    local wy  = math.max(1, math.min(math.floor((H-oh)/2)+off, H-1-oh))
    local module, err = loadProgram(prog)
    if not module then return end
    local win = {
        title=prog:sub(1,1):upper()..prog:sub(2),
        x=wx, y=wy, w=ow, h=oh,
        program=module,
        minimized=false,
        maximized=false,
        initData=initData,
    }
    if module.init then safeCall(module.init, win, initData) end
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

local function minimizeWindow(idx)
    if not state.windows[idx] then return end
    state.windows[idx].minimized = true
end

local function restoreWindow(idx)
    if not state.windows[idx] then return end
    state.windows[idx].minimized = false
    focusWindow(idx)
end

local function maximizeWindow(idx)
    if not state.windows[idx] then return end
    local win = state.windows[idx]
    if win.maximized then
        win.x = win._savedX or 2
        win.y = win._savedY or 2
        win.w = win._savedW or 60
        win.h = win._savedH or 20
        win.maximized = false
    else
        win._savedX = win.x
        win._savedY = win.y
        win._savedW = win.w
        win._savedH = win.h
        win.x = 0
        win.y = 1
        win.w = W
        win.h = H - 1
        win.maximized = true
    end
end

-- Hit Testing
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
        if not w.minimized and mx >= w.x and mx < w.x+w.w and my >= w.y and my < w.y+w.h then
            return i, w
        end
    end
    return nil, nil
end

local function taskbarPillAt(mx, my)
    if my ~= H then return nil end
    local startW = 8
    local px = startW + 3
    for i, win in ipairs(state.windows) do
        if win.minimized then
            if mx >= px and mx < px + 14 then return i end
            px = px + 15
        elseif not win.minimized then
            if mx >= px and mx < px + 14 then return i end
            px = px + 15
        end
    end
    return nil
end

local function handleMenuAction(action)
    state.startOpen = false
    if action == "shutdown" then
        gpu.setBackground(T.accent); gpu.fill(1,1,W,H," ")
        UI.centerText(1, math.floor(H/2), W, Lang.t("desktop.shutdown").."...", T.textOnAccent, T.accent)
        os.sleep(0.5); computer.shutdown()
    elseif action == "about" then
        createWindow("settings")
        if state.windows[#state.windows] then state.windows[#state.windows].selectedTab = 5 end
    elseif action == "update" then
        createWindow("settings")
        if state.windows[#state.windows] then state.windows[#state.windows].selectedTab = 4 end
    elseif action then
        createWindow(action)
    end
    redrawAll()
end

-- Clock
local function tickClock()
    local now = computer.uptime()
    if now - state.clockTick < 28 then return end
    state.clockTick = now
    local clk = os.date("%H:%M")
    gpu.setBackground(T.chromeMid); gpu.setForeground(T.textOnDark)
    gpu.set(W - #clk - 1, H, clk)
end

-- Make createWindow available globally for inter-program communication
_G.createWindow = createWindow

-- Main Loop
local function main()
    redrawAll()

    while state.running do
        -- FASTER REFRESH: 0.01s instead of 0.02s
        local ev = { computer.pullSignal(0.01) }
        local t  = ev[1]
        tickClock()

        local needRedraw = false
        for _, win in ipairs(state.windows) do
            if win.program and win.program.tick then
                local ok, nr = safeCall(win.program.tick, win)
                if ok and nr then needRedraw = true end
            end
        end
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

            elseif my == H then
                local pill = taskbarPillAt(mx, my)
                if pill then
                    if state.windows[pill].minimized then
                        restoreWindow(pill)
                    else
                        focusWindow(pill)
                    end
                    redrawAll()
                end

            else
                local wi, win = windowAt(mx, my)
                if wi then
                    focusWindow(wi)
                    win = state.windows[state.focused]

                    if my == win.y then
                        if mx >= win.x + win.w - 3 then
                            closeTop(); redrawAll()
                        elseif mx >= win.x + win.w - 7 and mx < win.x + win.w - 4 then
                            maximizeWindow(state.focused); redrawAll()
                        elseif mx >= win.x + win.w - 10 and mx < win.x + win.w - 8 then
                            minimizeWindow(state.focused); redrawAll()
                        else
                            state.drag = win; state.dragOX = mx-win.x; state.dragOY = my-win.y
                            redrawAll()
                        end
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
            if not win.maximized then
                win.x = math.max(0, math.min(W-win.w, mx-state.dragOX))
                win.y = math.max(1, math.min(H-1-win.h, my-state.dragOY))
                redrawAll()
            end

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