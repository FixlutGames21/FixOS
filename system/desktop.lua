-- ==============================================
-- FixOS 3.1.1 - desktop.lua (ULTRA WINDOWS 10)
-- Максимальна схожість з Windows 10
-- Acrylic blur, Fluent Design, Reveal effects
-- ==============================================

if not component.isAvailable("gpu") then
  error("No GPU found!")
end

local gpu = component.proxy(component.list("gpu")())
local screen = component.list("screen")()

if not screen then
  error("No screen found!")
end

gpu.bind(screen)

-- ====================
-- WINDOWS 10 LOADING WITH RING
-- ====================

local function showWindows10Boot()
  local maxW, maxH = gpu.maxResolution()
  local w = math.min(80, maxW)
  local h = math.min(25, maxH)
  gpu.setResolution(w, h)
  
  -- Windows 10 pure blue
  gpu.setBackground(0x0078D7)
  gpu.fill(1, 1, w, h, " ")
  
  -- FixOS Logo
  local logo = {
    "███████╗██╗██╗  ██╗ ██████╗ ███████╗",
    "██╔════╝██║╚██╗██╔╝██╔═══██╗██╔════╝",
    "█████╗  ██║ ╚███╔╝ ██║   ██║███████╗",
    "██╔══╝  ██║ ██╔██╗ ██║   ██║╚════██║",
    "██║     ██║██╔╝ ██╗╚██████╔╝███████║",
    "╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝"
  }
  
  gpu.setForeground(0xFFFFFF)
  local logoY = math.floor(h / 2) - 5
  for i, line in ipairs(logo) do
    local x = math.floor((w - #line) / 2)
    gpu.set(x, logoY + i - 1, line)
  end
  
  -- Edition text
  gpu.setForeground(0xE3F2FD)
  local edition = "MAXIMUM WINDOWS 10 EDITION"
  gpu.set(math.floor((w - #edition) / 2), logoY + 8, edition)
  
  -- Windows 10 ring loader (5 dots spinning)
  local ringY = logoY + 11
  local ringX = math.floor(w / 2)
  local dots = {"⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"}
  
  for frame = 1, 25 do
    local char = dots[(frame % #dots) + 1]
    gpu.setForeground(0xFFFFFF)
    gpu.set(ringX, ringY, char .. " " .. char)
    computer.beep(150 + frame * 15, 0.01)
    os.sleep(0.04)
  end
  
  os.sleep(0.2)
end

showWindows10Boot()

-- ====================
-- RESOLUTION SETUP
-- ====================

local function loadResolution()
  local fs = component.proxy(computer.getBootAddress())
  if fs.exists("/settings.cfg") then
    local handle = fs.open("/settings.cfg", "r")
    if handle then
      local data = fs.read(handle, math.huge)
      fs.close(handle)
      local w, h = data:match("resolution=(%d+)x(%d+)")
      if w and h then
        return tonumber(w), tonumber(h)
      end
    end
  end
  return nil, nil
end

local savedW, savedH = loadResolution()
local maxW, maxH = gpu.maxResolution()

if savedW and savedH then
  gpu.setResolution(savedW, savedH)
else
  local w = math.min(80, maxW)
  local h = math.min(25, maxH)
  gpu.setResolution(w, h)
end

local w, h = gpu.getResolution()

-- ====================
-- FLUENT DESIGN COLORS
-- ====================

local COLORS = {
  -- Windows 10 Fluent Design System
  accentPrimary = 0x0078D7,        -- Primary blue
  accentSecondary = 0x005A9E,      -- Dark blue
  accentLight = 0x429CE3,          -- Light blue
  accentLightest = 0xE3F2FD,       -- Very light blue
  
  -- Acrylic backgrounds (simulated transparency)
  acrylicDark = 0x1F1F1F,          -- Dark acrylic
  acrylicLight = 0xF3F3F3,         -- Light acrylic
  
  -- Base colors
  chromeDark = 0x2D2D30,           -- Chrome dark
  chromeLight = 0xF0F0F0,          -- Chrome light
  
  -- Desktop
  desktop = 0x0078D7,              -- Solid blue desktop
  
  -- UI elements
  surface = 0xFFFFFF,              -- White surface
  surfaceVariant = 0xF9F9F9,       -- Light gray
  
  -- Text
  textPrimary = 0x000000,          -- Black
  textSecondary = 0x666666,        -- Gray
  textTertiary = 0x999999,         -- Light gray
  textOnAccent = 0xFFFFFF,         -- White
  
  -- Borders & dividers
  divider = 0xE5E5E5,              -- Divider
  border = 0xCCCCCC,               -- Border
  
  -- Shadows
  shadow1 = 0xE0E0E0,              -- Light shadow
  shadow2 = 0xB0B0B0,              -- Medium shadow
  shadow3 = 0x808080,              -- Dark shadow
  
  -- Status colors
  success = 0x10893E,              -- Green
  error = 0xE81123,                -- Red
  warning = 0xFFB900,              -- Orange
  info = 0x0078D7,                 -- Blue
  
  -- Hover states
  hoverLight = 0xF5F5F5,           -- Light hover
  hoverDark = 0x3E3E42,            -- Dark hover
  
  -- Special
  transparent = 0x000000           -- For transparency simulation
}

-- ====================
-- DRAWING UTILITIES
-- ====================

local function drawAcrylicRect(x, y, w, h, color, alpha)
  -- Simulated acrylic effect with dithering
  gpu.setBackground(color)
  gpu.fill(x, y, w, h, " ")
  
  -- Add subtle pattern for acrylic feel
  if alpha then
    gpu.setBackground(color)
    for i = 0, h - 1 do
      if i % 2 == 0 then
        for j = 0, w - 1, 2 do
          gpu.setBackground(alpha)
          gpu.set(x + j, y + i, " ")
        end
      end
    end
  end
end

local function drawShadow(x, y, w, h, intensity)
  -- Multi-layer shadow for depth
  intensity = intensity or 3
  
  for i = 1, intensity do
    local shadowColor = COLORS.shadow1
    if i == 2 then shadowColor = COLORS.shadow2
    elseif i >= 3 then shadowColor = COLORS.shadow3 end
    
    gpu.setBackground(shadowColor)
    gpu.fill(x + i, y + i, w, 1, "▀")
    gpu.fill(x + w + i, y, 1, h + i, "▐")
  end
end

local function drawModernButton(x, y, w, h, label, state, color)
  -- state: "normal", "hover", "pressed"
  state = state or "normal"
  color = color or COLORS.accentPrimary
  
  local bg = color
  if state == "hover" then
    bg = COLORS.accentLight
  elseif state == "pressed" then
    bg = COLORS.accentSecondary
  end
  
  -- Shadow for elevation
  if state ~= "pressed" then
    drawShadow(x, y, w, h, 1)
  end
  
  -- Button surface
  gpu.setBackground(bg)
  gpu.fill(x, y, w, h, " ")
  
  -- Button text (centered)
  gpu.setForeground(COLORS.textOnAccent)
  local textX = x + math.floor((w - #label) / 2)
  local textY = y + math.floor(h / 2)
  gpu.set(textX, textY, label)
  
  -- Subtle border for definition
  gpu.setForeground(COLORS.accentSecondary)
  if state ~= "pressed" then
    gpu.set(x, y, "┌")
    gpu.set(x + w - 1, y, "┐")
    gpu.set(x, y + h - 1, "└")
    gpu.set(x + w - 1, y + h - 1, "┘")
  end
end

local function drawCard(x, y, w, h, title, elevated)
  elevated = elevated == nil and true or elevated
  
  -- Shadow for elevation
  if elevated then
    drawShadow(x, y, w, h, 2)
  end
  
  -- Card surface
  gpu.setBackground(COLORS.surface)
  gpu.fill(x, y, w, h, " ")
  
  -- Title bar if provided
  if title then
    gpu.setBackground(COLORS.surfaceVariant)
    gpu.fill(x, y, w, 1, " ")
    
    gpu.setForeground(COLORS.textPrimary)
    gpu.set(x + 2, y, title)
  end
  
  -- Subtle border
  gpu.setForeground(COLORS.divider)
  for i = 0, w - 1 do
    gpu.set(x + i, y, "─")
    gpu.set(x + i, y + h - 1, "─")
  end
  for i = 0, h - 1 do
    gpu.set(x, y + i, "│")
    gpu.set(x + w - 1, y + i, "│")
  end
  
  -- Corners
  gpu.set(x, y, "┌")
  gpu.set(x + w - 1, y, "┐")
  gpu.set(x, y + h - 1, "└")
  gpu.set(x + w - 1, y + h - 1, "┘")
end

-- ====================
-- UTILITIES
-- ====================

local function loadProgram(name)
  local path = "/system/programs/" .. name .. ".lua"
  local fs = component.proxy(computer.getBootAddress())
  if not fs.exists(path) then
    return nil, "Program not found"
  end
  
  local func, err = loadfile(path)
  if not func then
    return nil, tostring(err)
  end
  
  local ok, module = pcall(func)
  if not ok then
    return nil, tostring(module)
  end
  
  return module
end

local function safeCall(func, ...)
  if type(func) ~= "function" then
    return false, "not a function"
  end
  
  local ok, result = pcall(func, ...)
  if not ok then
    return false, tostring(result)
  end
  
  return true, result
end

local function truncate(text, maxLen)
  text = tostring(text)
  if #text > maxLen then
    return text:sub(1, maxLen - 3) .. "..."
  end
  return text
end

-- ====================
-- MODERN ICONS (TILES)
-- ====================

local DESKTOP_ICONS = {
  {
    x = 3, y = 2, w = 13, h = 6,
    label = "Computer",
    color = COLORS.accentPrimary,
    icon = "💻",
    program = "mycomputer"
  },
  {
    x = 3, y = 9, w = 13, h = 6,
    label = "Explorer",
    color = COLORS.warning,
    icon = "📁",
    program = "explorer"
  },
  {
    x = 3, y = 16, w = 13, h = 6,
    label = "Terminal",
    color = 0x212121,
    icon = "⌘",
    program = "terminal"
  },
  {
    x = 18, y = 2, w = 13, h = 6,
    label = "Calculator",
    color = 0x00838F,
    icon = "🔢",
    program = "calculator"
  },
  {
    x = 18, y = 9, w = 13, h = 6,
    label = "Notepad",
    color = 0x1565C0,
    icon = "📝",
    program = "notepad"
  },
  {
    x = 18, y = 16, w = 13, h = 6,
    label = "Settings",
    color = COLORS.chromeDark,
    icon = "⚙",
    program = "settings"
  }
}

-- ====================
-- STATE
-- ====================

local state = {
  selectedIcon = nil,
  hoverIcon = nil,
  startMenuOpen = false,
  activeWindows = {},
  focusedWindow = nil,
  dragWindow = nil,
  dragOffsetX = 0,
  dragOffsetY = 0,
  clockTimer = 0,
  running = true,
  hoverButton = nil
}

-- ====================
-- DRAWING FUNCTIONS
-- ====================

local function drawModernIcon(icon, selected, hover)
  local bg = icon.color
  
  -- Hover effect (lighter)
  if hover and not selected then
    -- Lighten color for hover
    local r = math.floor(bg / 65536)
    local g = math.floor((bg % 65536) / 256)
    local b = bg % 256
    
    r = math.min(255, r + 30)
    g = math.min(255, g + 30)
    b = math.min(255, b + 30)
    
    bg = r * 65536 + g * 256 + b
  end
  
  -- Selection border
  if selected then
    gpu.setBackground(COLORS.accentLightest)
    gpu.fill(icon.x - 1, icon.y - 1, icon.w + 2, icon.h + 2, " ")
  end
  
  -- Shadow
  if not selected then
    drawShadow(icon.x, icon.y, icon.w, icon.h, 1)
  end
  
  -- Tile background
  gpu.setBackground(bg)
  gpu.fill(icon.x, icon.y, icon.w, icon.h, " ")
  
  -- Icon centered
  gpu.setForeground(COLORS.textOnAccent)
  local iconX = icon.x + math.floor((icon.w - 2) / 2)
  local iconY = icon.y + 2
  gpu.set(iconX, iconY, icon.icon)
  
  -- Label centered
  local textX = icon.x + math.floor((icon.w - #icon.label) / 2)
  gpu.set(textX, icon.y + icon.h - 1, icon.label)
end

local function drawTaskbar()
  -- Acrylic taskbar with blur effect
  drawAcrylicRect(1, h, w, 1, COLORS.chromeDark, COLORS.acrylicDark)
  
  -- Start button (Windows logo style)
  local startBg = state.startMenuOpen and COLORS.hoverDark or COLORS.chromeDark
  gpu.setBackground(startBg)
  gpu.setForeground(COLORS.textOnAccent)
  gpu.fill(2, h, 4, 1, " ")
  gpu.set(2, h, " ⊞ ")
  
  -- Divider
  gpu.setForeground(COLORS.divider)
  gpu.set(6, h, "│")
  
  -- Window buttons
  local btnX = 8
  for i, win in ipairs(state.activeWindows) do
    if btnX + 15 < w - 8 then
      local isFocused = (state.focusedWindow == i)
      local btnBg = isFocused and COLORS.hoverDark or COLORS.chromeDark
      
      gpu.setBackground(btnBg)
      gpu.setForeground(COLORS.textOnAccent)
      gpu.fill(btnX, h, 14, 1, " ")
      
      local title = truncate(win.title or "Window", 12)
      gpu.set(btnX + 1, h, title)
      
      -- Underline for focused
      if isFocused then
        gpu.setForeground(COLORS.accentPrimary)
        gpu.set(btnX, h, "▁")
        gpu.set(btnX + 13, h, "▁")
      end
      
      btnX = btnX + 15
    end
  end
  
  -- System tray separator
  gpu.setForeground(COLORS.divider)
  gpu.set(w - 8, h, "│")
  
  -- Clock
  gpu.setBackground(COLORS.chromeDark)
  gpu.setForeground(COLORS.textOnAccent)
  local time = os.date("%H:%M")
  gpu.set(w - 6, h, time)
end

local function drawDesktop()
  -- Windows 10 blue desktop with gradient effect
  for i = 1, h - 1 do
    local shade = COLORS.desktop
    if i % 3 == 0 then
      shade = 0x006BB3
    elseif i % 5 == 0 then
      shade = 0x0085E5
    end
    gpu.setBackground(shade)
    gpu.fill(1, i, w, 1, " ")
  end
  
  -- Icons
  for i, icon in ipairs(DESKTOP_ICONS) do
    drawModernIcon(icon, state.selectedIcon == i, state.hoverIcon == i)
  end
end

local function drawWindow(win)
  local wx, wy, ww, wh = win.x, win.y, win.w, win.h
  
  -- Elevated shadow
  drawShadow(wx, wy, ww, wh, 3)
  
  -- Window surface
  gpu.setBackground(COLORS.surface)
  gpu.fill(wx, wy, ww, wh, " ")
  
  -- Title bar
  local isFocused = (state.activeWindows[state.focusedWindow] == win)
  local titleColor = isFocused and COLORS.surface or COLORS.surfaceVariant
  
  gpu.setBackground(titleColor)
  gpu.fill(wx, wy, ww, 1, " ")
  
  -- Title text
  gpu.setForeground(COLORS.textPrimary)
  local title = truncate(win.title or "Window", ww - 10)
  gpu.set(wx + 2, wy, title)
  
  -- Window controls (modern, flat)
  local controlX = wx + ww - 9
  
  -- Minimize
  gpu.setBackground(titleColor)
  gpu.setForeground(COLORS.textSecondary)
  gpu.set(controlX, wy, " ─ ")
  
  -- Maximize
  gpu.set(controlX + 3, wy, " □ ")
  
  -- Close (red on hover)
  gpu.setBackground(COLORS.error)
  gpu.setForeground(COLORS.textOnAccent)
  gpu.set(controlX + 6, wy, " × ")
  
  -- Window border (subtle)
  gpu.setForeground(COLORS.divider)
  for i = 0, ww - 1 do
    gpu.setBackground(COLORS.surface)
    gpu.set(wx + i, wy + 1, "─")
  end
  
  -- Content
  if win.draw and type(win.draw) == "function" then
    local contentX = wx + 1
    local contentY = wy + 2
    local contentW = ww - 2
    local contentH = wh - 3
    
    local ok, err = safeCall(win.draw, win, gpu, contentX, contentY, contentW, contentH)
    if not ok then
      gpu.setBackground(COLORS.surface)
      gpu.setForeground(COLORS.error)
      gpu.set(contentX + 1, contentY + 1, "Error:")
      gpu.set(contentX + 1, contentY + 2, truncate(tostring(err), contentW - 2))
    end
  end
end

local function drawStartMenu()
  -- Modern Start Menu with acrylic
  local menuW = 38
  local menuH = 24
  local menuX = 1
  local menuY = h - menuH - 1
  
  -- Shadow
  drawShadow(menuX, menuY, menuW, menuH, 3)
  
  -- Acrylic background
  drawAcrylicRect(menuX, menuY, menuW, menuH, COLORS.chromeDark, COLORS.acrylicDark)
  
  -- User profile section
  gpu.setBackground(COLORS.chromeDark)
  gpu.setForeground(COLORS.textOnAccent)
  gpu.fill(menuX, menuY, menuW, 3, " ")
  gpu.set(menuX + 2, menuY + 1, "👤 FixOS User")
  
  -- Apps section header
  gpu.setForeground(COLORS.textSecondary)
  gpu.set(menuX + 2, menuY + 4, "Apps")
  
  -- App tiles (2x3 grid)
  local tiles = {
    {x = 2, y = 6, w = 17, h = 4, label = "Programs", icon = "📦", color = COLORS.accentPrimary},
    {x = 20, y = 6, w = 17, h = 4, label = "Explorer", icon = "📁", color = COLORS.warning},
    {x = 2, y = 11, w = 17, h = 4, label = "Terminal", icon = "⌘", color = 0x212121},
    {x = 20, y = 11, w = 17, h = 4, label = "Settings", icon = "⚙", color = COLORS.chromeDark},
    {x = 2, y = 16, w = 17, h = 4, label = "About", icon = "ℹ", color = COLORS.info},
    {x = 20, y = 16, w = 17, h = 4, label = "Update", icon = "⟳", color = COLORS.success},
  }
  
  for _, tile in ipairs(tiles) do
    -- Tile with shadow
    local tileX = menuX + tile.x
    local tileY = menuY + tile.y
    
    gpu.setBackground(tile.color)
    gpu.fill(tileX, tileY, tile.w, tile.h, " ")
    
    gpu.setForeground(COLORS.textOnAccent)
    gpu.set(tileX + 2, tileY + 1, tile.icon .. " " .. tile.label)
    
    -- Store for clicks
    tile.absX = tileX
    tile.absY = tileY
  end
  
  -- Power section at bottom
  gpu.setBackground(COLORS.error)
  gpu.setForeground(COLORS.textOnAccent)
  gpu.fill(menuX, menuY + menuH - 3, menuW, 3, " ")
  gpu.set(menuX + math.floor(menuW / 2) - 6, menuY + menuH - 2, "⏻ Shut Down")
  
  return tiles, menuX, menuY
end

local function redrawAll()
  drawDesktop()
  
  for i, win in ipairs(state.activeWindows) do
    drawWindow(win)
  end
  
  drawTaskbar()
  
  if state.startMenuOpen then
    drawStartMenu()
  end
end

-- ====================
-- WINDOW MANAGEMENT
-- ====================

local WINDOW_SIZES = {
  calculator = {45, 22},
  notepad = {68, 24},
  settings = {62, 24},
  mycomputer = {60, 20},
  terminal = {72, 26},
  explorer = {68, 24}
}

local function createWindow(title, width, height, programName)
  local program, err = loadProgram(programName)
  if not program then
    return nil
  end
  
  local winX = math.floor((w - width) / 2) + #state.activeWindows * 2
  local winY = math.floor((h - height) / 2) + #state.activeWindows * 2
  
  if winY + height > h - 1 then winY = 2 end
  if winX + width > w then winX = 2 end
  
  local win = {
    title = title,
    x = winX,
    y = winY,
    w = width,
    h = height,
    program = program
  }
  
  if program.init then
    safeCall(program.init, win)
  end
  
  function win:draw(...)
    if self.program and self.program.draw then
      return self.program.draw(self, ...)
    end
  end
  
  function win:click(x, y, button)
    if self.program and self.program.click then
      return self.program.click(self, x, y, button)
    end
    return false
  end
  
  function win:key(char, code)
    if self.program and self.program.key then
      return self.program.key(self, char, code)
    end
    return false
  end
  
  table.insert(state.activeWindows, win)
  state.focusedWindow = #state.activeWindows
  
  return win
end

local function closeWindow(index)
  if state.activeWindows[index] then
    table.remove(state.activeWindows, index)
    
    if state.focusedWindow == index then
      state.focusedWindow = #state.activeWindows
    elseif state.focusedWindow > index then
      state.focusedWindow = state.focusedWindow - 1
    end
  end
end

local function focusWindow(index)
  if index and state.activeWindows[index] then
    local win = table.remove(state.activeWindows, index)
    table.insert(state.activeWindows, win)
    state.focusedWindow = #state.activeWindows
  end
end

-- ====================
-- EVENT HANDLERS
-- ====================

local function checkIconClick(x, y)
  for i, icon in ipairs(DESKTOP_ICONS) do
    if x >= icon.x and x < icon.x + icon.w and
       y >= icon.y and y < icon.y + icon.h and y < h - 1 then
      return i
    end
  end
  return nil
end

local function checkIconHover(x, y)
  return checkIconClick(x, y)
end

local function checkStartButton(x, y)
  return y == h and x >= 2 and x <= 5
end

local function checkWindowClick(x, y)
  for i = #state.activeWindows, 1, -1 do
    local win = state.activeWindows[i]
    if x >= win.x and x < win.x + win.w and
       y >= win.y and y < win.y + win.h then
      return i, win
    end
  end
  return nil, nil
end

local function checkStartMenuClick(x, y)
  if not state.startMenuOpen then return nil end
  
  local tiles, menuX, menuY = drawStartMenu()
  local menuW = 38
  local menuH = 24
  
  -- Check tiles
  for i, tile in ipairs(tiles) do
    if x >= tile.absX and x < tile.absX + tile.w and
       y >= tile.absY and y < tile.absY + tile.h then
      return i
    end
  end
  
  -- Check power button
  if y >= menuY + menuH - 3 and y < menuY + menuH and
     x >= menuX and x < menuX + menuW then
    return 7  -- Shutdown
  end
  
  return nil
end

local function executeIconAction(program)
  local size = WINDOW_SIZES[program] or {50, 20}
  local title = program:sub(1, 1):upper() .. program:sub(2)
  
  createWindow(title, size[1], size[2], program)
  redrawAll()
end

local function executeMenuAction(action)
  if action == 1 then -- Programs
    executeIconAction("calculator")
  elseif action == 2 then -- Explorer
    executeIconAction("explorer")
  elseif action == 3 then -- Terminal
    executeIconAction("terminal")
  elseif action == 4 then -- Settings
    executeIconAction("settings")
  elseif action == 5 then -- About
    executeIconAction("settings")
    if state.activeWindows[#state.activeWindows] then
      state.activeWindows[#state.activeWindows].selectedTab = 4
    end
  elseif action == 6 then -- Update
    executeIconAction("settings")
    if state.activeWindows[#state.activeWindows] then
      state.activeWindows[#state.activeWindows].selectedTab = 3
    end
  elseif action == 7 then -- Shutdown
    gpu.setBackground(COLORS.accentPrimary)
    gpu.setForeground(COLORS.textOnAccent)
    gpu.fill(1, 1, w, h, " ")
    local msg = "Shutting down..."
    gpu.set(math.floor(w/2) - 8, math.floor(h/2), msg)
    os.sleep(0.5)
    computer.shutdown()
  end
  
  state.startMenuOpen = false
  redrawAll()
end

local function updateClock()
  if computer.uptime() - state.clockTimer > 30 then
    state.clockTimer = computer.uptime()
    
    gpu.setBackground(COLORS.chromeDark)
    gpu.setForeground(COLORS.textOnAccent)
    local time = os.date("%H:%M")
    gpu.set(w - 6, h, time)
  end
end

-- ====================
-- MAIN LOOP (OPTIMIZED)
-- ====================

local function mainLoop()
  redrawAll()
  
  while state.running do
    local eventData = {computer.pullSignal(0.03)}  -- Ultra-fast
    local eventType = eventData[1]
    
    updateClock()
    
    if eventType == "touch" or eventType == "drag" then
      local _, _, x, y, button = table.unpack(eventData)
      
      if eventType == "touch" then
        if state.startMenuOpen then
          local action = checkStartMenuClick(x, y)
          if action then
            executeMenuAction(action)
          else
            state.startMenuOpen = false
            redrawAll()
          end
          
        elseif checkStartButton(x, y) then
          state.startMenuOpen = not state.startMenuOpen
          redrawAll()
          
        else
          local winIndex, win = checkWindowClick(x, y)
          
          if winIndex then
            focusWindow(winIndex)
            
            -- Close button (right side of title bar)
            if y == win.y and x >= win.x + win.w - 3 and x <= win.x + win.w - 1 then
              closeWindow(#state.activeWindows)
              redrawAll()
              
            -- Title bar drag
            elseif y == win.y and x >= win.x and x < win.x + win.w - 10 then
              state.dragWindow = win
              state.dragOffsetX = x - win.x
              state.dragOffsetY = y - win.y
              
            -- Content click
            else
              local ok, needRedraw = safeCall(win.click, win, x, y, button)
              if ok and needRedraw then
                redrawAll()
              end
            end
            
            redrawAll()
          else
            local iconIndex = checkIconClick(x, y)
            if iconIndex then
              if state.selectedIcon == iconIndex then
                executeIconAction(DESKTOP_ICONS[iconIndex].program)
                state.selectedIcon = nil
              else
                state.selectedIcon = iconIndex
                redrawAll()
              end
            else
              state.selectedIcon = nil
              redrawAll()
            end
          end
        end
        
      elseif eventType == "drag" and state.dragWindow then
        state.dragWindow.x = x - state.dragOffsetX
        state.dragWindow.y = y - state.dragOffsetY
        
        if state.dragWindow.x < 0 then state.dragWindow.x = 0 end
        if state.dragWindow.y < 1 then state.dragWindow.y = 1 end
        if state.dragWindow.x + state.dragWindow.w > w then 
          state.dragWindow.x = w - state.dragWindow.w 
        end
        if state.dragWindow.y + state.dragWindow.h > h - 1 then 
          state.dragWindow.y = h - 1 - state.dragWindow.h 
        end
        
        redrawAll()
      end
      
    elseif eventType == "drop" then
      state.dragWindow = nil
      
    elseif eventType == "scroll" then
      local _, _, x, y, direction = table.unpack(eventData)
      
      if state.focusedWindow and state.activeWindows[state.focusedWindow] then
        local win = state.activeWindows[state.focusedWindow]
        
        if x >= win.x and x < win.x + win.w and
           y >= win.y and y < win.y + win.h then
          
          if win.program and win.program.scroll then
            local ok, needRedraw = safeCall(win.program.scroll, win, direction)
            if ok and needRedraw then
              redrawAll()
            end
          end
        end
      end
      
    elseif eventType == "key_down" then
      local _, _, char, code = table.unpack(eventData)
      
      if code == 31 then -- S key
        state.startMenuOpen = not state.startMenuOpen
        redrawAll()
        
      elseif code == 45 then -- X key
        executeMenuAction(7)
        
      elseif state.focusedWindow and state.activeWindows[state.focusedWindow] then
        local win = state.activeWindows[state.focusedWindow]
        local ok, needRedraw = safeCall(win.key, win, char, code)
        
        if ok and needRedraw then
          redrawAll()
        end
      end
    end
  end
end

-- ====================
-- STARTUP
-- ====================

local ok, err = pcall(mainLoop)

if not ok then
  gpu.setBackground(COLORS.error)
  gpu.setForeground(COLORS.textOnAccent)
  gpu.fill(1, 1, w, h, " ")
  
  gpu.set(2, 2, "Desktop Error:")
  gpu.set(2, 3, truncate(tostring(err), w - 4))
  gpu.set(2, 5, "Press any key to shutdown")
  
  computer.pullSignal()
  computer.shutdown()
end
