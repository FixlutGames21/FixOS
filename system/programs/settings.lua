-- ==============================================
-- FixOS 2.0 - Settings Program (ПОКРАЩЕНО)
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
  win.remoteVersion = nil
  win.localVersion = "1.0.0"
  
  -- Завантаження локальної версії
  local ok, f = pcall(io.open, "/version.txt", "r")
  if ok and f then
    local content = f:read("*a")
    f:close()
    local version = content:match("[%d%.]+")
    if version then win.localVersion = version end
  end
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
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 5, "Operating System: FixOS 2.0")
    
    gpu.setForeground(0x000000)
    gpu.set(x + 2, y + 6, "Version: " .. win.localVersion)
    gpu.set(x + 2, y + 7, "Author: FixlutGames21")
    
    local component = require("component")
    local computer = require("computer")
    
    -- Memory
    local totalMem = computer.totalMemory()
    local freeMem = computer.freeMemory()
    local usedMem = totalMem - freeMem
    gpu.set(x + 2, y + 9, string.format("Memory: %dKB / %dKB used", 
            math.floor(usedMem/1024), math.floor(totalMem/1024)))
    
    -- Memory bar
    local memPct = usedMem / totalMem
    local barW = math.min(w - 6, 30)
    local filled = math.floor(barW * memPct)
    
    gpu.set(x + 3, y + 10, "[")
    gpu.setForeground(memPct > 0.8 and 0xFF0000 or 0x00AA00)
    for i = 1, filled do
      gpu.set(x + 3 + i, y + 10, "■")
    end
    gpu.setForeground(0xCCCCCC)
    for i = filled + 1, barW do
      gpu.set(x + 3 + i, y + 10, "□")
    end
    gpu.setForeground(0x000000)
    gpu.set(x + 4 + barW, y + 10, "]")
    
    -- Energy
    local energy = computer.energy()
    local maxEnergy = computer.maxEnergy()
    gpu.set(x + 2, y + 12, string.format("Energy: %d / %d", 
            math.floor(energy), math.floor(maxEnergy)))
    
    -- Components
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 14, "Components:")
    
    gpu.setForeground(0x000000)
    local cy = y + 15
    local count = 0
    for name in component.list() do
      if cy < y + h - 1 and count < 10 then
        local shortName = name:sub(1, w - 6)
        gpu.set(x + 3, cy, "• " .. shortName)
        cy = cy + 1
        count = count + 1
      end
    end
    
  elseif win.selectedTab == 2 then
    -- Update Tab
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 5, "System Update Manager")
    
    gpu.setBackground(0xE0E0E0)
    gpu.fill(x + 2, y + 7, w - 4, 3, " ")
    gpu.setForeground(0x000000)
    gpu.set(x + 3, y + 8, "Status: " .. win.updateStatus)
    
    if win.remoteVersion then
      gpu.setForeground(0x0000FF)
      gpu.set(x + 3, y + 9, "Latest: v" .. win.remoteVersion)
    end
    
    if win.updateProgress ~= "" then
      gpu.setBackground(0xFFFFFF)
      gpu.setForeground(0x808080)
      local progressText = win.updateProgress
      if #progressText > w - 6 then
        progressText = progressText:sub(1, w - 9) .. "..."
      end
      gpu.set(x + 3, y + 11, progressText)
    end
    
    local btnY = y + 13
    
    -- Check Updates Button
    gpu.setBackground(win.checkingUpdate and 0x808080 or 0x0080FF)
    gpu.fill(x + 2, btnY, 20, 3, " ")
    
    if not win.checkingUpdate then
      gpu.setForeground(0xFFFFFF)
      for i = 0, 19 do gpu.set(x + 2 + i, btnY, "▀") end
      gpu.setForeground(0x005580)
      for i = 0, 19 do gpu.set(x + 2 + i, btnY + 2, "▄") end
    end
    
    gpu.setForeground(0xFFFFFF)
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
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 5, "FixOS 2.0")
    
    gpu.setForeground(0x000000)
    gpu.set(x + 2, y + 7, "A Windows 2000 style OS")
    gpu.set(x + 2, y + 8, "for OpenComputers")
    
    gpu.set(x + 2, y + 10, "(c) 2024 FixlutGames21")
    
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 12, "Features:")
    
    gpu.setForeground(0x000000)
    gpu.set(x + 3, y + 13, "• Windowed interface")
    gpu.set(x + 3, y + 14, "• Modular programs")
    gpu.set(x + 3, y + 15, "• System updates")
    gpu.set(x + 3, y + 16, "• Easy to customize")
    
    gpu.setForeground(0x808080)
    gpu.set(x + 2, y + h - 2, "Version: " .. win.localVersion)
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
    if x >= 2 and x < 22 and y >= 13 and y < 16 then
      settings.checkUpdates(win)
      return true
    end
    
    if x >= 2 and x < 22 and y >= 17 and y < 20 then
      settings.installUpdates(win)
      return true
    end
  end
  
  return false
