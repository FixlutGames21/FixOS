-- ==============================================
-- FixOS 2.0 - system/desktop.lua (FIXED)
-- Робочий стіл з правильною ініціалізацією
-- ==============================================

-- На цьому етапі вже доступні:
-- component, computer, require, print, error, loadfile, dofile

local component = component
local computer = computer

-- ====================
-- Перевірка базових компонентів
-- ====================

if not component.isAvailable("gpu") then
  error("No GPU found!")
end

local gpu = component.proxy(component.list("gpu")())
local screen = component.list("screen")()

if not screen then
  error("No screen found!")
end

-- Прив'язуємо GPU до екрану
gpu.bind(screen)

-- Встановлюємо роздільну здатність
local maxW, maxH = gpu.maxResolution()
local w = math.min(80, maxW)
local h = math.min(25, maxH)
gpu.setResolution(w, h)

-- ====================
-- КОЛЬОРИ
-- ====================

local COLORS = {
  desktop = 0x008080,
  taskbar = 0xC0C0C0,
  taskbarDark = 0x808080,
  startBtn = 0x00AA00,
  startBtnText = 0xFFFFFF,
  iconBg = 0x008080,
  iconText = 0xFFFFFF,
  iconSelected = 0x000080,
  windowTitle = 0x000080,
  windowBg = 0xC0C0C0,
  white = 0xFFFFFF,
  black = 0x000000,
  btnHighlight = 0xFFFFFF,
  btnShadow = 0x808080,
  error = 0xFF0000,
  gray = 0x808080
}

-- ====================
-- УТИЛІТИ
-- ====================

-- Безпечне завантаження модуля програми
local function loadProgram(name)
  local path = "/system/programs/" .. name .. ".lua"
  
  -- Перевіряємо існування файлу
  local fs = component.proxy(computer.getBootAddress())
  if not fs.exists(path) then
    return nil, "Program not found: " .. name
  end
  
  -- Завантажуємо модуль
  local func, err = loadfile(path)
  if not func then
    return nil, "Load error: " .. tostring(err)
  end
  
  local ok, module = pcall(func)
  if not ok then
    return nil, "Init error: " .. tostring(module)
  end
  
  return module
end

-- Функція для безпечного виклику
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

-- Обрізка тексту під ширину
local function truncate(text, maxLen)
  text = tostring(text)
  if #text > maxLen then
    return text:sub(1, maxLen - 3) .. "..."
  end
  return text
end

-- ====================
-- ІКОНКИ НА РОБОЧОМУ СТОЛІ
-- ====================

