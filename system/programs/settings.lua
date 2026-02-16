-- ==============================================
-- FixOS 3.0 - Settings (ПОВНІСТЮ ПЕРЕПИСАНО)
-- system/programs/settings.lua
-- ==============================================

local settings = {}

function settings.init(win)
  win.selectedTab = 1
  win.tabs = {"System", "Display", "Update", "About"}
  win.version = "3.0.0"
  win.updateStatus = "Ready"
  win.updateProgress = 0
  win.scrollY = 0
  win.maxScrollY = 0
  
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
  
  -- Роздільності
  win.resolutions = {
    {w = 50, h = 16, name = "Tiny", desc = "Very small"},
    {w = 80, h = 25, name = "Standard", desc = "Recommended"},
    {w = 100, h = 30, name = "Large", desc = "Big screen"},
    {w = 120, h = 40, name = "Huge", desc = "Very large"},
    {w = 160, h = 50, name = "Maximum", desc = "Top tier GPU"}
  }
  
  -- Поточна роздільність
  local gpu = component.proxy(component.list("gpu")())
  win.currentW, win.currentH = gpu.getResolution()
  win.maxW, win.maxH = gpu.maxResolution()
  
  -- Позиції UI елементів (відносні від початку контенту)
  win.uiElements = {}
end

-- Windows-style група
local function drawGroup(gpu, x, y, w, h, title)
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x808080)
  
  -- Верхня лінія з заголовком
  local titleLen = #title + 2
  local leftLen = 3
  
  gpu.set(x, y, "┌" .. string.rep("─", leftLen))
  gpu.set(x + leftLen + titleLen + 1, y, string.rep("─", w - leftLen - titleLen - 2) .. "┐")
  
  gpu.setForeground(0x000080)
  gpu.set(x + leftLen + 1, y, " " .. title .. " ")
  
  -- Бокові
  gpu.setForeground(0x808080)
  for i = 1, h - 2 do
    gpu.set(x, y + i, "│")
    gpu.set(x + w - 1, y + i, "│")
  end
  
  -- Низ
  gpu.set(x, y + h - 1, "└" .. string.rep("─", w - 2) .. "┘")
end

