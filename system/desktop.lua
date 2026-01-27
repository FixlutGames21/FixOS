-- ==============================================
-- ФАЙЛ: system/desktop.lua
-- Windows 2000 Style Desktop з іконками та панеллю задач
-- ==============================================
local component = require("component")
local computer = require("computer")
local term = require("term")
local event = require("event")
local shell = require("shell")

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
  desktop = 0x008080,      -- Teal desktop
  taskbar = 0xC0C0C0,      -- Gray taskbar
  taskbarDark = 0x808080,  -- Dark gray border
  startBtn = 0x00AA00,     -- Green Start button
  startBtnText = 0xFFFFFF, -- White text
  iconBg = 0x008080,       -- Same as desktop
  iconText = 0xFFFFFF,     -- White text
  iconSelected = 0x000080, -- Navy blue when selected
  windowTitle = 0x000080,  -- Navy blue
  windowBg = 0xC0C0C0,     -- Gray
  white = 0xFFFFFF,
  black = 0x000000
}

-- Іконки на робочому столі
local ICONS = {
  {x = 2, y = 2, w = 10, h = 3, label = "My Computer", action = "mycomputer"},
  {x = 2, y = 6, w = 10, h = 3, label = "Calculator", action = "calc"},
  {x = 2, y = 10, w = 10, h = 3, label = "Text Editor", action = "edit"},
  {x = 2, y = 14, w = 10, h = 3, label = "Terminal", action = "terminal"},
  {x = 2, y = 18, w = 10, h = 3, label = "Settings", action = "settings"}
}

local selectedIcon = nil
local startMenuOpen = false
local clockTimer = 0