end

-- ПОКРАЩЕНА ФУНКЦІЯ ЗАВАНТАЖЕННЯ
local function downloadFileRetry(url, maxRetries)
  local component = require("component")
  local computer = require("computer")
  
  if not component.isAvailable("internet") then
    return nil, "No Internet Card"
  end
  
  local internet = component.internet
  maxRetries = maxRetries or 3
  
  for attempt = 1, maxRetries do
    local success, handle = pcall(internet.request, url)
    
    if success and handle then
      local result = {}
      local deadline = computer.uptime() + 30
      
      while computer.uptime() < deadline do
        local chunk = handle.read(math.huge)
        if chunk then
          table.insert(result, chunk)
        else
          break
        end
        require("os").sleep(0.05)
      end
      
      pcall(handle.close)
      local data = table.concat(result)
      
      if #data > 0 and not data:match("^%s*<!DOCTYPE") then
        return data
      end
    end
    
    if attempt < maxRetries then
      require("os").sleep(1)
    end
  end
  
  return nil, "Download failed after " .. maxRetries .. " attempts"
end

function settings.checkUpdates(win)
  win.checkingUpdate = true
  win.updateStatus = "Checking..."
  win.updateProgress = ""
  win.remoteVersion = nil
  
  local component = require("component")
  if not component.isAvailable("internet") then
    win.updateStatus = "Error: No Internet Card"
    win.checkingUpdate = false
    return
  end
  
  local url = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/version.txt"
  local data, err = downloadFileRetry(url, 3)
  
  if data and #data > 0 then
    local remoteVersion = data:match("[%d%.]+")
    
    if remoteVersion then
      win.remoteVersion = remoteVersion
      
      if remoteVersion ~= win.localVersion then
        win.updateStatus = "Update available!"
        win.updateProgress = "Current: v" .. win.localVersion
      else
        win.updateStatus = "Up to date"
        win.updateProgress = "v" .. win.localVersion
      end
    else
      win.updateStatus = "Parse error"
    end
  else
    win.updateStatus = "Check failed: " .. tostring(err)
  end
  
  win.checkingUpdate = false
end

function settings.installUpdates(win)
  win.installingUpdate = true
  win.updateStatus = "Installing..."
  win.updateProgress = "Preparing..."
  
  local component = require("component")
  local computer = require("computer")
  
  if not component.isAvailable("internet") then
    win.updateStatus = "Error: No Internet Card"
    win.installingUpdate = false
    return
  end
  
  local BASE_URL = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main"
  
  local files = {
    "boot/init.lua",
    "system/desktop.lua",
    "system/programs/calculator.lua",
    "system/programs/notepad.lua",
    "system/programs/settings.lua",
    "system/programs/mycomputer.lua",
    "version.txt"
  }
  
  local succeeded = 0
  local failed = 0
  
  for i, file in ipairs(files) do
    win.updateProgress = string.format("%d/%d: %s", i, #files, file)
    
    local url = BASE_URL .. "/" .. file
    local data, err = downloadFileRetry(url, 3)
    
    if data and #data > 0 then
      local ok, f = pcall(io.open, "/" .. file, "w")
      if ok and f then
        f:write(data)
        f:close()
        succeeded = succeeded + 1
      else
        failed = failed + 1
      end
    else
      failed = failed + 1
    end
    
    require("os").sleep(0.3)
  end
  
  if failed > 0 then
    win.updateStatus = string.format("Completed with %d errors", failed)
    win.updateProgress = string.format("%d/%d files updated", succeeded, #files)
  else
    win.updateStatus = "Complete!"
    win.updateProgress = "Restart to apply"
    
    -- Оновлення локальної версії
    if win.remoteVersion then
      win.localVersion = win.remoteVersion
    end
  end
  
  win.installingUpdate = false
  
  require("os").sleep(2)
  
  if failed == 0 then
    win.updateProgress = "Restart recommended"
  end
end

return settings