-- Прогрес бар
local function drawProgressBar(gpu, x, y, w, percent, color)
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x808080)
  gpu.set(x, y, "[")
  gpu.set(x + w - 1, y, "]")
  
  gpu.setBackground(0xC0C0C0)
  gpu.fill(x + 1, y, w - 2, 1, " ")
  
  local filled = math.floor((w - 2) * percent)
  if filled > 0 then
    gpu.setBackground(color or 0x0000AA)
    gpu.fill(x + 1, y, filled, 1, " ")
  end
  
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  local pctText = string.format("%d%%", math.floor(percent * 100))
  local pctX = x + math.floor((w - #pctText) / 2)
  gpu.set(pctX, y, pctText)
end

-- Кнопка
local function drawButton(gpu, x, y, w, label, enabled)
  local bgColor = enabled and 0xC0C0C0 or 0xA0A0A0
  
  gpu.setBackground(bgColor)
  gpu.fill(x, y, w, 3, " ")
  
  -- 3D рамка
  gpu.setForeground(0xFFFFFF)
  for i = 0, w - 1 do gpu.set(x + i, y, "▀") end
  for i = 0, 2 do gpu.set(x, y + i, "▌") end
  
  gpu.setForeground(0x404040)
  for i = 0, w - 1 do gpu.set(x + i, y + 2, "▄") end
  for i = 0, 2 do gpu.set(x + w - 1, y + i, "▐") end
  
  -- Текст
  gpu.setForeground(enabled and 0x000000 or 0x606060)
  gpu.setBackground(bgColor)
  local tx = x + math.floor((w - #label) / 2)
  gpu.set(tx, y + 1, label)
end

-- Scrollbar
local function drawScrollbar(gpu, x, y, h, scrollY, maxScrollY)
  if maxScrollY <= 0 then return end
  
  -- Трек
  gpu.setBackground(0xC0C0C0)
  gpu.fill(x, y, 1, h, "░")
  
  -- Кнопки
  gpu.setForeground(0x000000)
  gpu.set(x, y, "▲")
  gpu.set(x, y + h - 1, "▼")
  
  -- Повзунок
  local thumbH = math.max(2, math.floor(h * 0.2))
  local trackH = h - thumbH - 2
  if trackH > 0 then
    local thumbY = y + 1 + math.floor((scrollY / maxScrollY) * trackH)
    
    gpu.setBackground(0x808080)
    gpu.fill(x, thumbY, 1, thumbH, "█")
  end
end

function settings.draw(win, gpu, x, y, w, h)
  local contentH = h - 3
  local scrollbarW = 1
  local contentW = w - scrollbarW - 1
  
  -- Вкладки
  gpu.setBackground(0xC0C0C0)
  local tabX = x
  
  for i, tab in ipairs(win.tabs) do
    local isActive = (win.selectedTab == i)
    local tabW = 13
    
    if isActive then
      gpu.setBackground(0xFFFFFF)
      gpu.fill(tabX, y, tabW, 3, " ")
      
      gpu.setForeground(0x808080)
      gpu.set(tabX, y, "╔" .. string.rep("═", tabW - 2) .. "╗")
      gpu.set(tabX, y + 1, "║")
      gpu.set(tabX + tabW - 1, y + 1, "║")
      
      gpu.setForeground(0x000000)
      gpu.setBackground(0xFFFFFF)
    else
      gpu.setBackground(0xD0D0D0)
      gpu.fill(tabX, y + 1, tabW, 2, " ")
      
      gpu.setForeground(0x808080)
      gpu.set(tabX, y + 1, "┌" .. string.rep("─", tabW - 2) .. "┐")
      gpu.set(tabX, y + 2, "│")
      gpu.set(tabX + tabW - 1, y + 2, "│")
      
      gpu.setForeground(0x606060)
      gpu.setBackground(0xD0D0D0)
    end
    
    local labelX = tabX + math.floor((tabW - #tab) / 2)
    gpu.set(labelX, y + (isActive and 1 or 2), tab)
    tabX = tabX + tabW + 1
  end
  
  -- Контент area
  gpu.setBackground(0xFFFFFF)
  gpu.fill(x, y + 3, contentW, contentH, " ")
  
  -- Рамка
  gpu.setForeground(0x808080)
  gpu.set(x, y + 2, "╔" .. string.rep("═", contentW - 1) .. "╗")
  for i = 1, contentH - 1 do
    gpu.set(x, y + 2 + i, "║")
    gpu.set(x + contentW, y + 2 + i, "║")
  end
  gpu.set(x, y + 2 + contentH, "╚" .. string.rep("═", contentW - 1) .. "╝")
  
  -- Scrollbar
  drawScrollbar(gpu, x + w - 1, y + 3, contentH, win.scrollY, win.maxScrollY)
  
  -- Контент вкладки
  local cy = y + 4 - win.scrollY
  local cx = x + 2
  local cw = contentW - 4
  
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  
  -- Очищаємо UI елементи
  win.uiElements = {}
  
  local function isVisible(elemY)
    return elemY >= y + 3 and elemY < y + 3 + contentH
  end
  
  -- ===== SYSTEM TAB =====
  if win.selectedTab == 1 then
    if isVisible(cy) then
      gpu.setForeground(0x000080)
      gpu.set(cx, cy, "System Information")
    end
    cy = cy + 2
    
    -- OS Group
    if cy >= y + 3 - 5 then
      drawGroup(gpu, cx, cy, cw, 5, "Operating System")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, "Name:")
      gpu.setForeground(0x000080)
      gpu.set(cx + 15, cy, "FixOS")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, "Version:")
      gpu.setForeground(0x000080)
      gpu.set(cx + 15, cy, win.version)
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, "Platform:")
      gpu.setForeground(0x000080)
      gpu.set(cx + 15, cy, "OpenComputers")
    end
    cy = cy + 3
    
    -- Memory Group
    local totalMem = computer.totalMemory()
    local freeMem = computer.freeMemory()
    local usedMem = totalMem - freeMem
    local memPct = usedMem / totalMem
    
    if cy >= y + 3 - 6 then
      drawGroup(gpu, cx, cy, cw, 6, "Memory")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, string.format("Total: %d KB", math.floor(totalMem / 1024)))
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.set(cx + 2, cy, string.format("Used:  %d KB", math.floor(usedMem / 1024)))
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.set(cx + 2, cy, string.format("Free:  %d KB", math.floor(freeMem / 1024)))
    end
    cy = cy + 1
    
    if isVisible(cy) then
      local barColor = memPct > 0.8 and 0xFF0000 or (memPct > 0.6 and 0xFFAA00 or 0x00AA00)
      drawProgressBar(gpu, cx + 2, cy, cw - 4, memPct, barColor)
    end
    cy = cy + 3
    
    -- Energy Group
    local energy = computer.energy()
    local maxEnergy = computer.maxEnergy()
    local energyPct = energy / maxEnergy
    
    if cy >= y + 3 - 5 then
      drawGroup(gpu, cx, cy, cw, 5, "Power Status")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, string.format("Energy: %d / %d", math.floor(energy), math.floor(maxEnergy)))
    end
    cy = cy + 1
    
    if isVisible(cy) then
      drawProgressBar(gpu, cx + 2, cy, cw - 4, energyPct, 0xFFAA00)
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x606060)
      local uptime = math.floor(computer.uptime())
      gpu.set(cx + 2, cy, string.format("Uptime: %d seconds", uptime))
    end
    
    win.maxScrollY = math.max(0, cy - (y + 3 + contentH) + 5)
    
  -- ===== DISPLAY TAB =====
  elseif win.selectedTab == 2 then
    if isVisible(cy) then
      gpu.setForeground(0x000080)
      gpu.set(cx, cy, "Display Settings")
    end
    cy = cy + 2
    
    -- Current Resolution
    if cy >= y + 3 - 4 then
      drawGroup(gpu, cx, cy, cw, 4, "Current Resolution")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, string.format("Active: %dx%d pixels", win.currentW, win.currentH))
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x606060)
      gpu.set(cx + 2, cy, string.format("Maximum: %dx%d pixels", win.maxW, win.maxH))
    end
    cy = cy + 3
    
    -- Available Resolutions
    if isVisible(cy) then
      gpu.setForeground(0x000080)
      gpu.set(cx, cy, "Available Resolutions:")
    end
    cy = cy + 2
    
    for i, res in ipairs(win.resolutions) do
      if res.w <= win.maxW and res.h <= win.maxH then
        local isCurrent = (res.w == win.currentW and res.h == win.currentH)
        
        if isVisible(cy) then
          -- Radio button
          gpu.setForeground(0x000000)
          gpu.set(cx + 2, cy, isCurrent and "◉" or "○")
          
          -- Name
          gpu.setForeground(isCurrent and 0x0000AA or 0x000000)
          gpu.set(cx + 5, cy, string.format("%s (%dx%d)", res.name, res.w, res.h))
          
          -- Зберігаємо для кліку
          table.insert(win.uiElements, {
            type = "resolution",
            x = win.x + cx,
            y = cy,
            w = cw - 4,
            h = 2,
            res = res
          })
        end
        
        if isVisible(cy + 1) then
          gpu.setForeground(0x808080)
          gpu.set(cx + 8, cy + 1, res.desc)
        end
        
        cy = cy + 3
      end
    end
    
    if isVisible(cy) then
      gpu.setForeground(0x606060)
      gpu.set(cx, cy, "Click to apply and restart")
    end
    
    win.maxScrollY = math.max(0, cy - (y + 3 + contentH) + 5)
    
  -- ===== UPDATE TAB =====
  elseif win.selectedTab == 3 then
    if isVisible(cy) then
      gpu.setForeground(0x000080)
      gpu.set(cx, cy, "System Update")
    end
    cy = cy + 2
    
    -- Version Info
    if cy >= y + 3 - 4 then
      drawGroup(gpu, cx, cy, cw, 4, "Version Information")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, "Installed: FixOS " .. win.version)
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x606060)
      gpu.set(cx + 2, cy, "Repository: GitHub/FixlutGames21")
    end
    cy = cy + 3
    
    -- Update Status
    if cy >= y + 3 - 6 then
      drawGroup(gpu, cx, cy, cw, 6, "Update Status")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, "Status: " .. win.updateStatus)
    end
    cy = cy + 2
    
    if win.updateProgress > 0 and isVisible(cy) then
      drawProgressBar(gpu, cx + 2, cy, cw - 4, win.updateProgress, 0x00AA00)
      cy = cy + 1
    end
    cy = cy + 2
    
    -- Update button
    if isVisible(cy) then
      local enabled = component.isAvailable("internet")
      drawButton(gpu, cx + 2, cy, 20, "Check Updates", enabled)
      
      table.insert(win.uiElements, {
        type = "button",
        action = "update",
        x = win.x + cx + 2,
        y = cy,
        w = 20,
        h = 3
      })
    end
    cy = cy + 4
    
    if isVisible(cy) then
      gpu.setForeground(0x808080)
      local text = component.isAvailable("internet") and "Internet Card ready" or "⚠ Internet Card required"
      gpu.set(cx, cy, text)
    end
    
    win.maxScrollY = math.max(0, cy - (y + 3 + contentH) + 5)
    
  -- ===== ABOUT TAB =====
  elseif win.selectedTab == 4 then
    -- Logo
    if isVisible(cy) then
      gpu.setForeground(0x0000AA)
      gpu.set(cx + math.floor(cw/2) - 5, cy, "╔═══════╗")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.set(cx + math.floor(cw/2) - 5, cy, "║ FixOS ║")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.set(cx + math.floor(cw/2) - 5, cy, "║  3.0  ║")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.set(cx + math.floor(cw/2) - 5, cy, "╚═══════╝")
    end
    cy = cy + 2
    
    -- Version
    if isVisible(cy) then
      gpu.setForeground(0x000000)
      local verText = "Version " .. win.version .. " - SUPER EDITION"
      gpu.set(cx + math.floor((cw - #verText) / 2), cy, verText)
    end
    cy = cy + 2
    
    -- Description
    if isVisible(cy) then
      gpu.setForeground(0x606060)
      local desc = "Professional OS for OpenComputers"
      gpu.set(cx + math.floor((cw - #desc) / 2), cy, desc)
    end
    cy = cy + 3
    
    -- Credits
    if cy >= y + 3 - 4 then
      drawGroup(gpu, cx, cy, cw, 4, "Credits")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, "© 2024-2026 FixlutGames21")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x606060)
      gpu.set(cx + 2, cy, "Licensed under MIT")
    end
    cy = cy + 3
    
    -- Features
    if cy >= y + 3 - 10 then
      drawGroup(gpu, cx, cy, cw, 10, "Features")
    end
    cy = cy + 1
    
    local features = {
      "✓ Windows 2000 style UI",
      "✓ File Explorer",
      "✓ Terminal with commands",
      "✓ Multiple programs",
      "✓ Fast rendering engine",
      "✓ Icon system",
      "✓ Customizable resolution",
      "✓ Online updates"
    }
    
    for _, feature in ipairs(features) do
      if isVisible(cy) then
        gpu.setForeground(0x00AA00)
        gpu.set(cx + 2, cy, feature)
      end
      cy = cy + 1
    end
    
    win.maxScrollY = math.max(0, cy - (y + 3 + contentH) + 5)
  end
end

function settings.click(win, clickX, clickY, button)
  -- Клік по вкладках
  local tabX = win.x
  for i, tab in ipairs(win.tabs) do
    if clickY >= win.y and clickY <= win.y + 2 and
       clickX >= tabX and clickX < tabX + 13 then
      win.selectedTab = i
      win.scrollY = 0
      return true
    end
    tabX = tabX + 14
  end
  
  -- Клік по scrollbar
  local scrollbarX = win.x + win.w - 2
  if clickX == scrollbarX and clickY >= win.y + 3 and clickY < win.y + win.h - 1 then
    local relY = clickY - (win.y + 3)
    local contentH = win.h - 6
    
    if relY == 0 then
      win.scrollY = math.max(0, win.scrollY - 1)
      return true
    elseif relY == contentH - 1 then
      win.scrollY = math.min(win.maxScrollY, win.scrollY + 1)
      return true
    else
      if win.maxScrollY > 0 then
        local pct = relY / contentH
        win.scrollY = math.floor(win.maxScrollY * pct)
      end
      return true
    end
  end
  
  -- Клік по UI елементах
  for _, elem in ipairs(win.uiElements) do
    if clickX >= elem.x and clickX < elem.x + elem.w and
       clickY >= elem.y and clickY < elem.y + elem.h then
      
      if elem.type == "resolution" then
        -- Apply resolution
        local gpu = component.proxy(component.list("gpu")())
        gpu.setResolution(elem.res.w, elem.res.h)
        
        -- Save config
        local fs = component.proxy(computer.getBootAddress())
        local handle = fs.open("/settings.cfg", "w")
        if handle then
          fs.write(handle, string.format("resolution=%dx%d\n", elem.res.w, elem.res.h))
          fs.close(handle)
        end
        
        computer.shutdown(true)
        return true
        
      elseif elem.type == "button" and elem.action == "update" then
        settings.checkUpdates(win)
        return true
      end
    end
  end
  
  return false
end

function settings.key(win, char, code)
  if code == 201 then -- Page Up
    win.scrollY = math.max(0, win.scrollY - 5)
    return true
  elseif code == 209 then -- Page Down
    win.scrollY = math.min(win.maxScrollY, win.scrollY + 5)
    return true
  elseif code == 199 then -- Home
    win.scrollY = 0
    return true
  elseif code == 207 then -- End
    win.scrollY = win.maxScrollY
    return true
  elseif code == 200 then -- Arrow Up
    win.scrollY = math.max(0, win.scrollY - 1)
    return true
  elseif code == 208 then -- Arrow Down
    win.scrollY = math.min(win.maxScrollY, win.scrollY + 1)
    return true
  end
  
  return false
end

function settings.scroll(win, direction)
  if direction > 0 then
    win.scrollY = math.max(0, win.scrollY - 3)
  else
    win.scrollY = math.min(win.maxScrollY, win.scrollY + 3)
  end
  return true
end

function settings.checkUpdates(win)
  if not component.isAvailable("internet") then
    win.updateStatus = "Error: No Internet Card"
    return
  end
  
  win.updateStatus = "Checking..."
  win.updateProgress = 0.1
  
  local internet = component.internet
  local url = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/version.txt"
  
  local ok, handle = pcall(internet.request, url)
  if not ok or not handle then
    win.updateStatus = "Error: Cannot connect"
    win.updateProgress = 0
    return
  end
  
  win.updateProgress = 0.5
  
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
  
  local data = table.concat(result)
  if #data > 0 then
    local remoteVer = data:match("[%d%.]+")
    if remoteVer then
      win.updateProgress = 1.0
      if remoteVer == win.version then
        win.updateStatus = "✓ System is up to date!"
      else
        win.updateStatus = "⬇ Update available: v" .. remoteVer
      end
    else
      win.updateStatus = "Error: Invalid response"
      win.updateProgress = 0
    end
  else
    win.updateStatus = "Error: No data"
    win.updateProgress = 0
  end
end

return settings
