-- ==============================================
-- FixOS 2.0 - system/desktop.lua (ПОКРАЩЕНО)
-- Швидший рендеринг + кращий дизайн
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

-- Завантажуємо налаштування розміру екрану
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
-- ПОКРАЩЕНІ КОЛЬОРИ
-- ====================

local COLORS = {
  desktop = 0x008888,      -- Трошки світліший teal
  taskbar = 0xD3D3D3,      -- Світліший сірий
  taskbarDark = 0x909090,
  startBtn = 0x00CC00,     -- Яскравіший зелений
  startBtnHover = 0x00FF00,
  startBtnText = 0xFFFFFF,
  iconBg = 0x008888,
  iconText = 0xFFFFFF,
  iconSelected = 0x0000CC, -- Яскравіший синій
  windowTitle = 0x0000AA,  -- Насиченіший синій
  windowBg = 0xD3D3D3,
  white = 0xFFFFFF,
  black = 0x000000,
  btnHighlight = 0xFFFFFF,
  btnShadow = 0x707070,
  error = 0xFF0000,
  gray = 0x808080,
  lightBlue = 0xADD8E6
}

-- ====================
-- ОПТИМІЗАЦІЯ: Кешування останнього стану
-- ====================

local lastState = {
  desktop = false,
  taskbar = false,
  windows = {},
  startMenu = false
}

local function needsRedraw(what)
  if what == "all" then return true end
  return not lastState[what]
end

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
    return nil, "Program must return a table/module"
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
-- ПОКРАЩЕНІ ІКОНКИ
-- ====================

local ICONS = {
  {x = 2, y = 2, w = 14, h = 5, label = "My Computer", icon = "╔══╗\n║PC║\n╚══╝", program = "mycomputer"},
  {x = 2, y = 8, w = 14, h = 5, label = "Calculator", icon = "┌──┐\n│═╬│\n└──┘", program = "calculator"},
  {x = 2, y = 14, w = 14, h = 5, label = "Notepad", icon = "┌──┐\n│≡≡│\n└──┘", program = "notepad"},
  {x = 2, y = 20, w = 14, h = 5, label = "Settings", icon = "╔╦╗\n║⚙║\n╚╩╝", program = "settings"}
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
  running = true,
  needsFullRedraw = true
}

-- ====================
-- ПОКРАЩЕНІ ФУНКЦІЇ МАЛЮВАННЯ
-- ====================

local function draw3DFrame(x, y, w, h, raised)
  local topLeft = raised and COLORS.btnHighlight or COLORS.btnShadow
  local bottomRight = raised and COLORS.btnShadow or COLORS.btnHighlight
  
  gpu.setForeground(topLeft)
  gpu.fill(x, y, w, 1, "─")
  gpu.fill(x, y, 1, h, "│")
  
  gpu.setForeground(bottomRight)
  gpu.fill(x, y + h - 1, w, 1, "─")
  gpu.fill(x + w - 1, y, 1, h, "│")
end

