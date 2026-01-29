-- ==============================================
-- FixOS 2.0 - Settings Program
-- system/programs/settings.lua
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
    gpu.set(x + 2, y + 5, "Operating System: FixOS 2.0")
    gpu.set(x + 2, y + 6, "Version: 1.0.0")
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
        local shortName = name:sub(1, w - 6)
        gpu.set(x + 3, cy, "- " .. shortName)
        cy = cy + 1
      end
    end
    
  elseif win.selectedTab == 2 then
    -- Update Tab
    gpu.set(x + 2, y + 5, "System Update Manager")
    
    gpu.setBackground(0xE0E0E0)
    gpu.fill(x + 2, y + 7, w - 4, 2, " ")
    gpu.setForeground(0x000000)
    gpu.set(x + 3, y + 8, "Status: " .. win.updateStatus)
    
    if win.updateProgress ~= "" then
      gpu.setBackground(0xFFFFFF)
      local progressText = win.updateProgress
      if #progressText > w - 6 then
        progressText = progressText:sub(1, w - 9) .. "..."
      end
      gpu.set(x + 3, y + 10, progressText)
    end
    
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
    
    gpu.setBackground(0xFFFFFF)
    gpu.setForeground(0x808080)
    gpu.set(x + 2, y + h - 2, "Requires Internet Card")
    
  elseif win.selectedTab == 3 then
    -- About
    gpu.set(x + 2, y + 5, "FixOS 2.0")
    gpu.set(x + 2, y + 7, "A Windows 2000 style OS")
    gpu.set(x + 2, y + 8, "for OpenComputers")
    
    gpu.set(x + 2, y + 10, "(c) 2024 FixlutGames21")
    
    gpu.set(x + 2, y + 12, "Features:")
    gpu.set(x + 3, y + 13, "- Windowed interface")
    gpu.set(x + 3, y + 14, "- Modular programs")
    gpu.set(x + 3, y + 15, "- System updates")
    gpu.set(x + 3, y + 16, "- Easy to customize")
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
    if x >= 2 and x < 22 and y >= 12 and y < 15 then
      settings.checkUpdates(win)
      return true
    end
    
    if x >= 2 and x < 22 and y >= 16 and y < 19 then
      settings.installUpdates(win)
      return true
    end
  end
  
  return false
end

function settings.checkUpdates(win)
  win.checkingUpdate = true
  win.updateStatus = "Checking..."
  win.updateProgress = ""
  
  local component = require("component")
  if not component.isAvailable("internet") then
    win.updateStatus = "Error: No Internet Card"
    win.checkingUpdate = false
    return
  end
  
  local internet = component.internet
  local computer = require("computer")
  
  local url = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/version.txt"
  local handle = internet.request(url)
  if not handle then
    win.updateStatus = "Connection failed"
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
  
  if data and #data > 0 then
    local remoteVersion = data:match("[%d%.]+")
    local localVersion = "1.0.0"
    local f = io.open("/version.txt", "r")
    if f then
      localVersion = f:read("*a"):match("[%d%.]+") or "1.0.0"
      f:close()
    end
    
    if remoteVersion and remoteVersion ~= localVersion then
      win.updateStatus = "Update: v" .. remoteVersion
      win.updateProgress = "Current: v" .. localVersion
    else
      win.updateStatus = "Up to date (v" .. localVersion .. ")"
      win.updateProgress = ""
    end
  else
    win.updateStatus = "Check failed"
  end
  
  win.checkingUpdate = false
end

function settings.installUpdates(win)
  win.installingUpdate = true
  win.updateStatus = "Installing..."
  win.updateProgress = "Downloading..."
  
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
    "boot/init.lua",
    "system/desktop.lua",
    "system/programs/calculator.lua",
    "system/programs/notepad.lua",
    "system/programs/settings.lua",
    "system/programs/mycomputer.lua"
  }
  
  for i, file in ipairs(files) do
    win.updateProgress = string.format("%d/%d: %s", i, #files, file)
    
    local url = BASE_URL .. "/" .. file
    local handle = internet.request(url)
    
    if handle then
      local data = ""
      local deadline = computer.uptime() + 30
      
      while computer.uptime() < deadline do
        local chunk = handle.read(math.huge)
        if chunk then data = data .. chunk else break end
        require("os").sleep(0.05)
      end
      
      handle.close()
      
      if #data > 0 then
        local f = io.open("/" .. file, "w")
        if f then f:write(data); f:close() end
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
  
  win.updateStatus = "Complete!"
  win.updateProgress = "Restart to apply"
  win.installingUpdate = false
  
  require("os").sleep(2)
  win.updateStatus = "Ready"
  win.updateProgress = ""
end

return settings