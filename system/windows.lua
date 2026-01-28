-- ==============================================
-- ФАЙЛ: system/windows.lua
-- Всі модулі вікон з системою оновлень
-- ==============================================

-- ==============================================
-- Calculator Module
-- ==============================================
local calc = {}

function calc.init(win)
  win.display = "0"
  win.lastNum = 0
  win.operation = nil
  win.newNumber = true
  
  win.buttons = {
    {x=2, y=4, w=6, h=2, t="7", v="7"},
    {x=9, y=4, w=6, h=2, t="8", v="8"},
    {x=16, y=4, w=6, h=2, t="9", v="9"},
    {x=23, y=4, w=6, h=2, t="/", v="/"},
    {x=30, y=4, w=6, h=2, t="C", v="C"},
    
    {x=2, y=7, w=6, h=2, t="4", v="4"},
    {x=9, y=7, w=6, h=2, t="5", v="5"},
    {x=16, y=7, w=6, h=2, t="6", v="6"},
    {x=23, y=7, w=6, h=2, t="*", v="*"},
    
    {x=2, y=10, w=6, h=2, t="1", v="1"},
    {x=9, y=10, w=6, h=2, t="2", v="2"},
    {x=16, y=10, w=6, h=2, t="3", v="3"},
    {x=23, y=10, w=6, h=2, t="-", v="-"},
    
    {x=2, y=13, w=6, h=2, t="0", v="0"},
    {x=9, y=13, w=6, h=2, t=".", v="."},
    {x=16, y=13, w=6, h=2, t="+/-", v="+-"},
    {x=23, y=13, w=6, h=2, t="+", v="+"},
    {x=30, y=7, w=6, h=9, t="=", v="="}
  }
end