-- Малювання іконки
local function drawIcon(icon, selected)
  local bg = selected and COLORS.iconSelected or COLORS.iconBg
  local fg = COLORS.iconText
  
  gpu.setBackground(bg)
  if selected then
    gpu.fill(icon.x, icon.y, icon.w, icon.h, " ")
  end
  
  gpu.setForeground(fg)
  
  -- Малюємо іконку (простий ASCII арт)
  local iconChar = "[]"
  if icon.action == "calc" then iconChar = "[=]"
  elseif icon.action == "edit" then iconChar = "[T]"
  elseif icon.action == "terminal" then iconChar = "[>]"
  elseif icon.action == "settings" then iconChar = "[*]"
  elseif icon.action == "mycomputer" then iconChar = "[C]"
  end
  
  local iconX = icon.x + math.floor(icon.w / 2) - 1
  gpu.set(iconX, icon.y, iconChar)
  
  -- Текст під іконкою
  local textX = icon.x + math.floor((icon.w - #icon.label) / 2)
  gpu.set(textX, icon.y + 2, icon.label)
  
  gpu.setBackground(COLORS.desktop)
end

-- Малювання панелі задач (taskbar)
local function drawTaskbar()
  -- Основна панель
  gpu.setBackground(COLORS.taskbar)
  gpu.fill(1, h, w, 1, " ")
  
  -- Тінь зверху
  gpu.setBackground(COLORS.taskbarDark)
  gpu.fill(1, h, w, 1, "▀")
  
  gpu.setBackground(COLORS.taskbar)
  
  -- Кнопка Start
  gpu.setBackground(COLORS.startBtn)
  gpu.setForeground(COLORS.startBtnText)
  gpu.fill(1, h, 8, 1, " ")
  gpu.set(2, h, "Start")
  
  -- Роздільник
  gpu.setBackground(COLORS.taskbarDark)
  gpu.set(9, h, "│")
  
  -- Годинник справа
  gpu.setBackground(COLORS.taskbar)
  gpu.setForeground(COLORS.black)
  local time = os.date("%H:%M")
  gpu.set(w - 5, h, time)
end

-- Малювання всього робочого столу
local function drawDesktop()
  -- Фон робочого столу
  gpu.setBackground(COLORS.desktop)
  gpu.fill(1, 1, w, h - 1, " ")
  
  -- Іконки
  for i, icon in ipairs(ICONS) do
    drawIcon(icon, selectedIcon == i)
  end
  
  -- Панель задач
  drawTaskbar()
  
  -- Закриваємо меню Пуск якщо було відкрите
  startMenuOpen = false
end

-- Малювання меню Пуск
local function drawStartMenu()
  local menuW = 25
  local menuH = 12
  local menuX = 1
  local menuY = h - menuH - 1
  
  -- Тінь
  gpu.setBackground(COLORS.taskbarDark)
  gpu.fill(menuX + 1, menuY + 1, menuW, menuH, " ")
  
  -- Основне вікно меню
  gpu.setBackground(COLORS.windowBg)
  gpu.fill(menuX, menuY, menuW, menuH, " ")
  
  -- Заголовок
  gpu.setBackground(COLORS.windowTitle)
  gpu.setForeground(COLORS.white)
  gpu.fill(menuX, menuY, menuW, 2, " ")
  gpu.set(menuX + 1, menuY, " FixOS 2000")
  
  -- Пункти меню
  gpu.setBackground(COLORS.windowBg)
  gpu.setForeground(COLORS.black)
  
  local menuItems = {
    {y = menuY + 3, text = " Programs", action = "programs"},
    {y = menuY + 4, text = " Documents", action = "docs"},
    {y = menuY + 5, text = " Settings", action = "settings"},
    {y = menuY + 6, text = " Search", action = "search"},
    {y = menuY + 7, text = " Help", action = "help"},
    {y = menuY + 8, text = " Run...", action = "run"},
    {y = menuY + 10, text = " Shut Down...", action = "shutdown"}
  }
  
  for _, item in ipairs(menuItems) do
    gpu.set(menuX + 1, item.y, item.text)
  end
  
  -- Роздільник
  gpu.set(menuX, menuY + 9, "─")
  for i = 2, menuW - 1 do
    gpu.set(menuX + i - 1, menuY + 9, "─")
  end
  
  startMenuOpen = true
  return menuItems
end

-- Перевірка кліку на іконку
local function checkIconClick(x, y)
  for i, icon in ipairs(ICONS) do
    if x >= icon.x and x < icon.x + icon.w and
       y >= icon.y and y < icon.y + icon.h then
      return i
    end
  end
  return nil
end

-- Перевірка кліку на кнопку Start
local function checkStartButton(x, y)
  return y == h and x >= 1 and x <= 8
end

-- Перевірка кліку на меню Пуск
local function checkStartMenuClick(x, y)
  local menuY = h - 13
  local menuItems = {
    {y = menuY + 3, action = "programs"},
    {y = menuY + 4, action = "docs"},
    {y = menuY + 5, action = "settings"},
    {y = menuY + 6, action = "search"},
    {y = menuY + 7, action = "help"},
    {y = menuY + 8, action = "run"},
    {y = menuY + 10, action = "shutdown"}
  }
  
  for _, item in ipairs(menuItems) do
    if y == item.y and x >= 1 and x <= 25 then
      return item.action
    end
  end
  return nil
end

-- Виконання дії іконки
local function executeIconAction(action)
  gpu.setBackground(COLORS.black)
  gpu.setForeground(COLORS.white)
  term.clear()
  
  if action == "calc" then
    dofile("/bin/calc.lua")
  elseif action == "edit" then
    dofile("/bin/edit.lua")
  elseif action == "terminal" then
    shell.execute("sh")
  elseif action == "settings" then
    dofile("/system/settings.lua")
  elseif action == "mycomputer" then
    -- My Computer - показуємо список дисків
    print("FixOS 2000 - My Computer")
    print("")
    for addr in component.list("filesystem") do
      local proxy = component.proxy(addr)
      local label = proxy.getLabel() or "Unnamed"
      print(label .. " (" .. addr:sub(1, 8) .. ")")
    end
    print("")
    print("Press any key to return...")
    event.pull("key_down")
  end
  
  drawDesktop()
end

-- Виконання дії меню Пуск
local function executeMenuAction(action)
  if action == "shutdown" then
    gpu.setBackground(COLORS.black)
    gpu.setForeground(COLORS.white)
    term.clear()
    print("FixOS 2000 is shutting down...")
    os.sleep(1)
    computer.shutdown()
  elseif action == "settings" then
    gpu.setBackground(COLORS.black)
    term.clear()
    dofile("/system/settings.lua")
    drawDesktop()
  elseif action == "run" then
    gpu.setBackground(COLORS.black)
    term.clear()
    print("Run Program")
    print("")
    io.write("Enter command: ")
    local cmd = io.read()
    if cmd and cmd ~= "" then
      shell.execute(cmd)
    end
    drawDesktop()
  elseif action == "programs" then
    drawDesktop()
    -- Підменю Programs
    local subMenuY = h - 13
    gpu.setBackground(COLORS.windowBg)
    gpu.fill(26, subMenuY + 3, 20, 5, " ")
    gpu.setForeground(COLORS.black)
    gpu.set(27, subMenuY + 3, " Calculator")
    gpu.set(27, subMenuY + 4, " Text Editor")
    gpu.set(27, subMenuY + 5, " Terminal")
  else
    -- Для інших пунктів просто закриваємо меню
    drawDesktop()
  end
end

-- Оновлення годинника
local function updateClock()
  if computer.uptime() - clockTimer > 30 then
    clockTimer = computer.uptime()
    gpu.setBackground(COLORS.taskbar)
    gpu.setForeground(COLORS.black)
    local time = os.date("%H:%M")
    gpu.set(w - 5, h, time)
  end
end

-- Головний цикл
local function main()
  drawDesktop()
  
  while true do
    local eventData = {event.pull(0.5)}
    local eventType = eventData[1]
    
    -- Оновлення годинника
    updateClock()
    
    if eventType == "touch" then
      local _, _, x, y, button = table.unpack(eventData)
      
      if startMenuOpen then
        -- Якщо меню відкрите
        local menuAction = checkStartMenuClick(x, y)
        if menuAction then
          executeMenuAction(menuAction)
          startMenuOpen = false
        else
          -- Клік поза меню - закриваємо його
          drawDesktop()
        end
      else
        -- Перевірка кнопки Start
        if checkStartButton(x, y) then
          drawStartMenu()
        else
          -- Перевірка кліку на іконку
          local iconIndex = checkIconClick(x, y)
          if iconIndex then
            if selectedIcon == iconIndex then
              -- Подвійний клік - запускаємо
              executeIconAction(ICONS[iconIndex].action)
              selectedIcon = nil
            else
              -- Одинарний клік - виділяємо
              selectedIcon = iconIndex
              drawDesktop()
            end
          else
            -- Клік на пусте місце - знімаємо виділення
            if selectedIcon then
              selectedIcon = nil
              drawDesktop()
            end
          end
        end
      end
      
    elseif eventType == "key_down" then
      local _, _, char, code = table.unpack(eventData)
      
      -- Гарячі клавіші
      if code == 31 then -- S key - Start menu
        if startMenuOpen then
          drawDesktop()
        else
          drawStartMenu()
        end
      elseif code == 45 then -- X key - Shutdown
        gpu.setBackground(COLORS.black)
        gpu.setForeground(COLORS.white)
        term.clear()
        print("FixOS 2000 is shutting down...")
        os.sleep(1)
        computer.shutdown()
      elseif code == 28 and selectedIcon then -- Enter - відкрити виділену іконку
        executeIconAction(ICONS[selectedIcon].action)
        selectedIcon = nil
      elseif code == 200 and selectedIcon and selectedIcon > 1 then -- Up arrow
        selectedIcon = selectedIcon - 1
        drawDesktop()
      elseif code == 208 and selectedIcon and selectedIcon < #ICONS then -- Down arrow
        selectedIcon = selectedIcon + 1
        drawDesktop()
      end
    end
  end
end

-- Запуск з обробкою помилок
local ok, err = pcall(main)
if not ok then
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFF0000)
  term.clear()
  print("Desktop Error:")
  print(tostring(err))
  print("")
  print("Press any key to shutdown...")
  event.pull("key_down")
  computer.shutdown()
end
