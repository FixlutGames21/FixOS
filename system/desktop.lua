-- ==========================================================
-- FixOS 4.0.0 - system/desktop.lua
-- ЗМІНИ 4.0.0:
--   - Покращені іконки (multi-line з символами)
--   - Нова анімація завантаження
--   - Версія синхронізована до 4.0.0
--   - Більш чіткий taskbar з назвами вікон
--   - Alt+F4 закриває активне вікно
-- ==========================================================

if not component.isAvailable("gpu") then error("No GPU found") end

local gpu    = component.proxy(component.list("gpu")())
local screen = component.list("screen")()
if not screen then error("No screen") end
gpu.bind(screen)

-- ============================================================
-- BOOT ANIMATION
-- ============================================================
local function showBoot()
    local maxW, maxH = gpu.maxResolution()
    local bw = math.min(80, maxW)
    local bh = math.min(25, maxH)
    gpu.setResolution(bw, bh)
    gpu.setBackground(0x0D1117)
    gpu.fill(1, 1, bw, bh, " ")

    local logo = {
        "\xE2\x95\x94\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x97",
        "\xE2\x95\x91  FixOS 4.0.0                    \xE2\x95\x91",
        "\xE2\x95\x91  OpenComputers Edition           \xE2\x95\x91",
        "\xE2\x95\x91  Fixed. Fast. Functional.        \xE2\x95\x91",
        "\xE2\x95\x9A\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x90\xE2\x95\x9D",
    }

    gpu.setForeground(0x0078D7)
    local ly = math.floor(bh / 2) - 3
    for i, line in ipairs(logo) do
        gpu.set(math.floor((bw - #line) / 2) + 1, ly + i - 1, line)
    end

    -- Boot progress items
    local items = {
        "Ядро системи...",
        "Підсистема пам'яті...",
        "Файлова система...",
        "Відеосистема...",
        "Готово!",
    }

    gpu.setForeground(0x666666)
    local iy = ly + #logo + 2
    for i, item in ipairs(items) do
        gpu.set(math.floor(bw/2) - 12, iy, "[    ] " .. item)
        computer.beep(200 + i * 60, 0.03)
        os.sleep(0.05)
        gpu.setForeground(0x10893E)
        gpu.set(math.floor(bw/2) - 12, iy, "[ OK ]")
        gpu.setForeground(0x666666)
        iy = iy + 1
    end

    os.sleep(0.2)
end

showBoot()

-- ============================================================
-- CONFIG
-- ============================================================
local function loadCfg()
    local fs  = component.proxy(computer.getBootAddress())
    local cfg = {language="en", wallpaper=1}
    if not fs.exists("/settings.cfg") then return cfg end
    local h = fs.open("/settings.cfg","r")
    if not h then return cfg end
    local d = fs.read(h, math.huge); fs.close(h)
    local w2, h2    = d:match("resolution=(%d+)x(%d+)")
    cfg.resW        = tonumber(w2)
    cfg.resH        = tonumber(h2)
    cfg.language    = d:match("language=(%a+)") or "en"
    cfg.wallpaper   = tonumber(d:match("wallpaper=(%d+)")) or 1
    return cfg
end

local cfg = loadCfg()
do
    local mw, mh = gpu.maxResolution()
    gpu.setResolution(math.min(cfg.resW or 80, mw), math.min(cfg.resH or 25, mh))
end

local W, H = gpu.getResolution()

local UI = dofile("/system/ui.lua")
UI.init(gpu)
local T = UI.Theme

local Lang = dofile("/system/lang.lua")
Lang.load(cfg.language)
_G.Lang = Lang

-- ============================================================
-- WALLPAPERS
-- ============================================================
local WALLPAPERS = {
    {top=0x0078D7, bot=0x003F73},  -- Blue (default)
    {top=0x1A1A2E, bot=0x0D0D1A},  -- Dark Night
    {top=0x1B5E20, bot=0x0A2E0F},  -- Forest Green
    {top=0x4A148C, bot=0x1A0040},  -- Deep Purple
    {top=0xB71C1C, bot=0x5C0000},  -- Deep Red
    {top=0x37474F, bot=0x1C2833},  -- Steel Gray
    {top=0x006064, bot=0x002829},  -- Dark Teal
    {top=0x0D0D0D, bot=0x000000},  -- True Black
}

-- ============================================================
-- STATE
-- ============================================================
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
_G._desktop_state = state

-- ============================================================
-- ICONS (покращені - більше деталей)
-- ============================================================
local ICON_W = 14
local ICON_H = 5

-- Icon tile definition: x, y, label (2 lines), color, prog
-- icon field = 2 chars used for center display
local ICONS = {
    {
        x=2,  y=2,
        lines={"  [===]  ", " MyPC  "},
        label=Lang.t("app.computer"),
        color=T.tileBlue, prog="mycomputer",
    },
    {
        x=2,  y=9,
        lines={"  [F/] ", " Files "},
        label=Lang.t("app.explorer"),
        color=T.tileOrange, prog="explorer",
    },
    {
        x=2,  y=16,
        lines={" [>_]  ", "  Term "},
        label=Lang.t("app.terminal"),
        color=T.tileDark, prog="terminal",
    },
    {
        x=18, y=2,
        lines={"  [7/] ", "  Calc "},
        label=Lang.t("app.calculator"),
        color=T.tileCyan, prog="calculator",
    },
    {
        x=18, y=9,
        lines={"  [N] ", "  Note "},
        label=Lang.t("app.notepad"),
        color=0x1565C0, prog="notepad",
    },
    {
        x=18, y=16,
        lines={"  [o] ", "  Cfg  "},
        label=Lang.t("app.settings"),
        color=T.tileGray, prog="settings",
    },
    {
        x=34, y=2,
        lines={"  [W] ", " Web   "},
        label="Browser",
        color=0x00695C, prog="browser",
    },
}

local WIN_SIZES = {
    calculator = {46, 22},
    notepad    = {62, 22},
    settings   = {66, 24},
    mycomputer = {60, 22},
    terminal   = {68, 22},
    explorer   = {70, 22},
    browser    = {74, 22},
}

-- ============================================================
-- HELPERS
-- ============================================================
local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function loadProgram(name)
    local path = "/system/programs/" .. name .. ".lua"
    local fs   = component.proxy(computer.getBootAddress())
    if not fs.exists(path) then return nil end
    local fn, _ = loadfile(path)
    if not fn then return nil end
    local ok, mod = pcall(fn)
    if not ok then return nil end
    return mod
end

-- ============================================================
-- WALLPAPER
-- ============================================================
local function drawWallpaper()
    local wp = WALLPAPERS[math.max(1, math.min(#WALLPAPERS, state.wallpaperIdx or 1))]
    local function interp(c1, c2, t)
        local r1,g1,b1 = math.floor(c1/0x10000), math.floor((c1%0x10000)/256), c1%256
        local r2,g2,b2 = math.floor(c2/0x10000), math.floor((c2%0x10000)/256), c2%256
        return math.floor(r1+(r2-r1)*t)*0x10000+math.floor(g1+(g2-g1)*t)*0x100+math.floor(b1+(b2-b1)*t)
    end
    local rows = H - 1
    for row = 1, rows do
        gpu.setBackground(interp(wp.top, wp.bot, (row-1)/math.max(1,rows-1)))
        gpu.fill(1, row, W, 1, " ")
    end
end

-- ============================================================
-- ICON DRAWING (покращений)
-- ============================================================
local function drawIcon(icon, selected)
    local bg = icon.color

    -- Selection glow
    if selected then
        local r=math.min(255,math.floor(bg/0x10000)+30)
        local g=math.min(255,math.floor((bg%0x10000)/256)+30)
        local b=math.min(255,bg%256+30)
        gpu.setBackground(r*0x10000+g*0x100+b)
        gpu.fill(icon.x-1, icon.y-1, ICON_W+2, ICON_H+2, " ")
    end

    -- Main tile
    gpu.setBackground(bg)
    gpu.fill(icon.x, icon.y, ICON_W, ICON_H, " ")

    -- Top highlight stripe
    local r=math.min(255,math.floor(bg/0x10000)+50)
    local g=math.min(255,math.floor((bg%0x10000)/256)+50)
    local b=math.min(255,bg%256+50)
    gpu.setBackground(r*0x10000+g*0x100+b)
    gpu.fill(icon.x, icon.y, ICON_W, 1, " ")

    -- Left accent stripe
    local r2=math.floor(bg/0x10000)+30
    local g2=math.floor((bg%0x10000)/256)+30
    local b2=bg%256+30
    gpu.setBackground(math.min(255,r2)*0x10000+math.min(255,g2)*0x100+math.min(255,b2))
    gpu.fill(icon.x, icon.y, 1, ICON_H, " ")

    -- Icon graphic (2 lines in the center)
    gpu.setForeground(0xFFFFFF)
    gpu.setBackground(bg)
    if icon.lines then
        local midY = icon.y + math.floor(ICON_H/2) - 1
        for i, ln in ipairs(icon.lines) do
            if i <= 2 then
                local lx = icon.x + math.max(1, math.floor((ICON_W - #ln)/2))
                gpu.set(lx, midY + i - 1, ln)
            end
        end
    end

    -- Label below icon (on darker bg)
    gpu.setBackground(bg)
    gpu.setForeground(0xFFFFFF)
    UI.centerText(icon.x, icon.y + ICON_H - 1, ICON_W, icon.label, 0xFFFFFF, bg)
end

-- ============================================================
-- TASKBAR
-- ============================================================
local function drawTaskbar()
    gpu.setBackground(T.chromeMid)
    gpu.fill(1, H, W, 1, " ")

    -- Start button
    local sl   = " \xE2\x8A\x9E " .. Lang.t("desktop.start") .. " "
    local sbg  = state.startOpen and T.accent or T.accentDark
    local sw   = math.max(8, #sl + 2)
    gpu.setBackground(sbg); gpu.setForeground(T.textOnAccent)
    gpu.fill(1, H, sw, 1, " ")
    gpu.set(2, H, sl)

    -- Divider
    gpu.setForeground(T.chromeBorder); gpu.setBackground(T.chromeMid)
    gpu.set(sw + 1, H, "\xE2\x94\x82")

    -- Window pills
    local px = sw + 2
    for i, win in ipairs(state.windows) do
        if px + 16 >= W - 8 then break end
        local isF = (state.focused == i)
        local pillBg = win.minimized and T.chromeDark or (isF and T.accentDark or T.chromeMid)
        gpu.setBackground(pillBg)
        gpu.fill(px, H, 15, 1, " ")
        gpu.setForeground(win.minimized and T.textDisabled or T.textOnDark)
        gpu.set(px + 1, H, UI.truncate(win.title or "?", 13))
        if isF and not win.minimized then
            gpu.setForeground(T.accent)
            gpu.set(px, H, "\xE2\x96\x83")
            gpu.set(px+14, H, "\xE2\x96\x83")
        end
        px = px + 16
    end

    -- Clock
    local clk = os.date("%H:%M")
    gpu.setBackground(T.chromeDark); gpu.setForeground(T.textOnDark)
    gpu.fill(W - #clk - 3, H, #clk + 2, 1, " ")
    gpu.set(W - #clk - 2, H, clk)
end

-- ============================================================
-- DESKTOP DRAW
-- ============================================================
local function drawDesktop()
    drawWallpaper()
    for i, icon in ipairs(ICONS) do drawIcon(icon, state.selIcon == i) end
end

-- ============================================================
-- WINDOW DRAW
-- ============================================================
local function drawWindow(win, isFocused)
    if win.minimized then return end
    local cx, cy, cw, ch = UI.drawWindow(win.x, win.y, win.w, win.h, win.title, isFocused)
    win._cx, win._cy, win._cw, win._ch = cx, cy, cw, ch
    if win.program and win.program.draw then
        local ok, err = safeCall(win.program.draw, win, gpu, cx, cy, cw, ch)
        if not ok then
            gpu.setBackground(T.surface); gpu.setForeground(T.danger)
            gpu.set(cx, cy, UI.truncate("[ERR] "..tostring(err), cw))
        end
    end
end

-- ============================================================
-- START MENU
-- ============================================================
local START_MENU_TILES = {
    {label=Lang.t("app.computer"),   icon="[PC]", color=T.tileBlue,   action="mycomputer"},
    {label=Lang.t("app.explorer"),   icon="[F]",  color=T.tileOrange, action="explorer"},
    {label=Lang.t("app.terminal"),   icon="[>_]", color=T.tileDark,   action="terminal"},
    {label=Lang.t("app.calculator"), icon="[=]",  color=T.tileCyan,   action="calculator"},
    {label=Lang.t("app.notepad"),    icon="[N]",  color=0x1565C0,     action="notepad"},
    {label="Browser",                icon="[W]",  color=0x00695C,     action="browser"},
    {label=Lang.t("app.settings"),   icon="[S]",  color=T.tileGray,   action="settings"},
    {label=Lang.t("app.update"),     icon="[U]",  color=T.tileGreen,  action="update"},
}

local _menuHits = {}
local MENU_W    = 2 + (UI.TILE_W + UI.TILE_GAP) * 2 - UI.TILE_GAP + 2
local MENU_H    = 3 + (UI.TILE_H + UI.TILE_GAP) * 4 - UI.TILE_GAP + 4

local function drawStartMenu()
    local mx, my = 1, H - MENU_H - 1
    gpu.setBackground(T.chromeDark)
    gpu.fill(mx, my, MENU_W, MENU_H, " ")

    -- User bar
    gpu.setBackground(T.accent)
    gpu.fill(mx, my, MENU_W, 2, " ")
    gpu.setForeground(T.textOnAccent)
    gpu.set(mx+2, my,   "[*] FixOS 4.0.0")
    gpu.set(mx+2, my+1, "    " .. Lang.t("desktop.user"))

    gpu.setBackground(T.chromeDark)
    gpu.setForeground(T.textSecondary)
    gpu.set(mx+2, my+3, Lang.t("desktop.apps"))

    _menuHits = UI.drawStartMenuGrid(mx+2, my+4, START_MENU_TILES)

    -- Shutdown button
    local powerY = my + MENU_H - 2
    gpu.setBackground(T.danger); gpu.fill(mx, powerY, MENU_W, 2, " ")
    UI.centerText(mx, powerY+1, MENU_W, "[X] "..Lang.t("desktop.shutdown"), T.textOnAccent, T.danger)
    table.insert(_menuHits, {x=mx, y=powerY, w=MENU_W, h=2, action="shutdown"})
end

-- ============================================================
-- WINDOW MANAGEMENT
-- ============================================================
local function redrawAll()
    drawDesktop()
    for i, win in ipairs(state.windows) do
        drawWindow(win, i == state.focused)
    end
    drawTaskbar()
    if state.startOpen then drawStartMenu() end
end

local function createWindow(prog, initData)
    local sz  = WIN_SIZES[prog] or {56, 20}
    local off = #state.windows * 2
    local wx  = math.max(0, math.min(math.floor((W-sz[1])/2)+off, W-sz[1]))
    local wy  = math.max(1, math.min(math.floor((H-sz[2])/2)+off, H-2-sz[2]))
    local mod = loadProgram(prog)
    if not mod then return nil end
    local win = {
        title     = prog:sub(1,1):upper()..prog:sub(2),
        x=wx, y=wy, w=sz[1], h=sz[2],
        program   = mod,
        minimized = false,
        maximized = false,
        initData  = initData,
    }
    if mod.init then safeCall(mod.init, win, initData) end
    table.insert(state.windows, win)
    state.focused = #state.windows
    return win
end

local function closeWindow(idx)
    if not state.windows[idx] then return end
    table.remove(state.windows, idx)
    if #state.windows > 0 then
        state.focused = math.min(idx, #state.windows)
    else
        state.focused = nil
    end
end

local function focusWindow(idx)
    if not state.windows[idx] then return end
    local win = table.remove(state.windows, idx)
    table.insert(state.windows, win)
    state.focused = #state.windows
end

local function minimizeWindow(idx)
    if state.windows[idx] then state.windows[idx].minimized = true end
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
        win.x, win.y = win._sx or 2, win._sy or 2
        win.w, win.h = win._sw or 60, win._sh or 20
        win.maximized = false
    else
        win._sx,win._sy = win.x, win.y
        win._sw,win._sh = win.w, win.h
        win.x, win.y   = 0, 1
        win.w, win.h   = W, H-1
        win.maximized  = true
    end
end

local function iconAt(mx, my)
    for i, ic in ipairs(ICONS) do
        if mx>=ic.x and mx<ic.x+ICON_W and my>=ic.y and my<ic.y+ICON_H then
            return i
        end
    end
end

local function windowAt(mx, my)
    for i = #state.windows, 1, -1 do
        local w = state.windows[i]
        if not w.minimized and mx>=w.x and mx<w.x+w.w and my>=w.y and my<w.y+w.h then
            return i, w
        end
    end
end

local function taskbarPillAt(mx, my)
    if my ~= H then return nil end
    local sl  = " \xE2\x8A\x9E " .. Lang.t("desktop.start") .. " "
    local sw  = math.max(8, #sl+2) + 2
    local px  = sw
    for i, _ in ipairs(state.windows) do
        if mx >= px and mx < px + 15 then return i end
        px = px + 16
    end
end

local function handleMenuAction(action)
    state.startOpen = false
    if action == "shutdown" then
        gpu.setBackground(T.chromeDark); gpu.fill(1,1,W,H," ")
        UI.centerText(1,math.floor(H/2)-1,W,"FixOS 4.0.0",T.accent,T.chromeDark)
        UI.centerText(1,math.floor(H/2)+1,W,Lang.t("desktop.shutdown").."...",T.textSecondary,T.chromeDark)
        os.sleep(0.8); computer.shutdown()
    elseif action == "update" then
        createWindow("settings")
        if state.windows[#state.windows] then state.windows[#state.windows].selectedTab = 4 end
    elseif action then
        createWindow(action)
    end
    redrawAll()
end

local function tickClock()
    local now = computer.uptime()
    if now - state.clockTick < 28 then return end
    state.clockTick = now
    local clk = os.date("%H:%M")
    gpu.setBackground(T.chromeDark); gpu.setForeground(T.textOnDark)
    gpu.set(W-#clk-2, H, clk)
end

_G.createWindow = createWindow

-- ============================================================
-- MAIN LOOP
-- ============================================================
local function main()
    redrawAll()

    while state.running do
        local ev = {computer.pullSignal(0.02)}
        local t  = ev[1]
        tickClock()

        -- Tick all windows
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

        -- ── TOUCH ──────────────────────────────────────────
        if t == "touch" then
            local _,_,mx,my,btn = table.unpack(ev)

            if state.startOpen then
                local hit = false
                for _, h in ipairs(_menuHits) do
                    if UI.hitTest(h,mx,my) then
                        handleMenuAction(h.action); hit=true; break
                    end
                end
                if not hit then state.startOpen=false; redrawAll() end

            elseif my == H then
                local sl  = " \xE2\x8A\x9E " .. Lang.t("desktop.start") .. " "
                local sw  = math.max(8, #sl+2)
                if mx >= 1 and mx <= sw then
                    state.startOpen = not state.startOpen; redrawAll()
                else
                    local pill = taskbarPillAt(mx, my)
                    if pill then
                        if state.windows[pill] and state.windows[pill].minimized then
                            restoreWindow(pill)
                        else
                            focusWindow(pill)
                        end
                        redrawAll()
                    end
                end

            else
                local wi, win = windowAt(mx, my)
                if wi then
                    focusWindow(wi); win = state.windows[state.focused]

                    if my == win.y then
                        -- Title bar actions
                        if mx >= win.x+win.w-3 then
                            closeWindow(state.focused); redrawAll()
                        elseif mx >= win.x+win.w-7 and mx < win.x+win.w-4 then
                            maximizeWindow(state.focused); redrawAll()
                        elseif mx >= win.x+win.w-10 and mx < win.x+win.w-8 then
                            minimizeWindow(state.focused); redrawAll()
                        else
                            state.drag=win; state.dragOX=mx-win.x; state.dragOY=my-win.y
                        end
                    else
                        local ok,nr = safeCall(win.program and win.program.click,win,mx,my,btn)
                        if nr then redrawAll() end
                    end
                else
                    local ii = iconAt(mx, my)
                    if ii then
                        if state.selIcon == ii then
                            createWindow(ICONS[ii].prog); state.selIcon=nil
                        else
                            state.selIcon = ii
                        end
                        redrawAll()
                    else
                        if state.selIcon then state.selIcon=nil; redrawAll() end
                    end
                end
            end

        -- ── DRAG ───────────────────────────────────────────
        elseif t == "drag" and state.drag then
            local _,_,mx,my = table.unpack(ev)
            local win = state.drag
            if not win.maximized then
                win.x = math.max(0, math.min(W-win.w, mx-state.dragOX))
                win.y = math.max(1, math.min(H-2-win.h, my-state.dragOY))
                redrawAll()
            end

        -- ── DROP ───────────────────────────────────────────
        elseif t == "drop" then
            state.drag = nil

        -- ── SCROLL ─────────────────────────────────────────
        elseif t == "scroll" then
            local _,_,mx,my,dir = table.unpack(ev)
            if state.focused and state.windows[state.focused] then
                local win = state.windows[state.focused]
                if not win.minimized and mx>=win.x and mx<win.x+win.w and my>=win.y and my<win.y+win.h then
                    local ok,nr = safeCall(win.program and win.program.scroll,win,dir)
                    if nr then redrawAll() end
                end
            end

        -- ── KEY ────────────────────────────────────────────
        elseif t == "key_down" then
            local _,_,char,code = table.unpack(ev)

            -- Alt+F4 = close focused window
            -- code 62 = F4, but in OC Alt modifier is separate
            -- We handle ESC (code 1) to close when no program handles it
            if state.focused and state.windows[state.focused] then
                local win = state.windows[state.focused]
                local ok,nr = safeCall(win.program and win.program.key,win,char,code)
                if nr then redrawAll() end
            end
        end
    end
end

local ok, err = pcall(main)
if not ok then
    gpu.setBackground(T.danger); gpu.setForeground(T.textOnAccent)
    gpu.fill(1,1,W,H," ")
    gpu.set(2,2,"FixOS 4.0.0 - Desktop Error:")
    gpu.set(2,3,UI.truncate(tostring(err), W-4))
    gpu.set(2,5,"Press any key to reboot")
    computer.pullSignal(); computer.shutdown(true)
end