function calc.draw(win, gpu, x, y, w, h)
  -- Дисплей
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  gpu.fill(x + 1, y, w - 2, 2, " ")
  
  -- Рамка дисплею
  gpu.setForeground(0x808080)
  for i = 0, w - 3 do
    gpu.set(x + 1 + i, y, "▄")
    gpu.set(x + 1 + i, y + 1, "▀")
  end
  
  local dispText = tostring(win.display)
  if #dispText > w - 4 then dispText = dispText:sub(1, w - 4) end
  gpu.setForeground(0x000000)
  gpu.set(x + w - 2 - #dispText, y + 1, dispText)
  
  -- Кнопки
  gpu.setBackground(0xC0C0C0)
  for _, btn in ipairs(win.buttons) do
    gpu.fill(x + btn.x, y + btn.y, btn.w, btn.h, " ")
    
    -- 3D ефект
    gpu.setForeground(0xFFFFFF)
    for i = 0, btn.w - 1 do gpu.set(x + btn.x + i, y + btn.y, "▀") end
    for i = 0, btn.h - 1 do gpu.set(x + btn.x, y + btn.y + i, "▌") end
    
    gpu.setForeground(0x808080)
    for i = 0, btn.w - 1 do gpu.set(x + btn.x + i, y + btn.y + btn.h - 1, "▄") end
    for i = 0, btn.h - 1 do gpu.set(x + btn.x + btn.w - 1, y + btn.y + i, "▐") end
    
    gpu.setForeground(0x000000)
    local tx = x + btn.x + math.floor((btn.w - #btn.t) / 2)
    local ty = y + btn.y + math.floor(btn.h / 2)
    gpu.set(tx, ty, btn.t)
  end
end

function calc.click(win, x, y, button)
  for _, btn in ipairs(win.buttons) do
    if x >= btn.x and x < btn.x + btn.w and
       y >= btn.y and y < btn.y + btn.h then
      calc.handleButton(win, btn.v)
      return true
    end
  end
  return false
end

function calc.handleButton(win, value)
  if value == "C" then
    win.display = "0"
    win.lastNum = 0
    win.operation = nil
    win.newNumber = true
  elseif value == "=" then
    calc.calculate(win)
  elseif value == "+-" then
    local num = tonumber(win.display)
    if num then win.display = tostring(-num) end
  elseif value == "+" or value == "-" or value == "*" or value == "/" then
    if win.operation then calc.calculate(win) end
    win.lastNum = tonumber(win.display) or 0
    win.operation = value
    win.newNumber = true
  elseif (value >= "0" and value <= "9") or value == "." then
    if win.newNumber then
      win.display = (value == ".") and "0." or value
      win.newNumber = false
    else
      if value == "." and win.display:find("%.") then return end
      win.display = (win.display == "0" and value ~= ".") and value or (win.display .. value)
    end
  end
end

function calc.calculate(win)
  if win.operation and win.lastNum then
    local current = tonumber(win.display) or 0
    local result
    if win.operation == "+" then result = win.lastNum + current
    elseif win.operation == "-" then result = win.lastNum - current
    elseif win.operation == "*" then result = win.lastNum * current
    elseif win.operation == "/" then
      result = (current ~= 0) and (win.lastNum / current) or nil
    end
    
    if result then
      win.display = string.format("%.8f", result):gsub("%.?0+$", "")
      if win.display == "" then win.display = "0" end
    else
      win.display = "Error"
    end
    
    win.lastNum = tonumber(win.display) or 0
    win.operation = nil
  end
  win.newNumber = true
end

-- ==============================================
-- Settings Module з оновленням системи
-- ==============================================
local settings = {}

function settings.init(win)
  win.selectedTab = 1
  win.updateStatus = "Ready"
  win.updateProgress = ""
  win.tabs = {"System", "Update", "About"}
  win.checkingUpdate = false
  win.installingUpdate = false
end

function settings.draw(win, gpu, x, y, w, h)
  -- Вкладки
  gpu.setBackground(0xC0C0C0)
  local tabX = x
  for i, tab in ipairs(win.tabs) do
    local isActive = (win.selectedTab == i)
    gpu.setBackground(isActive and 0xFFFFFF or 0xA0A0A0)
    gpu.setForeground(0x000000)
    gpu.fill(tabX, y, 13, 2, " ")
    
    -- 3D рамка вкладки
    if isActive then
      gpu.setForeground(0xFFFFFF)
      for k = 0, 12 do gpu.set(tabX + k, y, "▀") end
    end
    
    gpu.setForeground(0x000000)
    gpu.set(tabX + 3, y + 1, tab)
    tabX = tabX + 14
  end
  
  -- Вміст
  gpu.setBackground(0xFFFFFF)
  gpu.fill(x, y + 3, w, h - 3, " ")
  gpu.setForeground(0x000000)
  
  if win.selectedTab == 1 then
    -- System Info
    gpu.set(x + 2, y + 5, "Operating System: FixOS 2000")
    gpu.set(x + 2, y + 6, "Version: 1.0 Windowed Edition")
    gpu.set(x + 2, y + 7, "Author: FixlutGames21")
    
    local component = require("component")
    local computer = require("computer")
    
    local totalMem = computer.totalMemory()
    local freeMem = computer.freeMemory()
    gpu.set(x + 2, y + 9, string.format("Memory: %dKB / %dKB", 
            math.floor(freeMem/1024), math.floor(totalMem/1024)))
    
    local energy = computer.energy()
    local maxEnergy = computer.maxEnergy()
    gpu.set(x + 2, y + 10, string.format("Energy: %d / %d", 
            math.floor(energy), math.floor(maxEnergy)))
    
    -- Компоненти
    gpu.set(x + 2, y + 12, "Components:")
    local cy = y + 13
    for name in component.list() do
      if cy < y + h - 1 then
        gpu.set(x + 3, cy, "- " .. name)
        cy = cy + 1
      end
    end
    
  elseif win.selectedTab == 2 then
    -- Update Tab
    gpu.set(x + 2, y + 5, "System Update Manager")
    
    -- Статус
    gpu.setBackground(0xE0E0E0)
    gpu.fill(x + 2, y + 7, w - 4, 2, " ")
    gpu.setForeground(0x000000)
    gpu.set(x + 3, y + 8, "Status: " .. win.updateStatus)
    
    -- Прогрес
    if win.updateProgress ~= "" then
      gpu.setBackground(0xFFFFFF)
      gpu.set(x + 3, y + 10, win.updateProgress)
    end
    
    -- Кнопки
    local btnY = y + 12
    
    -- Check Updates Button
    gpu.setBackground(win.checkingUpdate and 0x808080 or 0xC0C0C0)
    gpu.fill(x + 2, btnY, 20, 3, " ")
    
    if not win.checkingUpdate then
      gpu.setForeground(0xFFFFFF)
      for i = 0, 19 do gpu.set(x + 2 + i, btnY, "▀") end
      gpu.setForeground(0x808080)
      for i = 0, 19 do gpu.set(x + 2 + i, btnY + 2, "▄") end
    end
    
    gpu.setForeground(0x000000)
    gpu.set(x + 6, btnY + 1, "Check Updates")
    
    -- Install Button
    btnY = btnY + 4
    gpu.setBackground(win.installingUpdate and 0x808080 or 0x00AA00)
    gpu.fill(x + 2, btnY, 20, 3, " ")
    
    if not win.installingUpdate then
      gpu.setForeground(0xFFFFFF)
      for i = 0, 19 do gpu.set(x + 2 + i, btnY, "▀") end
      gpu.setForeground(0x008800)
      for i = 0, 19 do gpu.set(x + 2 + i, btnY + 2, "▄") end
    end
    
    gpu.setForeground(0xFFFFFF)
    gpu.set(x + 5, btnY + 1, "Install Updates")
    
    -- Info
    gpu.setBackground(0xFFFFFF)
    gpu.setForeground(0x808080)
    gpu.set(x + 2, y + h - 2, "Note: Requires Internet Card")
    
  elseif win.selectedTab == 3 then
    -- About
    gpu.set(x + 2, y + 5, "FixOS 2000 Windowed Edition")
    gpu.set(x + 2, y + 7, "A Windows 2000 style operating system")
    gpu.set(x + 2, y + 8, "for OpenComputers mod in Minecraft")
    
    gpu.set(x + 2, y + 10, "(c) 2024 FixlutGames21")
    
    gpu.set(x + 2, y + 12, "Features:")
    gpu.set(x + 3, y + 13, "- Windowed GUI interface")
    gpu.set(x + 3, y + 14, "- Draggable windows")
    gpu.set(x + 3, y + 15, "- System update support")
    gpu.set(x + 3, y + 16, "- Calculator & Notepad")
    gpu.set(x + 3, y + 17, "- Custom BIOS")
  end
end

function settings.click(win, x, y, button)
  -- Вкладки
  local tabX = 0
  for i, tab in ipairs(win.tabs) do
    if x >= tabX and x < tabX + 13 and y >= 0 and y < 3 then
      win.selectedTab = i
      return true
    end
    tabX = tabX + 14
  end
  
  -- Кнопки оновлення
  if win.selectedTab == 2 and not win.checkingUpdate and not win.installingUpdate then
    -- Check Updates
    if x >= 2 and x < 22 and y >= 12 and y < 15 then
      settings.checkUpdates(win)
      return true
    end
    
    -- Install Updates
    if x >= 2 and x < 22 and y >= 16 and y < 19 then
      settings.installUpdates(win)
      return true
    end
  end
  
  return false
end

function settings.checkUpdates(win)
  win.checkingUpdate = true
  win.updateStatus = "Checking for updates..."
  win.updateProgress = ""
  
  -- Перевірка Internet Card
  local component = require("component")
  if not component.isAvailable("internet") then
    win.updateStatus = "Error: No Internet Card found"
    win.checkingUpdate = false
    return
  end
  
  local internet = component.internet
  local computer = require("computer")
  
  -- Завантаження version.txt з GitHub
  local url = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/version.txt"
  
  local handle = internet.request(url)
  if not handle then
    win.updateStatus = "Error: Connection failed"
    win.checkingUpdate = false
    return
  end
  
  local data = ""
  local deadline = computer.uptime() + 10
  
  while computer.uptime() < deadline do
    local chunk = handle.read(math.huge)
    if chunk then
      data = data .. chunk
    else
      break
    end
    require("os").sleep(0.05)
  end
  
  handle.close()
  
  -- Порівняння версій
  if data and #data > 0 then
    local remoteVersion = data:match("[%d%.]+")
    
    -- Читаємо локальну версію
    local localVersion = "1.0.0"
    local f = io.open("/version.txt", "r")
    if f then
      localVersion = f:read("*a"):match("[%d%.]+") or "1.0.0"
      f:close()
    end
    
    if remoteVersion and remoteVersion ~= localVersion then
      win.updateStatus = "Update available: v" .. remoteVersion
      win.updateProgress = "Your version: v" .. localVersion
    else
      win.updateStatus = "System is up to date (v" .. localVersion .. ")"
      win.updateProgress = ""
    end
  else
    win.updateStatus = "Error: Cannot check updates"
  end
  
  win.checkingUpdate = false
end

function settings.installUpdates(win)
  win.installingUpdate = true
  win.updateStatus = "Installing updates..."
  win.updateProgress = "Downloading files..."
  
  local component = require("component")
  local computer = require("computer")
  
  if not component.isAvailable("internet") then
    win.updateStatus = "Error: No Internet Card"
    win.installingUpdate = false
    return
  end
  
  local internet = component.internet
  local BASE_URL = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main"
  
  local files = {
    "system/desktop.lua",
    "system/windows.lua",
    "boot/init.lua"
  }
  
  -- Завантаження файлів
  for i, file in ipairs(files) do
    win.updateProgress = string.format("Downloading %d/%d: %s", i, #files, file)
    
    local url = BASE_URL .. "/" .. file
    local handle = internet.request(url)
    
    if handle then
      local data = ""
      local deadline = computer.uptime() + 30
      
      while computer.uptime() < deadline do
        local chunk = handle.read(math.huge)
        if chunk then
          data = data .. chunk
        else
          break
        end
        require("os").sleep(0.05)
      end
      
      handle.close()
      
      if #data > 0 then
        -- Запис файлу
        local f = io.open("/" .. file, "w")
        if f then
          f:write(data)
          f:close()
        end
      end
    end
    
    require("os").sleep(0.2)
  end
  
  -- Оновлення версії
  local vHandle = internet.request(BASE_URL .. "/version.txt")
  if vHandle then
    local vData = ""
    local deadline = computer.uptime() + 5
    while computer.uptime() < deadline do
      local chunk = vHandle.read(math.huge)
      if chunk then vData = vData .. chunk else break end
    end
    vHandle.close()
    
    if #vData > 0 then
      local f = io.open("/version.txt", "w")
      if f then f:write(vData); f:close() end
    end
  end
  
  win.updateStatus = "Update completed!"
  win.updateProgress = "Please restart computer to apply"
  win.installingUpdate = false
  
  require("os").sleep(2)
  win.updateStatus = "Ready"
  win.updateProgress = ""
end

-- ==============================================
-- Notepad Module
-- ==============================================
local notepad = {}

function notepad.init(win)
  win.lines = {""}
  win.cursorLine = 1
  win.cursorCol = 1
  win.scrollY = 0
  win.filename = "untitled.txt"
end

function notepad.draw(win, gpu, x, y, w, h)
  -- Фон
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  gpu.fill(x, y, w, h, " ")
  
  -- Статус бар
  gpu.setBackground(0xC0C0C0)
  gpu.fill(x, y + h - 1, w, 1, " ")
  gpu.set(x + 1, y + h - 1, "File: " .. win.filename)
  gpu.set(x + w - 15, y + h - 1, string.format("Ln %d, Col %d", win.cursorLine, win.cursorCol))
  
  -- Текст
  gpu.setBackground(0xFFFFFF)
  local visibleLines = h - 2
  for i = 1, visibleLines do
    local lineIdx = win.scrollY + i
    if win.lines[lineIdx] then
      local line = win.lines[lineIdx]
      if #line > w then line = line:sub(1, w) end
      gpu.set(x, y + i - 1, line)
    end
  end
  
  -- Курсор
  if win.cursorLine >= win.scrollY + 1 and win.cursorLine <= win.scrollY + visibleLines then
    local cy = y + (win.cursorLine - win.scrollY) - 1
    gpu.setForeground(0x000000)
    gpu.set(x + math.min(win.cursorCol - 1, w - 1), cy, "_")
  end
end

function notepad.key(win, char, code)
  if code == 28 then -- Enter
    local currentLine = win.lines[win.cursorLine]
    local leftPart = currentLine:sub(1, win.cursorCol - 1)
    local rightPart = currentLine:sub(win.cursorCol)
    
    win.lines[win.cursorLine] = leftPart
    table.insert(win.lines, win.cursorLine + 1, rightPart)
    win.cursorLine = win.cursorLine + 1
    win.cursorCol = 1
    return true
    
  elseif code == 14 then -- Backspace
    if win.cursorCol > 1 then
      local line = win.lines[win.cursorLine]
      win.lines[win.cursorLine] = line:sub(1, win.cursorCol - 2) .. line:sub(win.cursorCol)
      win.cursorCol = win.cursorCol - 1
      return true
    elseif win.cursorLine > 1 then
      local currentLine = win.lines[win.cursorLine]
      table.remove(win.lines, win.cursorLine)
      win.cursorLine = win.cursorLine - 1
      win.cursorCol = #win.lines[win.cursorLine] + 1
      win.lines[win.cursorLine] = win.lines[win.cursorLine] .. currentLine
      return true
    end
    
  elseif char and char >= 32 and char < 127 then
    local line = win.lines[win.cursorLine]
    win.lines[win.cursorLine] = line:sub(1, win.cursorCol - 1) .. 
                                 string.char(char) .. 
                                 line:sub(win.cursorCol)
    win.cursorCol = win.cursorCol + 1
    return true
  end
  
  return false
end

-- ==============================================
-- My Computer Module
-- ==============================================
local mycomp = {}

function mycomp.init(win)
  win.drives = {}
  local component = require("component")
  
  for addr in component.list("filesystem") do
    local proxy = component.proxy(addr)
    local label = "Unknown"
    pcall(function() label = proxy.getLabel() or addr:sub(1, 8) end)
    
    local total = 0
    local free = 0
    pcall(function() 
      total = proxy.spaceTotal()
      free = proxy.spaceUsed and (total - proxy.spaceUsed()) or 0
    end)
    
    table.insert(win.drives, {
      label = label,
      address = addr:sub(1, 8),
      total = total,
      free = free
    })
  end
end

function mycomp.draw(win, gpu, x, y, w, h)
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  gpu.fill(x, y, w, h, " ")
  
  gpu.set(x + 2, y + 1, "Computer Drives:")
  
  local yPos = y + 3
  for i, drive in ipairs(win.drives) do
    if yPos < y + h - 1 then
      -- Іконка та назва
      gpu.set(x + 2, yPos, "[HDD] " .. drive.label)
      
      -- Розмір
      local sizeText = "??"
      if drive.total > 1024*1024 then
        sizeText = string.format("%.1fMB", drive.total / (1024*1024))
      elseif drive.total > 1024 then
        sizeText = string.format("%.1fKB", drive.total / 1024)
      end
      
      gpu.set(x + 30, yPos, sizeText)
      
      -- Адреса
      gpu.setForeground(0x808080)
      gpu.set(x + 4, yPos + 1, drive.address)
      
      -- Прогрес бар використання
      if drive.total > 0 then
        local used = drive.total - drive.free
        local usedPct = math.floor((used / drive.total) * 20)
        
        gpu.setForeground(0x000000)
        gpu.set(x + 4, yPos + 2, "[")
        gpu.setForeground(0x00AA00)
        for k = 1, usedPct do
          gpu.set(x + 4 + k, yPos + 2, "■")
        end
        gpu.setForeground(0xCCCCCC)
        for k = usedPct + 1, 20 do
          gpu.set(x + 4 + k, yPos + 2, "□")
        end
        gpu.setForeground(0x000000)
        gpu.set(x + 25, yPos + 2, "]")
      end
      
      yPos = yPos + 4
    end
  end
end

-- Return all modules
return {
  calculator = calc,
  settings = settings,
  notepad = notepad,
  mycomputer = mycomp
}