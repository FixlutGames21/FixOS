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
