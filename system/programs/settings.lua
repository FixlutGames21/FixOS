-- ==============================================
-- FixOS 2.0 - Settings (ПОКРАЩЕНО)
-- system/programs/settings.lua
-- Додано: зміна роздільності, оновлення системи
-- ==============================================

local settings = {}

function settings.init(win)
  win.selectedTab = 1
  win.tabs = {"System", "Display", "Update", "About"}
  win.version = "2.0.0"
  win.updateStatus = "Ready"
  win.updateProgress = 0
  
  -- Завантаження версії
  local fs = component.proxy(computer.getBootAddress())
  if fs.exists("/version.txt") then
    local handle = fs.open("/version.txt", "r")
    if handle then
      local content = fs.read(handle, math.huge)
      fs.close(handle)
      if content then
        local ver = content:match("[%d%.]+")
        if ver then win.version = ver end
      end
    end
  end
  
  -- Доступні роздільності
  win.resolutions = {
    {w = 50, h = 16, name = "Small (50x16)"},
    {w = 80, h = 25, name = "Medium (80x25)"},
    {w = 100, h = 30, name = "Large (100x30)"},
    {w = 120, h = 40, name = "Extra Large (120x40)"},
    {w = 160, h = 50, name = "Maximum (160x50)"}
  }
  
  -- Поточна роздільність
  local gpu = component.proxy(component.list("gpu")())
  win.currentW, win.currentH = gpu.getResolution()
  win.maxW, win.maxH = gpu.maxResolution()
end

