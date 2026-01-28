-- ==============================================
-- ФАЙЛ: system/desktop.lua
-- Windows 2000 з віконним менеджером
-- ==============================================
local component = require("component")
local computer = require("computer")
local event = require("event")
local unicode = require("unicode")

if not component.isAvailable("gpu") then
  print("ERROR: No GPU available!")
  os.exit()
end

local gpu = component.gpu
local w, h = gpu.maxResolution()
gpu.setResolution(math.min(80, w), math.min(25, h))
w, h = gpu.getResolution()

-- Кольори Windows 2000
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
  btnFace = 0xC0C0C0,
  btnHighlight = 0xFFFFFF,
  btnShadow = 0x808080,
  btnDarkShadow = 0x404040
}

-- Іконки на робочому столі
local ICONS = {
  {x = 2, y = 2, w = 12, h = 4, label = "My Computer", icon = "[PC]", action = "mycomputer"},
  {x = 2, y = 7, w = 12, h = 4, label = "Calculator", icon = "[=]", action = "calc"},
  {x = 2, y = 12, w = 12, h = 4, label = "Notepad", icon = "[N]", action = "notepad"},
  {x = 2, y = 17, w = 12, h = 4, label = "Settings", icon = "[*]", action = "settings"}
}

local selectedIcon = nil
local startMenuOpen = false
local activeWindows = {}
local focusedWindow = nil
local dragWindow = nil
local dragOffsetX, dragOffsetY = 0, 0
local clockTimer = 0

-- Завантаження модулів вікон
local windowModules = dofile("/system/windows.lua")

-- Малювання 3D рамки
local function draw3DFrame(x, y, w, h, raised)
  if raised then
    gpu.setForeground(COLORS.btnHighlight)
    for i = 0, w - 1 do gpu.set(x + i, y, "─") end
    for i = 0, h - 1 do gpu.set(x, y + i, "│") end
    
    gpu.setForeground(COLORS.btnShadow)
    for i = 0, w - 1 do gpu.set(x + i, y + h - 1, "─") end
    for i = 0, h - 1 do gpu.set(x + w - 1, y + i, "│") end
  else
    gpu.setForeground(COLORS.btnShadow)
    for i = 0, w - 1 do gpu.set(x + i, y, "─") end
    for i = 0, h - 1 do gpu.set(x, y + i, "│") end
    
    gpu.setForeground(COLORS.btnHighlight)
    for i = 0, w - 1 do gpu.set(x + i, y + h - 1, "─") end
    for i = 0, h - 1 do gpu.set(x + w - 1, y + i, "│") end
  end
end

-- Малювання іконки
local function drawIcon(icon, selected)
  local bg = selected and COLORS.iconSelected or COLORS.iconBg
  local fg = COLORS.iconText
  
  if selected then
    gpu.setBackground(bg)
    gpu.fill(icon.x, icon.y, icon.w, icon.h, " ")
  end
  
  gpu.setForeground(fg)
  
  -- Іконка
  local iconX = icon.x + math.floor(icon.w / 2) - math.floor(unicode.len(icon.icon) / 2)
  gpu.set(iconX, icon.y + 1, icon.icon)
  
  -- Текст
  local textX = icon.x + math.floor((icon.w - unicode.len(icon.label)) / 2)
  gpu.set(textX, icon.y + 3, icon.label)
  
  gpu.setBackground(COLORS.desktop)
end

-- Малювання панелі задач
local function drawTaskbar()
  gpu.setBackground(COLORS.taskbar)
  gpu.fill(1, h, w, 1, " ")
  
  -- Верхня рамка
  gpu.setForeground(COLORS.btnHighlight)
  for i = 1, w do gpu.set(i, h, "▀") end
  
  -- Кнопка Start
  gpu.setBackground(COLORS.startBtn)
  gpu.setForeground(COLORS.startBtnText)
  gpu.fill(2, h, 9, 1, " ")
  gpu.set(3, h, "⊞ Start")
  
  -- Роздільник
  gpu.setBackground(COLORS.taskbar)
  gpu.setForeground(COLORS.btnShadow)
  gpu.set(12, h, "│")
  
  -- Кнопки вікон
  local btnX = 14
  for i, win in ipairs(activeWindows) do
    if btnX + 15 < w - 7 then
      local isFocused = (focusedWindow == i)
      gpu.setBackground(isFocused and COLORS.taskbarDark or COLORS.taskbar)
      gpu.setForeground(COLORS.black)
      gpu.fill(btnX, h, 15, 1, " ")
      local title = win.title
      if unicode.len(title) > 12 then title = unicode.sub(title, 1, 12) .. "..." end
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
    drawIcon(icon, selectedIcon == i)
  end
  
  drawTaskbar()
  startMenuOpen = false
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
  local isFocused = (activeWindows[focusedWindow] == win)
  gpu.setBackground(isFocused and COLORS.windowTitle or COLORS.btnShadow)
  gpu.setForeground(COLORS.white)
  gpu.fill(wx, wy, ww, 1, " ")
  
  local title = win.title or "Window"
  if unicode.len(title) > ww - 6 then
    title = unicode.sub(title, 1, ww - 9) .. "..."
  end
  gpu.set(wx + 1, wy, title)
  
  -- Кнопки вікна
  gpu.set(wx + ww - 4, wy, "[_]")
  gpu.set(wx + ww - 2, wy, "[X]")
  
  -- Рамка
  gpu.setBackground(COLORS.windowBg)
  draw3DFrame(wx, wy + 1, ww, wh - 1, true)
  
  -- Вміст вікна
  if win.draw then
    win:draw(gpu, wx + 1, wy + 2, ww - 2, wh - 3)
  end
