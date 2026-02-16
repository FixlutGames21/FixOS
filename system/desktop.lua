-- ==============================================
-- FixOS 3.0 - desktop.lua (ПОВНІСТЮ ПЕРЕПИСАНО)
-- Нова архітектура + splash + іконки
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
-- SPLASH SCREEN
-- ====================

local function showSplash()
  local maxW, maxH = gpu.maxResolution()
  local w = math.min(80, maxW)
  local h = math.min(25, maxH)
  gpu.setResolution(w, h)
  
  gpu.setBackground(0x0000AA)
  gpu.fill(1, 1, w, h, " ")
  
  -- Логотип
  gpu.setForeground(0xFFFFFF)
  local logo = {
    "███████╗██╗██╗  ██╗ ██████╗ ███████╗",
    "██╔════╝██║╚██╗██╔╝██╔═══██╗██╔════╝",
    "█████╗  ██║ ╚███╔╝ ██║   ██║███████╗",
    "██╔══╝  ██║ ██╔██╗ ██║   ██║╚════██║",
    "██║     ██║██╔╝ ██╗╚██████╔╝███████║",
    "╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝"
  }
  
  local startY = math.floor(h / 2) - 5
  for i, line in ipairs(logo) do
    local x = math.floor((w - #line) / 2)
    gpu.set(x, startY + i - 1, line)
  end
  
  -- Версія
  gpu.setForeground(0xFFFF00)
  local version = "Version 3.0.0 - SUPER EDITION"
  gpu.set(math.floor((w - #version) / 2), startY + 8, version)
  
  -- Loading bar
  gpu.setForeground(0x00FF00)
  local barW = 40
  local barX = math.floor((w - barW) / 2)
  local barY = startY + 10
  
  gpu.set(barX, barY, "[" .. string.rep(" ", barW - 2) .. "]")
  
  for i = 1, barW - 2 do
    gpu.set(barX + i, barY, "█")
    computer.beep(200 + i * 10, 0.02)
    os.sleep(0.015)
  end
  
  os.sleep(0.3)
end

showSplash()

-- ====================
-- НАЛАШТУВАННЯ ЕКРАНУ
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
-- ЗАВАНТАЖЕННЯ МОДУЛІВ
-- ====================

local icons = dofile("/system/icons.lua")

-- ====================
-- КОЛЬОРИ (ПОКРАЩЕНІ)
-- ====================

local COLORS = {
  desktop = 0x008888,
  taskbar = 0xD3D3D3,
  taskbarDark = 0xA0A0A0,
  startBtn = 0x00CC00,
  startBtnHover = 0x00FF00,
  startBtnText = 0xFFFFFF,
  iconBg = 0x008888,
  iconText = 0xFFFFFF,
  iconSelected = 0x0066CC,
  iconHighlight = 0x00AAFF,
  windowTitle = 0x0000AA,
  windowTitleInactive = 0x808080,
  windowBg = 0xD3D3D3,
  white = 0xFFFFFF,
  black = 0x000000,
  btnHighlight = 0xFFFFFF,
  btnShadow = 0x606060,
  error = 0xFF0000,
  success = 0x00AA00
}

-- ====================
-- УТИЛІТИ
-- ====================

local function loadProgram(name)
  local path = "/system/programs/" .. name .. ".lua"
  local fs = component.proxy(computer.getBootAddress())
  if not fs.exists(path) then
    return nil, "Program not found: " .. name
  end
  
  local func, err = loadfile(path)
  if not func then
    return nil, "Load error: " .. tostring(err)
  end
  
  local ok, module = pcall(func)
  if not ok then
    return nil, "Init error: " .. tostring(module)
  end
  
  if type(module) ~= "table" then
    return nil, "Program must return table"
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
-- ІКОНКИ РОБОЧОГО СТОЛУ
-- ====================

local DESKTOP_ICONS = {
  {
    x = 2, y = 2, w = 14, h = 7,
    label = "My Computer",
    icon = "computer",
    program = "mycomputer"
  },
  {
    x = 2, y = 10, w = 14, h = 7,
    label = "Explorer",
    icon = "folder",
    program = "explorer"
  },
  {
    x = 2, y = 18, w = 14, h = 7,
    label = "Terminal",
    icon = "terminal",
    program = "terminal"
  },
  {
    x = 18, y = 2, w = 14, h = 7,
    label = "Calculator",
    icon = "calculator",
    program = "calculator"
  },
  {
    x = 18, y = 10, w = 14, h = 7,
    label = "Notepad",
    icon = "notepad",
    program = "notepad"
  },
  {
    x = 18, y = 18, w = 14, h = 7,
    label = "Settings",
    icon = "settings",
    program = "settings"
  }
}

-- ====================
-- СТАН СИСТЕМИ
-- ====================

local state = {
  selectedIcon = nil,
  startMenuOpen = false,
  activeWindows = {},
  focusedWindow = nil,
  dragWindow = nil,
  dragOffsetX = 0,
  dragOffsetY = 0,
  clockTimer = 0,
  running = true
}

-- ====================
-- ФУНКЦІЇ МАЛЮВАННЯ
-- ====================

local function draw3DFrame(x, y, w, h, raised)
  local topLeft = raised and COLORS.btnHighlight or COLORS.btnShadow
  local bottomRight = raised and COLORS.btnShadow or COLORS.btnHighlight
  
  gpu.setForeground(topLeft)
  for i = 0, w - 1 do gpu.set(x + i, y, "▀") end
  for i = 0, h - 1 do gpu.set(x, y + i, "▌") end
  
  gpu.setForeground(bottomRight)
  for i = 0, w - 1 do gpu.set(x + i, y + h - 1, "▄") end
  for i = 0, h - 1 do gpu.set(x + w - 1, y + i, "▐") end
end

local function drawIcon(iconData, selected)
  local bg = selected and COLORS.iconSelected or COLORS.iconBg
  
  gpu.setBackground(bg)
  gpu.fill(iconData.x, iconData.y, iconData.w, iconData.h, " ")
  
  -- Рамка при виборі
  if selected then
    gpu.setForeground(COLORS.iconHighlight)
    gpu.set(iconData.x, iconData.y, "┌" .. string.rep("─", iconData.w - 2) .. "┐")
    gpu.set(iconData.x, iconData.y + iconData.h - 1, "└" .. string.rep("─", iconData.w - 2) .. "┘")
    for i = 1, iconData.h - 2 do
      gpu.set(iconData.x, iconData.y + i, "│")
      gpu.set(iconData.x + iconData.w - 1, iconData.y + i, "│")
    end
  end
  
  -- Іконка
  local iconX = iconData.x + math.floor((iconData.w - 8) / 2)
  local iconY = iconData.y + 1
  icons.draw(gpu, iconData.icon, iconX, iconY, 8, 4, COLORS.iconText)
  
  -- Текст
  gpu.setForeground(COLORS.white)
  gpu.setBackground(bg)
  local textX = iconData.x + math.floor((iconData.w - #iconData.label) / 2)
  gpu.set(textX, iconData.y + iconData.h - 1, iconData.label)
  
  gpu.setBackground(COLORS.desktop)
end

local function drawTaskbar()
  -- Основа
  gpu.setBackground(COLORS.taskbar)
  gpu.fill(1, h, w, 1, " ")
  
  -- Верхня підсвітка
  gpu.setForeground(COLORS.btnHighlight)
  for i = 1, w do
    gpu.set(i, h, "▀")
  end
  
  -- Start button
  local startW = 11
  gpu.setBackground(COLORS.startBtn)
  gpu.setForeground(COLORS.startBtnText)
  gpu.fill(2, h, startW, 1, " ")
  gpu.set(3, h, "◢ Start ◣")
  
  gpu.setForeground(COLORS.btnHighlight)
  gpu.set(2, h, "▌")
  gpu.setForeground(COLORS.btnShadow)
  gpu.set(2 + startW - 1, h, "▐")
  
  -- Розділювач
  gpu.setBackground(COLORS.taskbar)
  gpu.setForeground(COLORS.btnShadow)
  gpu.set(14, h, "┃")
  
  -- Кнопки вікон
  local btnX = 16
  for i, win in ipairs(state.activeWindows) do
    if btnX + 16 < w - 8 then
      local isFocused = (state.focusedWindow == i)
      gpu.setBackground(isFocused and COLORS.taskbarDark or COLORS.taskbar)
      gpu.setForeground(COLORS.black)
      gpu.fill(btnX, h, 15, 1, " ")
      
      local title = truncate(win.title or "Window", 13)
      gpu.set(btnX + 1, h, title)
      
      gpu.setForeground(isFocused and COLORS.btnShadow or COLORS.btnHighlight)
      gpu.set(btnX, h, "▌")
      gpu.set(btnX + 14, h, "▐")
      
      btnX = btnX + 16
    end
  end
  
  -- Годинник
  gpu.setBackground(COLORS.taskbar)
  gpu.setForeground(COLORS.black)
  local time = os.date("%H:%M")
  gpu.fill(w - 8, h, 7, 1, " ")
  gpu.set(w - 7, h, "⏰" .. time)
end

local function drawDesktop()
  -- Фон з градієнтом
  for i = 1, h - 1 do
    local shade = i % 4 == 0 and 0x007777 or COLORS.desktop
    gpu.setBackground(shade)
    gpu.fill(1, i, w, 1, " ")
  end
  
  -- Іконки
  for i, icon in ipairs(DESKTOP_ICONS) do
    drawIcon(icon, state.selectedIcon == i)
  end
end

local function drawWindow(win)
  local wx, wy, ww, wh = win.x, win.y, win.w, win.h
  
  -- Тінь
  gpu.setBackground(0x404040)
  gpu.fill(wx + 2, wy + 2, ww, wh, " ")
  
  -- Фон вікна
  gpu.setBackground(COLORS.windowBg)
  gpu.fill(wx, wy, ww, wh, " ")
  
  -- Заголовок
  local isFocused = (state.activeWindows[state.focusedWindow] == win)
  local titleColor = isFocused and COLORS.windowTitle or COLORS.windowTitleInactive
  
  gpu.setBackground(titleColor)
  gpu.setForeground(COLORS.white)
  gpu.fill(wx, wy, ww, 1, " ")
  
  -- Іконка вікна
  gpu.set(wx + 1, wy, "▣")
  
  -- Заголовок
  local title = truncate(win.title or "Window", ww - 8)
  gpu.set(wx + 3, wy, title)
  
  -- Кнопки управління
  gpu.setBackground(COLORS.btnShadow)
  gpu.setForeground(COLORS.white)
  gpu.set(wx + ww - 7, wy, "─")
  
  gpu.setBackground(COLORS.success)
  gpu.set(wx + ww - 5, wy, "□")
  
  gpu.setBackground(COLORS.error)
  gpu.set(wx + ww - 3, wy, "×")
  
  -- Рамка
  draw3DFrame(wx, wy + 1, ww, wh - 1, true)
  
  -- Контент
  if win.draw and type(win.draw) == "function" then
    local contentX = wx + 1
    local contentY = wy + 2
    local contentW = ww - 2
    local contentH = wh - 3
    
    local ok, err = safeCall(win.draw, win, gpu, contentX, contentY, contentW, contentH)
    if not ok then
      gpu.setBackground(COLORS.windowBg)
      gpu.setForeground(COLORS.error)
      gpu.set(contentX + 1, contentY + 1, "Draw error:")
      gpu.set(contentX + 1, contentY + 2, truncate(tostring(err), contentW - 2))
    end
  end
end

local function drawStartMenu()
  local menuW = 30
  local menuH = 20
  local menuX = 2
  local menuY = h - menuH - 1
  
  -- Тінь
  gpu.setBackground(0x404040)
  gpu.fill(menuX + 2, menuY + 2, menuW, menuH, " ")
  
  -- Фон
  gpu.setBackground(COLORS.windowBg)
  gpu.fill(menuX, menuY, menuW, menuH, " ")
  
  -- Заголовок
  gpu.setBackground(COLORS.windowTitle)
  gpu.setForeground(COLORS.white)
  gpu.fill(menuX, menuY, menuW, 3, " ")
  gpu.set(menuX + 6, menuY + 1, "◢ FixOS 3.0 ◣")
  
  -- Пункти меню
  gpu.setBackground(COLORS.windowBg)
  gpu.setForeground(COLORS.black)
  
  local items = {
    {y = 4, text = " ▸ Programs"},
    {y = 6, text = " ▸ Explorer"},
    {y = 8, text = " ▸ Terminal"},
    {y = 10, text = " ▸ Settings"},
    {y = 12, text = " ℹ About"},
    {y = 15, text = " ⟳ Update"},
    {y = 17, text = " ⏻ Shut Down"}
  }
  
  for _, item in ipairs(items) do
    gpu.set(menuX + 2, menuY + item.y, item.text)
  end
  
  -- Розділювачі
  gpu.setForeground(COLORS.btnShadow)
  gpu.fill(menuX + 1, menuY + 14, menuW - 2, 1, "─")
  
  -- Рамка
  draw3DFrame(menuX, menuY, menuW, menuH, true)
  
  return items, menuX, menuY
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
-- КЕРУВАННЯ ВІКНАМИ
-- ====================

local WINDOW_SIZES = {
  calculator = {42, 24},
  notepad = {65, 22},
  settings = {60, 23},
  mycomputer = {58, 18},
  terminal = {70, 24},
  explorer = {65, 22}
}

local function createWindow(title, width, height, programName)
  local program, err = loadProgram(programName)
  if not program then
    return nil
  end
  
  local winX = math.floor((w - width) / 2) + #state.activeWindows * 2
  local winY = math.floor((h - height) / 2) + #state.activeWindows * 2
  
  if winY + height > h - 1 then winY = 3 end
  if winX + width > w then winX = 3 end
  
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
  
  function win:click(clickX, clickY, button)
    if self.program and self.program.click then
      return self.program.click(self, clickX, clickY, button)
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
-- ОБРОБНИКИ ПОДІЙ
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

local function checkStartButton(x, y)
  return y == h and x >= 2 and x <= 12
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
  
  local items, menuX, menuY = drawStartMenu()
  
  for i, item in ipairs(items) do
    if y == menuY + item.y and x >= menuX and x < menuX + 28 then
      return i
    end
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
    gpu.setBackground(COLORS.black)
    gpu.setForeground(COLORS.white)
    gpu.fill(1, 1, w, h, " ")
    
    local msg = "Shutting down FixOS 3.0..."
    gpu.set(math.floor(w/2) - math.floor(#msg/2), math.floor(h/2), msg)
    os.sleep(0.5)
    computer.shutdown()
  end
  
  state.startMenuOpen = false
  redrawAll()
end

local function updateClock()
  if computer.uptime() - state.clockTimer > 30 then
    state.clockTimer = computer.uptime()
    
    gpu.setBackground(COLORS.taskbar)
    gpu.setForeground(COLORS.black)
    local time = os.date("%H:%M")
    gpu.fill(w - 8, h, 7, 1, " ")
    gpu.set(w - 7, h, "⏰" .. time)
  end
end

-- ====================
-- ГОЛОВНИЙ ЦИКЛ
-- ====================

local function mainLoop()
  redrawAll()
  
  while state.running do
    local eventData = {computer.pullSignal(0.1)}
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
            
            -- Закриття
            if y == win.y and x >= win.x + win.w - 3 and x <= win.x + win.w - 1 then
              closeWindow(#state.activeWindows)
              redrawAll()
              
            -- Перетягування
            elseif y == win.y and x >= win.x and x < win.x + win.w - 8 then
              state.dragWindow = win
              state.dragOffsetX = x - win.x
              state.dragOffsetY = y - win.y
              
            -- Клік по контенту
            else
              local clickX = x
              local clickY = y
              
              local ok, needRedraw = safeCall(win.click, win, clickX, clickY, button)
              if ok and needRedraw then
                redrawAll()
              end
            end
            
            redrawAll()
          else
            -- Клік по іконці
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
      
      if code == 31 then -- 'S' key для Start menu
        state.startMenuOpen = not state.startMenuOpen
        redrawAll()
        
      elseif code == 45 then -- 'X' key для shutdown
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
-- ЗАПУСК
-- ====================

local ok, err = pcall(mainLoop)

if not ok then
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFF0000)
  gpu.fill(1, 1, w, h, " ")
  
  gpu.set(2, 2, "Desktop Error:")
  gpu.set(2, 3, truncate(tostring(err), w - 4))
  gpu.set(2, 5, "Press any key to shutdown")
  
  computer.pullSignal()
  computer.shutdown()
end
