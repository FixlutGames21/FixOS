-- ==============================================
-- FixOS 2.0 - Settings (ВИПРАВЛЕНО)
-- system/programs/settings.lua
-- ==============================================

local settings = {}

-- Ініціалізація
function settings.init(win)
  win.selectedTab = 1
  win.tabs = {"System", "About"}
  win.version = "2.0.0"
  
  -- Завантаження версії з файлу
  local fs = component.proxy(computer.getBootAddress())
  if fs.exists("/version.txt") then
    local handle = fs.open("/version.txt", "r")
    if handle then
      local content = fs.read(handle, math.huge)
      fs.close(handle)
      
      if content then
        local ver = content:match("[%d%.]+")
        if ver then
          win.version = ver
        end
      end
    end
  end
end

-- Малювання
function settings.draw(win, gpu, x, y, w, h)
  -- Вкладки
  gpu.setBackground(0xC0C0C0)
  local tabX = x
  
  for i, tab in ipairs(win.tabs) do
    local isActive = (win.selectedTab == i)
    
    gpu.setBackground(isActive and 0xFFFFFF or 0xA0A0A0)
    gpu.setForeground(0x000000)
    gpu.fill(tabX, y, 13, 2, " ")
    
    -- Верхня лінія для активної вкладки
    if isActive then
      gpu.setForeground(0xFFFFFF)
      for k = 0, 12 do 
        gpu.set(tabX + k, y, "▀") 
      end
    end
    
    gpu.setForeground(0x000000)
    gpu.set(tabX + 3, y + 1, tab)
    tabX = tabX + 14
  end
  
  -- Вміст вкладки
  gpu.setBackground(0xFFFFFF)
  gpu.fill(x, y + 3, w, h - 3, " ")
  gpu.setForeground(0x000000)
  
  if win.selectedTab == 1 then
    -- Вкладка System Info
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 5, "Operating System: FixOS 2.0")
    
    gpu.setForeground(0x000000)
    gpu.set(x + 2, y + 6, "Version: " .. win.version)
    gpu.set(x + 2, y + 7, "Author: FixlutGames21")
    
    -- Пам'ять
    local totalMem = computer.totalMemory()
    local freeMem = computer.freeMemory()
    local usedMem = totalMem - freeMem
    
    gpu.set(x + 2, y + 9, string.format("Memory: %dKB / %dKB used", 
            math.floor(usedMem / 1024), math.floor(totalMem / 1024)))
    
    -- Прогрес бар пам'яті
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
    
    gpu.set(x + 6 + barW, y + 10, string.format(" %.0f%%", memPct * 100))
    
    -- Енергія
    local energy = computer.energy()
    local maxEnergy = computer.maxEnergy()
    
    gpu.set(x + 2, y + 12, string.format("Energy: %d / %d", 
            math.floor(energy), math.floor(maxEnergy)))
    
    -- Список компонентів
    gpu.setForeground(0x000080)
    gpu.set(x + 2, y + 14, "Components:")
    
    gpu.setForeground(0x000000)
    local cy = y + 15
    local count = 0
    
    for name, addr in component.list() do
      if cy < y + h - 1 and count < 5 then
        local shortName = name
        if #shortName > w - 6 then
          shortName = shortName:sub(1, w - 9) .. "..."
        end
        
        gpu.set(x + 3, cy, "• " .. shortName)
        cy = cy + 1
        count = count + 1
      end
    end
    
  elseif win.selectedTab == 2 then
    -- Вкладка About
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
    gpu.set(x + 3, y + 15, "• Multiple applications")
    gpu.set(x + 3, y + 16, "• Easy to customize")
    
    gpu.setForeground(0x808080)
    gpu.set(x + 2, y + h - 2, "Version: " .. win.version)
  end
end

-- Обробка кліку
function settings.click(win, x, y, button)
  -- Перевірка кліку по вкладках
  local tabX = 0
  
  for i, tab in ipairs(win.tabs) do
    if x >= tabX and x < tabX + 13 and y >= 0 and y < 3 then
      win.selectedTab = i
      return true
    end
    tabX = tabX + 14
  end
  
  return false
end

return settings