end

-- Малювання всіх вікон
local function redrawAll()
  drawDesktop()
  for i, win in ipairs(activeWindows) do
    drawWindow(win)
  end
  if startMenuOpen then
    drawStartMenu()
  end
end

-- Малювання меню Пуск
function drawStartMenu()
  local menuW = 28
  local menuH = 14
  local menuX = 2
  local menuY = h - menuH - 1
  
  -- Тінь
  gpu.setBackground(COLORS.black)
  gpu.fill(menuX + 1, menuY + 1, menuW, menuH, " ")
  
  -- Вікно меню
  gpu.setBackground(COLORS.windowBg)
  gpu.fill(menuX, menuY, menuW, menuH, " ")
  
  -- Заголовок
  gpu.setBackground(COLORS.windowTitle)
  gpu.setForeground(COLORS.white)
  gpu.fill(menuX, menuY, menuW, 2, " ")
  gpu.set(menuX + 1, menuY + 1, " FixOS 2000")
  
  -- Пункти меню
  gpu.setBackground(COLORS.windowBg)
  gpu.setForeground(COLORS.black)
  
  local items = {
    {y = 3, text = " ► Programs", action = "programs"},
    {y = 4, text = " ► Documents", action = "docs"},
    {y = 5, text = " ► Settings", action = "settings"},
    {y = 7, text = " ► Search", action = "search"},
    {y = 8, text = " ► Help", action = "help"},
    {y = 9, text = " ► Run...", action = "run"},
    {y = 11, text = " ⊗ Shut Down", action = "shutdown"}
  }
  
  for _, item in ipairs(items) do
    gpu.set(menuX + 2, menuY + item.y, item.text)
  end
  
  -- Роздільник
  gpu.setForeground(COLORS.btnShadow)
  for i = 0, menuW - 1 do
    gpu.set(menuX + i, menuY + 6, "─")
    gpu.set(menuX + i, menuY + 10, "─")
  end
  
  startMenuOpen = true
  return items, menuX, menuY
end

-- Перевірки кліків
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
  return y == h and x >= 2 and x <= 10
end

local function checkWindowClick(x, y)
  for i = #activeWindows, 1, -1 do
    local win = activeWindows[i]
    if x >= win.x and x < win.x + win.w and
       y >= win.y and y < win.y + win.h then
      return i, win
    end
  end
  return nil, nil
end

local function checkStartMenuClick(x, y)
  if not startMenuOpen then return nil end
  local items, menuX, menuY = drawStartMenu()
  startMenuOpen = false  -- Reset
  startMenuOpen = true   -- Set back
  
  for _, item in ipairs(items) do
    if y == menuY + item.y and x >= menuX and x < menuX + 28 then
      return item.action
    end
  end
  return nil
end

local function checkTaskbarWindowClick(x, y)
  if y ~= h then return nil end
  local btnX = 14
  for i, win in ipairs(activeWindows) do
    if x >= btnX and x < btnX + 15 then
      return i
    end
    btnX = btnX + 16
  end
  return nil
end

-- Створення вікна
local function createWindow(title, width, height, windowModule)
  local winX = math.floor((w - width) / 2) + #activeWindows * 2
  local winY = math.floor((h - height) / 2) + #activeWindows * 2
  
  if winY + height > h - 1 then winY = 3 end
  if winX + width > w then winX = 3 end
  
  local win = {
    title = title,
    x = winX,
    y = winY,
    w = width,
    h = height,
    module = windowModule
  }
  
  if windowModule and windowModule.init then
    windowModule.init(win)
  end
  
  function win:draw(gpu, x, y, w, h)
    if self.module and self.module.draw then
      self.module.draw(self, gpu, x, y, w, h)
    end
  end
  
  function win:click(x, y, button)
    if self.module and self.module.click then
      return self.module.click(self, x, y, button)
    end
  end
  
  function win:key(char, code)
    if self.module and self.module.key then
      return self.module.key(self, char, code)
    end
  end
  
  table.insert(activeWindows, win)
  focusedWindow = #activeWindows
  return win
end

-- Закриття вікна
local function closeWindow(index)
  if activeWindows[index] then
    table.remove(activeWindows, index)
    if focusedWindow == index then
      focusedWindow = #activeWindows
    elseif focusedWindow > index then
      focusedWindow = focusedWindow - 1
    end
  end
end