local function drawIcon(icon, selected)
  local bg = selected and COLORS.iconSelected or COLORS.iconBg
  
  gpu.setBackground(bg)
  gpu.fill(icon.x, icon.y, icon.w, icon.h, " ")
  
  -- Малюємо іконку (багаторядкову)
  gpu.setForeground(COLORS.iconText)
  local lines = {}
  for line in icon.icon:gmatch("[^\n]+") do
    table.insert(lines, line)
  end
  
  local startY = icon.y + 1
  for i, line in ipairs(lines) do
    local iconX = icon.x + math.floor((icon.w - #line) / 2)
    gpu.set(iconX, startY + i - 1, line)
  end
  
  -- Текст під іконкою
  local textX = icon.x + math.floor((icon.w - #icon.label) / 2)
  gpu.set(textX, icon.y + icon.h - 1, icon.label)
  
  gpu.setBackground(COLORS.desktop)
end

local function drawTaskbar()
  gpu.setBackground(COLORS.taskbar)
  gpu.fill(1, h, w, 1, " ")
  
  -- Верхня підсвітка
  gpu.setForeground(COLORS.btnHighlight)
  gpu.fill(1, h, w, 1, "▀")
  
  -- Кнопка Start (покращена)
  local startW = 11
  gpu.setBackground(COLORS.startBtn)
  gpu.setForeground(COLORS.startBtnText)
  gpu.fill(2, h, startW, 1, " ")
  gpu.set(3, h, "◢ Start ◣")
  
  -- Рамка Start кнопки
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
    if btnX + 15 < w - 8 then
      local isFocused = (state.focusedWindow == i)
      gpu.setBackground(isFocused and COLORS.taskbarDark or COLORS.taskbar)
      gpu.setForeground(COLORS.black)
      gpu.fill(btnX, h, 15, 1, " ")
      
      local title = truncate(win.title or "Window", 13)
      gpu.set(btnX + 1, h, title)
      
      -- Рамка кнопки
      gpu.setForeground(isFocused and COLORS.btnShadow or COLORS.btnHighlight)
      gpu.set(btnX, h, "▌")
      gpu.set(btnX + 14, h, "▐")
      
      btnX = btnX + 16
    end
  end
  
  -- Годинник (покращений)
  gpu.setBackground(COLORS.taskbar)
  gpu.setForeground(COLORS.black)
  local time = os.date("%H:%M")
  gpu.fill(w - 8, h, 7, 1, " ")
  gpu.set(w - 7, h, "⏰" .. time)
  
  lastState.taskbar = true
end

local function drawDesktop()
  -- ВИПРАВЛЕННЯ: Завжди малюємо фон при будь-яких змінах
  gpu.setBackground(COLORS.desktop)
  gpu.fill(1, 1, w, h - 1, " ")
  
  -- Додаємо градієнт-ефект (опціонально)
  for i = 1, h - 1, 2 do
    gpu.setBackground(i % 4 == 0 and 0x007777 or COLORS.desktop)
    gpu.fill(1, i, w, 1, " ")
  end
  
  for i, icon in ipairs(ICONS) do
    drawIcon(icon, state.selectedIcon == i)
  end
  
  lastState.desktop = true
  state.needsFullRedraw = false
end

local function drawWindow(win)
  local wx, wy, ww, wh = win.x, win.y, win.w, win.h
  
  -- Тінь (більш м'яка)
  gpu.setBackground(0x404040)
  gpu.fill(wx + 2, wy + 2, ww, wh, " ")
  
  -- Фон вікна
  gpu.setBackground(COLORS.windowBg)
  gpu.fill(wx, wy, ww, wh, " ")
  
  -- Заголовок (градієнт)
  local isFocused = (state.activeWindows[state.focusedWindow] == win)
  local titleColor = isFocused and COLORS.windowTitle or COLORS.btnShadow
  
  gpu.setBackground(titleColor)
  gpu.setForeground(COLORS.white)
  gpu.fill(wx, wy, ww, 1, " ")
  
  -- Іконка вікна
  gpu.set(wx + 1, wy, "▣")
  
  local title = truncate(win.title or "Window", ww - 8)
  gpu.set(wx + 3, wy, title)
  
  -- Кнопки керування (покращені)
  gpu.setBackground(COLORS.gray)
  gpu.set(wx + ww - 7, wy, "─")
  gpu.setBackground(COLORS.startBtn)
  gpu.set(wx + ww - 5, wy, "□")
  gpu.setBackground(COLORS.error)
  gpu.set(wx + ww - 3, wy, "×")
  
  -- Область контенту
  draw3DFrame(wx, wy + 1, ww, wh - 1, true)
  
  -- Малювання вмісту програми
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
      gpu.set(contentX + 1, contentY + 2, truncate(err, contentW - 2))
    end
  end
end

local function drawStartMenu()
  local menuW = 30
  local menuH = 16
  local menuX = 2
  local menuY = h - menuH - 1
  
  -- Тінь
  gpu.setBackground(0x404040)
  gpu.fill(menuX + 2, menuY + 2, menuW, menuH, " ")
  
  -- Фон меню
  gpu.setBackground(COLORS.windowBg)
  gpu.fill(menuX, menuY, menuW, menuH, " ")
  
  -- Заголовок (градієнт)
  gpu.setBackground(COLORS.windowTitle)
  gpu.setForeground(COLORS.white)
  gpu.fill(menuX, menuY, menuW, 3, " ")
  gpu.set(menuX + 2, menuY + 1, "◢ FixOS 2.0 ◣")
  
  -- Пункти меню (покращені)
  gpu.setBackground(COLORS.windowBg)
  gpu.setForeground(COLORS.black)
  
  local items = {
    {y = 4, text = " ▸ Programs", icon = "📁"},
    {y = 6, text = " ▸ Settings", icon = "⚙"},
    {y = 8, text = " ▸ About", icon = "ℹ"},
    {y = 11, text = " ▸ Update", icon = "⟳"},
    {y = 13, text = " ⏻ Shut Down", icon = "⏻"}
  }
  
  for _, item in ipairs(items) do
    -- Фон пункту при наведенні (опціонально)
    gpu.setBackground(COLORS.windowBg)
    gpu.set(menuX + 2, menuY + item.y, item.text)
  end
  
  -- Розділювачі
  gpu.setForeground(COLORS.btnShadow)
  gpu.fill(menuX + 1, menuY + 10, menuW - 2, 1, "─")
  
  -- Рамка
  draw3DFrame(menuX, menuY, menuW, menuH, true)
  
  lastState.startMenu = true
  return items, menuX, menuY
end

local function redrawAll()
  drawDesktop()
  
  -- Малюємо всі вікна
  for i, win in ipairs(state.activeWindows) do
    drawWindow(win)
  end
  
  drawTaskbar()
  
  -- Малюємо Start menu якщо відкрите
  if state.startMenuOpen then
    drawStartMenu()
  end
end

-- ====================
-- КЕРУВАННЯ ВІКНАМИ
-- ====================

local function createWindow(title, width, height, programName)
  local program, err = loadProgram(programName)
  if not program then
    print("Failed to load program: " .. tostring(err))
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
    local ok, initErr = safeCall(program.init, win)
    if not ok then
      print("Program init error: " .. tostring(initErr))
    end
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
    
    -- ВИПРАВЛЕННЯ: Повне перемалювання після закриття
    state.needsFullRedraw = true
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
  for i, icon in ipairs(ICONS) do
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
  local windowSizes = {
    calculator = {42, 24},
    notepad = {65, 22},
    settings = {60, 20},
    mycomputer = {58, 18}
  }
  
  local size = windowSizes[program] or {50, 20}
  local title = program:sub(1, 1):upper() .. program:sub(2)
  
  createWindow(title, size[1], size[2], program)
  redrawAll()
end

local function executeMenuAction(action)
  if action == 1 then -- Programs
    executeIconAction("calculator")
  elseif action == 2 then -- Settings
    executeIconAction("settings")
  elseif action == 3 then -- About
    executeIconAction("settings")
  elseif action == 4 then -- Update
    executeIconAction("settings")
    -- Після відкриття settings, переключаємо на вкладку Update
    if state.activeWindows[#state.activeWindows] and 
       state.activeWindows[#state.activeWindows].program then
      state.activeWindows[#state.activeWindows].selectedTab = 3
    end
  elseif action == 5 then -- Shutdown
    gpu.setBackground(COLORS.black)
    gpu.setForeground(COLORS.white)
    gpu.fill(1, 1, w, h, " ")
    gpu.set(math.floor(w/2) - 10, math.floor(h/2), "Shutting down...")
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
-- ГОЛОВНИЙ ЦИКЛ (ОПТИМІЗОВАНИЙ)
-- ====================

local function mainLoop()
  redrawAll()
  
  while state.running do
    -- ОПТИМІЗАЦІЯ: Зменшено таймаут до 0.1 сек для швидшого відгуку
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
            
            if y == win.y and x >= win.x + win.w - 3 and x <= win.x + win.w - 1 then
              closeWindow(#state.activeWindows)
              redrawAll()
              
            elseif y == win.y and x >= win.x and x < win.x + win.w - 8 then
              state.dragWindow = win
              state.dragOffsetX = x - win.x
              state.dragOffsetY = y - win.y
              
            else
              local relX = x - win.x - 1
              local relY = y - win.y - 2
              
              local ok, needRedraw = safeCall(win.click, win, relX, relY, button)
              if ok and needRedraw then
                redrawAll()
              end
            end
            
            redrawAll()
          else
            local iconIndex = checkIconClick(x, y)
            if iconIndex then
              if state.selectedIcon == iconIndex then
                executeIconAction(ICONS[iconIndex].program)
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
      
    elseif eventType == "key_down" then
      local _, _, char, code = table.unpack(eventData)
      
      if code == 31 then
        state.startMenuOpen = not state.startMenuOpen
        redrawAll()
        
      elseif code == 45 then
        executeMenuAction(5)
        
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