function settings.draw(win, gpu, x, y, w, h)
  -- Вкладки
  gpu.setBackground(0xC0C0C0)
  local tabX = x
  
  for i, tab in ipairs(win.tabs) do
    local isActive = (win.selectedTab == i)
    local tabW = 13
    
    gpu.setBackground(isActive and 0xFFFFFF or 0xA0A0A0)
    gpu.setForeground(0x000000)
    gpu.fill(tabX, y, tabW, 2, " ")
    
    if isActive then
      gpu.setForeground(0xFFFFFF)
      for k = 0, tabW - 1 do 
        gpu.set(tabX + k, y, "▀") 
      end
    end
    
    gpu.setForeground(0x000000)
    local labelX = tabX + math.floor((tabW - #tab) / 2)
    gpu.set(labelX, y + 1, tab)
    tabX = tabX + tabW + 1
  end
  
  -- Вміст вкладки
  gpu.setBackground(0xFFFFFF)
  gpu.fill(x, y + 3, w, h - 3, " ")
  gpu.setForeground(0x000000)
  
  -- ============ ВКЛАДКА SYSTEM ============
  if win.selectedTab == 1 then
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 5, "╔═══════════════════════════╗")
    gpu.set(x + 2, y + 6, "║  Operating System: FixOS  ║")
    gpu.set(x + 2, y + 7, "╚═══════════════════════════╝")
    
    gpu.setForeground(0x000000)
    gpu.set(x + 2, y + 9, "Version: " .. win.version)
    gpu.set(x + 2, y + 10, "Author: FixlutGames21")
    gpu.set(x + 2, y + 11, "Architecture: Lua 5.3")
    
    -- Пам'ять
    local totalMem = computer.totalMemory()
    local freeMem = computer.freeMemory()
    local usedMem = totalMem - freeMem
    
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 13, "═══ Memory Usage ═══")
    
    gpu.setForeground(0x000000)
    gpu.set(x + 2, y + 14, string.format("%dKB / %dKB used", 
            math.floor(usedMem / 1024), math.floor(totalMem / 1024)))
    
    -- Прогрес бар пам'яті (покращений)
    local memPct = usedMem / totalMem
    local barW = math.min(w - 6, 35)
    local filled = math.floor(barW * memPct)
    
    gpu.set(x + 3, y + 15, "╔")
    gpu.set(x + 4 + barW, y + 15, "╗")
    
    local barColor
    if memPct > 0.8 then
      barColor = 0xFF0000
    elseif memPct > 0.6 then
      barColor = 0xFFAA00
    else
      barColor = 0x00AA00
    end
    
    gpu.setForeground(barColor)
    for i = 1, filled do
      gpu.set(x + 3 + i, y + 15, "█")
    end
    
    gpu.setForeground(0xCCCCCC)
    for i = filled + 1, barW do
      gpu.set(x + 3 + i, y + 15, "░")
    end
    
    gpu.setForeground(0x000000)
    gpu.set(x + 6 + barW, y + 15, string.format(" %.0f%%", memPct * 100))
    
    -- Енергія
    local energy = computer.energy()
    local maxEnergy = computer.maxEnergy()
    
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 17, "═══ Power Status ═══")
    gpu.setForeground(0x000000)
    gpu.set(x + 2, y + 18, string.format("⚡ %d / %d", 
            math.floor(energy), math.floor(maxEnergy)))
  
  -- ============ ВКЛАДКА DISPLAY ============
  elseif win.selectedTab == 2 then
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 5, "╔══════════════════════════════╗")
    gpu.set(x + 2, y + 6, "║  Display Settings            ║")
    gpu.set(x + 2, y + 7, "╚══════════════════════════════╝")
    
    gpu.setForeground(0x000000)
    gpu.set(x + 2, y + 9, string.format("Current: %dx%d", win.currentW, win.currentH))
    gpu.set(x + 2, y + 10, string.format("Maximum: %dx%d", win.maxW, win.maxH))
    
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 12, "Available Resolutions:")
    
    -- Список роздільностей
    local startY = y + 13
    for i, res in ipairs(win.resolutions) do
      if res.w <= win.maxW and res.h <= win.maxH then
        local isCurrent = (res.w == win.currentW and res.h == win.currentH)
        
        -- Кнопка
        local btnY = startY + (i - 1) * 2
        if btnY < y + h - 2 then
          gpu.setBackground(isCurrent and 0x00AA00 or 0xD3D3D3)
          gpu.setForeground(0x000000)
          gpu.fill(x + 4, btnY, w - 8, 1, " ")
          
          local marker = isCurrent and "● " or "○ "
          gpu.set(x + 5, btnY, marker .. res.name)
          
          -- Зберігаємо координати для кліку
          win["res_" .. i] = {x = x + 4, y = btnY, w = w - 8, h = 1, res = res}
        end
      end
    end
    
    -- Інструкція
    gpu.setBackground(0xFFFFFF)
    gpu.setForeground(0x808080)
    gpu.set(x + 2, y + h - 2, "Click resolution to apply")
  
  -- ============ ВКЛАДКА UPDATE ============
  elseif win.selectedTab == 3 then
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 5, "╔══════════════════════════════╗")
    gpu.set(x + 2, y + 6, "║  System Update               ║")
    gpu.set(x + 2, y + 7, "╚══════════════════════════════╝")
    
    gpu.setForeground(0x000000)
    gpu.set(x + 2, y + 9, "Current Version: " .. win.version)
    gpu.set(x + 2, y + 10, "Update Server: GitHub")
    
    -- Статус оновлення
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 12, "═══ Update Status ═══")
    
    gpu.setForeground(0x000000)
    gpu.set(x + 2, y + 13, "Status: " .. win.updateStatus)
    
    -- Прогрес бар оновлення
    if win.updateProgress > 0 then
      local barW = w - 8
      local filled = math.floor(barW * win.updateProgress)
      
      gpu.set(x + 3, y + 15, "╔")
      gpu.setForeground(0x00AA00)
      for i = 1, filled do
        gpu.set(x + 3 + i, y + 15, "█")
      end
      gpu.setForeground(0xCCCCCC)
      for i = filled + 1, barW do
        gpu.set(x + 3 + i, y + 15, "░")
      end
      gpu.setForeground(0x000000)
      gpu.set(x + 4 + barW, y + 15, "╗")
      gpu.set(x + 3, y + 16, string.format("%.0f%% complete", win.updateProgress * 100))
    end
    
    -- Кнопка перевірки оновлень
    local btnY = y + h - 5
    gpu.setBackground(0x00AA00)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(x + 4, btnY, 20, 3, " ")
    
    -- 3D ефект кнопки
    gpu.setForeground(0xFFFFFF)
    for i = 0, 19 do gpu.set(x + 4 + i, btnY, "▀") end
    for i = 0, 2 do gpu.set(x + 4, btnY + i, "▌") end
    
    gpu.setForeground(0x404040)
    for i = 0, 19 do gpu.set(x + 4 + i, btnY + 2, "▄") end
    for i = 0, 2 do gpu.set(x + 23, btnY + i, "▐") end
    
    gpu.setForeground(0xFFFFFF)
    gpu.setBackground(0x00AA00)
    gpu.set(x + 8, btnY + 1, "⟳ Check Updates")
    
    win.updateButton = {x = x + 4, y = btnY, w = 20, h = 3}
    
    -- Інструкція
    gpu.setBackground(0xFFFFFF)
    gpu.setForeground(0x808080)
    gpu.set(x + 2, y + h - 2, "Requires Internet Card")
  
  -- ============ ВКЛАДКА ABOUT ============
  elseif win.selectedTab == 4 then
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 5, "╔══════════════════════════════╗")
    gpu.set(x + 2, y + 6, "║         FixOS 2.0            ║")
    gpu.set(x + 2, y + 7, "╚══════════════════════════════╝")
    
    gpu.setForeground(0x000000)
    gpu.set(x + 2, y + 9, "A Windows 2000 style OS")
    gpu.set(x + 2, y + 10, "for OpenComputers")
    
    gpu.set(x + 2, y + 12, "© 2024 FixlutGames21")
    gpu.set(x + 2, y + 13, "Licensed under MIT")
    
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 15, "═══ Features ═══")
    
    gpu.setForeground(0x000000)
    gpu.set(x + 3, y + 16, "✓ Windowed interface")
    gpu.set(x + 3, y + 17, "✓ Modular programs")
    gpu.set(x + 3, y + 18, "✓ Multiple applications")
    gpu.set(x + 3, y + 19, "✓ Easy to customize")
    gpu.set(x + 3, y + 20, "✓ Fast & optimized")
    
    gpu.setForeground(0x808080)
    gpu.set(x + 2, y + h - 2, "Version: " .. win.version)
  end