-- Фокусування вікна
local function focusWindow(index)
  if index and activeWindows[index] then
    local win = table.remove(activeWindows, index)
    table.insert(activeWindows, win)
    focusedWindow = #activeWindows
  end
end

-- Виконання дії іконки
local function executeIconAction(action)
  if action == "calc" then
    createWindow("Calculator", 40, 22, windowModules.calculator)
  elseif action == "notepad" then
    createWindow("Notepad", 60, 20, windowModules.notepad)
  elseif action == "settings" then
    createWindow("Settings", 50, 18, windowModules.settings)
  elseif action == "mycomputer" then
    createWindow("My Computer", 55, 16, windowModules.mycomputer)
  end
  redrawAll()
end

-- Виконання дії меню
local function executeMenuAction(action)
  if action == "shutdown" then
    gpu.setBackground(COLORS.black)
    gpu.setForeground(COLORS.white)
    gpu.fill(1, 1, w, h, " ")
    gpu.set(math.floor(w/2) - 10, math.floor(h/2), "Shutting down...")
    os.sleep(1)
    computer.shutdown()
  elseif action == "settings" then
    createWindow("Settings", 50, 18, windowModules.settings)
  elseif action == "run" then
    -- TODO: Run dialog
  elseif action == "programs" then
    -- Submenu з програмами
    executeIconAction("calc")
  end
  startMenuOpen = false
  redrawAll()
end

-- Оновлення годинника
local function updateClock()
  if computer.uptime() - clockTimer > 30 then
    clockTimer = computer.uptime()
    gpu.setBackground(COLORS.taskbar)
    gpu.setForeground(COLORS.black)
    local time = os.date("%H:%M")
    gpu.set(w - 6, h, time)
  end
end

-- Головний цикл
local function main()
  drawDesktop()
  
  while true do
    local eventData = {event.pull(0.5)}
    local eventType = eventData[1]
    
    updateClock()
    
    if eventType == "touch" or eventType == "drag" then
      local _, _, x, y, button = table.unpack(eventData)
      
      if eventType == "touch" then
        if startMenuOpen then
          local action = checkStartMenuClick(x, y)
          if action then
            executeMenuAction(action)
          else
            startMenuOpen = false
            redrawAll()
          end
        elseif checkStartButton(x, y) then
          startMenuOpen = not startMenuOpen
          redrawAll()
        else
          local winIndex, win = checkWindowClick(x, y)
          
          if winIndex then
            focusWindow(winIndex)
            
            -- Перевірка кнопки закриття
            if y == win.y and x >= win.x + win.w - 2 and x <= win.x + win.w - 1 then
              closeWindow(#activeWindows)
              redrawAll()
            elseif y == win.y and x >= win.x and x < win.x + win.w - 6 then
              -- Початок перетягування
              dragWindow = win
              dragOffsetX = x - win.x
              dragOffsetY = y - win.y
            else
              -- Клік всередині вікна
              local relX = x - win.x - 1
              local relY = y - win.y - 2
              if win.click then
                local needRedraw = win:click(relX, relY, button)
                if needRedraw then redrawAll() end
              end
            end
            
            redrawAll()
          else
            -- Клік на taskbar кнопку вікна
            local taskWin = checkTaskbarWindowClick(x, y)
            if taskWin then
              focusWindow(taskWin)
              redrawAll()
            else
              -- Клік на іконку
              local iconIndex = checkIconClick(x, y)
              if iconIndex then
                if selectedIcon == iconIndex then
                  executeIconAction(ICONS[iconIndex].action)
                  selectedIcon = nil
                else
                  selectedIcon = iconIndex
                  redrawAll()
                end
              else
                selectedIcon = nil
                redrawAll()
              end
            end
          end
        end
      elseif eventType == "drag" and dragWindow then
        dragWindow.x = x - dragOffsetX
        dragWindow.y = y - dragOffsetY
        
        -- Обмеження
        if dragWindow.x < 0 then dragWindow.x = 0 end
        if dragWindow.y < 1 then dragWindow.y = 1 end
        if dragWindow.x + dragWindow.w > w then dragWindow.x = w - dragWindow.w end
        if dragWindow.y + dragWindow.h > h - 1 then dragWindow.y = h - 1 - dragWindow.h end
        
        redrawAll()
      end
    elseif eventType == "drop" then
      dragWindow = nil
    elseif eventType == "key_down" then
      local _, _, char, code = table.unpack(eventData)
      
      if code == 31 then -- S
        startMenuOpen = not startMenuOpen
        redrawAll()
      elseif code == 45 then -- X
        executeMenuAction("shutdown")
      elseif focusedWindow and activeWindows[focusedWindow] then
        local win = activeWindows[focusedWindow]
        if win.key then
          local needRedraw = win:key(char, code)
          if needRedraw then redrawAll() end
        end
      end
    end
  end
end

local ok, err = pcall(main)
if not ok then
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFF0000)
  gpu.fill(1, 1, w, h, " ")
  gpu.set(2, 2, "Desktop Error:")
  gpu.set(2, 3, tostring(err))
  event.pull("key_down")
  computer.shutdown()
end