local ICONS = {
  {x = 2, y = 2, w = 12, h = 4, label = "My Computer", icon = "[PC]", program = "mycomputer"},
  {x = 2, y = 7, w = 12, h = 4, label = "Calculator", icon = "[=]", program = "calculator"},
  {x = 2, y = 12, w = 12, h = 4, label = "Notepad", icon = "[N]", program = "notepad"},
  {x = 2, y = 17, w = 12, h = 4, label = "Settings", icon = "[*]", program = "settings"}
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

-- Малювання 3D рамки
local function draw3DFrame(x, y, w, h, raised)
  local topLeft = raised and COLORS.btnHighlight or COLORS.btnShadow
  local bottomRight = raised and COLORS.btnShadow or COLORS.btnHighlight
  
  gpu.setForeground(topLeft)
  for i = 0, w - 1 do gpu.set(x + i, y, "─") end
  for i = 0, h - 1 do gpu.set(x, y + i, "│") end
  
  gpu.setForeground(bottomRight)
  for i = 0, w - 1 do gpu.set(x + i, y + h - 1, "─") end
  for i = 0, h - 1 do gpu.set(x + w - 1, y + i, "│") end
end

-- Малювання іконки
local function drawIcon(icon, selected)
  local bg = selected and COLORS.iconSelected or COLORS.iconBg
  
  if selected then
    gpu.setBackground(bg)
    gpu.fill(icon.x, icon.y, icon.w, icon.h, " ")
  end
  
  gpu.setForeground(COLORS.iconText)
  local iconX = icon.x + math.floor((icon.w - #icon.icon) / 2)
  gpu.set(iconX, icon.y + 1, icon.icon)
  
  local textX = icon.x + math.floor((icon.w - #icon.label) / 2)
  gpu.set(textX, icon.y + 3, icon.label)
  
  gpu.setBackground(COLORS.desktop)
end

-- Малювання панелі задач
local function drawTaskbar()
  gpu.setBackground(COLORS.taskbar)
  gpu.fill(1, h, w, 1, " ")
  
  -- Верхня підсвітка
  gpu.setForeground(COLORS.btnHighlight)
  for i = 1, w do gpu.set(i, h, "▀") end
  
  -- Кнопка Start
  gpu.setBackground(COLORS.startBtn)
  gpu.setForeground(COLORS.startBtnText)
  gpu.fill(2, h, 9, 1, " ")
  gpu.set(3, h, "⊞ Start")
  
  -- Розділювач
  gpu.setBackground(COLORS.taskbar)
  gpu.setForeground(COLORS.btnShadow)
  gpu.set(12, h, "│")
  
  -- Кнопки вікон
  local btnX = 14
  for i, win in ipairs(state.activeWindows) do
    if btnX + 15 < w - 7 then
      local isFocused = (state.focusedWindow == i)
      gpu.setBackground(isFocused and COLORS.taskbarDark or COLORS.taskbar)
      gpu.setForeground(COLORS.black)
      gpu.fill(btnX, h, 15, 1, " ")
      
      local title = truncate(win.title or "Window", 12)
      gpu.set(btnX + 1, h, title)
      btnX = btnX + 16
    end
  end
  
  -- Годинник
  gpu.setBackground(COLORS.taskbar)
  gpu.setForeground(COLORS.black)
  local time = os.date("%H:%M")
  gpu.set(w - 6, h, time)
end

-- Малювання робочого столу
local function drawDesktop()
  gpu.setBackground(COLORS.desktop)
  gpu.fill(1, 1, w, h - 1, " ")
  
  for i, icon in ipairs(ICONS) do
    drawIcon(icon, state.selectedIcon == i)
  end
  
  drawTaskbar()
end

-- Малювання вікна
local function drawWindow(win)
  local wx, wy, ww, wh = win.x, win.y, win.w, win.h
  
  -- Тінь
  gpu.setBackground(COLORS.black)
  gpu.fill(wx + 1, wy + 1, ww, wh, " ")
  
  -- Фон вікна
  gpu.setBackground(COLORS.windowBg)
  gpu.fill(wx, wy, ww, wh, " ")
  
  -- Заголовок
  local isFocused = (state.activeWindows[state.focusedWindow] == win)
  gpu.setBackground(isFocused and COLORS.windowTitle or COLORS.btnShadow)
  gpu.setForeground(COLORS.white)
  gpu.fill(wx, wy, ww, 1, " ")
  
  local title = truncate(win.title or "Window", ww - 6)
  gpu.set(wx + 1, wy, title)
  
  -- Кнопка закриття
  gpu.set(wx + ww - 3, wy, "[X]")
  
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

-- Малювання меню Start
local function drawStartMenu()
  local menuW = 28
  local menuH = 14
  local menuX = 2
  local menuY = h - menuH - 1
  
  -- Тінь
  gpu.setBackground(COLORS.black)
  gpu.fill(menuX + 1, menuY + 1, menuW, menuH, " ")
  
  -- Фон меню
  gpu.setBackground(COLORS.windowBg)
  gpu.fill(menuX, menuY, menuW, menuH, " ")
  
  -- Заголовок
  gpu.setBackground(COLORS.windowTitle)
  gpu.setForeground(COLORS.white)
  gpu.fill(menuX, menuY, menuW, 2, " ")
  gpu.set(menuX + 1, menuY + 1, " FixOS 2.0")
  
  -- Пункти меню
  gpu.setBackground(COLORS.windowBg)
  gpu.setForeground(COLORS.black)
  
  local items = {
    {y = 3, text = " ► Programs"},
    {y = 5, text = " ► Settings"},
    {y = 7, text = " ► About"},
    {y = 9, text = " ⊗ Shut Down"}
  }
  
  for _, item in ipairs(items) do
    gpu.set(menuX + 2, menuY + item.y, item.text)
  end
  
  -- Розділювачі
  gpu.setForeground(COLORS.btnShadow)
  gpu.fill(menuX, menuY + 4, menuW, 1, "─")
  gpu.fill(menuX, menuY + 8, menuW, 1, "─")
  
  return items, menuX, menuY
end

-- Перемалювати все
local function redrawAll()
  drawDesktop()
  
  -- Малюємо всі вікна
  for i, win in ipairs(state.activeWindows) do
    drawWindow(win)
  end
  
  -- Малюємо Start menu якщо відкрите
  if state.startMenuOpen then
    drawStartMenu()
  end
end

-- ====================
-- КЕРУВАННЯ ВІКНАМИ
-- ====================

-- Створення нового вікна
local function createWindow(title, width, height, programName)
  -- Завантажуємо програму
  local program, err = loadProgram(programName)
  if not program then
    print("Failed to load program: " .. tostring(err))
    return nil
  end
  
  -- Позиція вікна
  local winX = math.floor((w - width) / 2) + #state.activeWindows * 2
  local winY = math.floor((h - height) / 2) + #state.activeWindows * 2
  
  -- Перевірка меж
  if winY + height > h - 1 then winY = 3 end
  if winX + width > w then winX = 3 end
  
  -- Створюємо об'єкт вікна
  local win = {
    title = title,
    x = winX,
    y = winY,
    w = width,
    h = height,
    program = program
  }
  
  -- Ініціалізуємо програму
  if program.init then
    local ok, initErr = safeCall(program.init, win)
    if not ok then
      print("Program init error: " .. tostring(initErr))
    end
  end
  
  -- Методи вікна
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
  
  -- Додаємо вікно до списку
  table.insert(state.activeWindows, win)
  state.focusedWindow = #state.activeWindows
  
  return win
end

-- Закриття вікна
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

-- Фокусування вікна
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

-- Перевірка кліку по іконці
local function checkIconClick(x, y)
  for i, icon in ipairs(ICONS) do
    if x >= icon.x and x < icon.x + icon.w and
       y >= icon.y and y < icon.y + icon.h and y < h - 1 then
      return i
    end
  end
  return nil
end

-- Перевірка кліку по кнопці Start
local function checkStartButton(x, y)
  return y == h and x >= 2 and x <= 10
end

-- Перевірка кліку по вікну
local function checkWindowClick(x, y)
  -- Перевіряємо з верхнього вікна
  for i = #state.activeWindows, 1, -1 do
    local win = state.activeWindows[i]
    if x >= win.x and x < win.x + win.w and
       y >= win.y and y < win.y + win.h then
      return i, win
    end
  end
  return nil, nil
end

-- Перевірка кліку по меню Start
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

-- Виконання дії іконки
local function executeIconAction(program)
  local windowSizes = {
    calculator = {40, 22},
    notepad = {60, 20},
    settings = {50, 18},
    mycomputer = {55, 16}
  }
  
  local size = windowSizes[program] or {50, 20}
  local title = program:sub(1, 1):upper() .. program:sub(2)
  
  createWindow(title, size[1], size[2], program)
  redrawAll()
end

-- Виконання дії меню
local function executeMenuAction(action)
  if action == 1 then -- Programs
    executeIconAction("calculator")
  elseif action == 2 then -- Settings
    executeIconAction("settings")
  elseif action == 3 then -- About
    executeIconAction("settings")
  elseif action == 4 then -- Shutdown
    gpu.setBackground(COLORS.black)
    gpu.setForeground(COLORS.white)
    gpu.fill(1, 1, w, h, " ")
    gpu.set(math.floor(w/2) - 10, math.floor(h/2), "Shutting down...")
    os.sleep(1)
    computer.shutdown()
  end
  
  state.startMenuOpen = false
  redrawAll()
end

-- Оновлення годинника
local function updateClock()
  if computer.uptime() - state.clockTimer > 30 then
    state.clockTimer = computer.uptime()
    
    gpu.setBackground(COLORS.taskbar)
    gpu.setForeground(COLORS.black)
    local time = os.date("%H:%M")
    gpu.set(w - 6, h, time)
  end
end

-- ====================
-- ГОЛОВНИЙ ЦИКЛ
-- ====================

local function mainLoop()
  -- Початкове малювання
  redrawAll()
  
  while state.running do
    -- Чекаємо на подію (макс. 0.5 сек)
    local eventData = {computer.pullSignal(0.5)}
    local eventType = eventData[1]
    
    -- Оновлюємо годинник
    updateClock()
    
    if eventType == "touch" or eventType == "drag" then
      local _, _, x, y, button = table.unpack(eventData)
      
      if eventType == "touch" then
        -- Обробка кліку
        
        if state.startMenuOpen then
          -- Клік в меню Start
          local action = checkStartMenuClick(x, y)
          if action then
            executeMenuAction(action)
          else
            state.startMenuOpen = false
            redrawAll()
          end
          
        elseif checkStartButton(x, y) then
          -- Клік по кнопці Start
          state.startMenuOpen = not state.startMenuOpen
          redrawAll()
          
        else
          -- Клік по вікну
          local winIndex, win = checkWindowClick(x, y)
          
          if winIndex then
            focusWindow(winIndex)
            
            -- Кнопка закриття
            if y == win.y and x >= win.x + win.w - 3 and x <= win.x + win.w - 1 then
              closeWindow(#state.activeWindows)
              redrawAll()
              
            -- Заголовок (перетягування)
            elseif y == win.y and x >= win.x and x < win.x + win.w - 6 then
              state.dragWindow = win
              state.dragOffsetX = x - win.x
              state.dragOffsetY = y - win.y
              
            -- Область контенту
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
            -- Клік по іконці
            local iconIndex = checkIconClick(x, y)
            if iconIndex then
              if state.selectedIcon == iconIndex then
                -- Подвійний клік - запускаємо
                executeIconAction(ICONS[iconIndex].program)
                state.selectedIcon = nil
              else
                -- Одинарний клік - вибираємо
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
        -- Перетягування вікна
        state.dragWindow.x = x - state.dragOffsetX
        state.dragWindow.y = y - state.dragOffsetY
        
        -- Утримуємо вікно на екрані
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
      
      -- Глобальні гарячі клавіші
      if code == 31 then -- S - Start menu
        state.startMenuOpen = not state.startMenuOpen
        redrawAll()
        
      elseif code == 45 then -- X - Shutdown
        executeMenuAction(4)
        
      elseif state.focusedWindow and state.activeWindows[state.focusedWindow] then
        -- Передаємо клавішу активному вікну
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

-- Запускаємо головний цикл з обробкою помилок
local ok, err = pcall(mainLoop)

if not ok then
  -- Показуємо помилку
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFF0000)
  gpu.fill(1, 1, w, h, " ")
  
  gpu.set(2, 2, "Desktop Error:")
  gpu.set(2, 3, truncate(tostring(err), w - 4))
  gpu.set(2, 5, "Press any key to shutdown")
  
  computer.pullSignal()
  computer.shutdown()
end