end

function settings.click(win, x, y, button)
  -- Клік по вкладках
  local tabX = 0
  for i, tab in ipairs(win.tabs) do
    if x >= tabX and x < tabX + 13 and y >= 0 and y < 3 then
      win.selectedTab = i
      return true
    end
    tabX = tabX + 14
  end
  
  -- Клік по роздільності (вкладка Display)
  if win.selectedTab == 2 then
    for i, res in ipairs(win.resolutions) do
      local btn = win["res_" .. i]
      if btn and x >= btn.x and x < btn.x + btn.w and 
         y >= btn.y and y < btn.y + btn.h then
        -- Застосовуємо роздільність
        local gpu = component.proxy(component.list("gpu")())
        gpu.setResolution(btn.res.w, btn.res.h)
        win.currentW, win.currentH = gpu.getResolution()
        
        -- Зберігаємо в конфіг
        local fs = component.proxy(computer.getBootAddress())
        local handle = fs.open("/settings.cfg", "w")
        if handle then
          fs.write(handle, string.format("resolution=%dx%d\n", win.currentW, win.currentH))
          fs.close(handle)
        end
        
        -- Перезавантаження системи для застосування
        computer.shutdown(true)
        return true
      end
    end
  end
  
  -- Клік по кнопці оновлення (вкладка Update)
  if win.selectedTab == 3 and win.updateButton then
    local btn = win.updateButton
    if x >= btn.x and x < btn.x + btn.w and 
       y >= btn.y and y < btn.y + btn.h then
      -- Запускаємо перевірку оновлень
      settings.checkUpdates(win)
      return true
    end
  end
  
  return false
end

function settings.checkUpdates(win)
  if not component.isAvailable("internet") then
    win.updateStatus = "Error: No Internet Card"
    return
  end
  
  win.updateStatus = "Checking..."
  win.updateProgress = 0.1
  
  -- Симуляція перевірки оновлень
  local internet = component.internet
  local url = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/version.txt"
  
  local ok, handle = pcall(internet.request, url)
  if not ok or not handle then
    win.updateStatus = "Error: Cannot connect"
    win.updateProgress = 0
    return
  end
  
  win.updateProgress = 0.3
  
  local result = {}
  local deadline = computer.uptime() + 10
  
  while computer.uptime() < deadline do
    local chunk = handle.read(math.huge)
    if chunk then
      table.insert(result, chunk)
    else
      break
    end
    os.sleep(0.05)
  end
  
  pcall(handle.close)
  
  win.updateProgress = 0.6
  
  local data = table.concat(result)
  if #data > 0 then
    local remoteVer = data:match("[%d%.]+")
    if remoteVer then
      win.updateProgress = 1.0
      if remoteVer == win.version then
        win.updateStatus = "Up to date!"
      else
        win.updateStatus = "Update available: v" .. remoteVer
      end
    else
      win.updateStatus = "Error: Invalid response"
      win.updateProgress = 0
    end
  else
    win.updateStatus = "Error: No data received"
    win.updateProgress = 0
  end
end

return settings