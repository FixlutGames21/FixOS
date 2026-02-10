-- ==============================================
-- FixOS 2.1.1 - Settings (WINDOWS STYLE + SCROLLBAR)
-- system/programs/settings.lua
-- ==============================================

local settings = {}

function settings.init(win)
  win.selectedTab = 1
  win.tabs = {"System", "Display", "Update", "About"}
  win.version = "2.1.1"
  win.updateStatus = "Ready"
  win.updateProgress = 0
  win.scrollY = 0  -- Позиція прокрутки
  win.maxScrollY = 0  -- Максимальна прокрутка
  
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
    {w = 50, h = 16, name = "Small", desc = "Low-end systems"},
    {w = 80, h = 25, name = "Medium", desc = "Recommended"},
    {w = 100, h = 30, name = "Large", desc = "High resolution"},
    {w = 120, h = 40, name = "Extra Large", desc = "Advanced"},
    {w = 160, h = 50, name = "Maximum", desc = "Top tier GPU"}
  }
  
  -- Поточна роздільність
  local gpu = component.proxy(component.list("gpu")())
  win.currentW, win.currentH = gpu.getResolution()
  win.maxW, win.maxH = gpu.maxResolution()
end

-- Малювання Windows-style групи
local function drawGroup(gpu, x, y, w, h, title)
  -- Рамка групи (3D)
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x808080)
  
  -- Верхня лінія (з розривом для заголовку)
  local titleLen = #title + 2
  local leftLen = 3
  
  gpu.set(x, y, "┌" .. string.rep("─", leftLen))
  gpu.set(x + leftLen + titleLen + 1, y, string.rep("─", w - leftLen - titleLen - 2) .. "┐")
  
  -- Заголовок
  gpu.setForeground(0x000080)
  gpu.set(x + leftLen + 1, y, " " .. title .. " ")
  
  -- Бокові лінії
  gpu.setForeground(0x808080)
  for i = 1, h - 2 do
    gpu.set(x, y + i, "│")
    gpu.set(x + w - 1, y + i, "│")
  end
  
  -- Нижня лінія
  gpu.set(x, y + h - 1, "└" .. string.rep("─", w - 2) .. "┘")
end

-- Малювання прогрес бару (Windows-style)
local function drawProgressBar(gpu, x, y, w, percent, color)
  -- Рамка
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x808080)
  gpu.set(x, y, "▐")
  gpu.set(x + w - 1, y, "▌")
  
  -- Фон бару
  gpu.setBackground(0xC0C0C0)
  gpu.fill(x + 1, y, w - 2, 1, " ")
  
  -- Заповнення
  local filled = math.floor((w - 2) * percent)
  if filled > 0 then
    gpu.setBackground(color or 0x0000AA)
    gpu.fill(x + 1, y, filled, 1, " ")
  end
  
  -- Відсоток
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  local pctText = string.format("%d%%", math.floor(percent * 100))
  local pctX = x + math.floor((w - #pctText) / 2)
  gpu.set(pctX, y, pctText)
end

-- Малювання кнопки (Windows-style)
local function drawButton(gpu, x, y, w, label, enabled, pressed)
  local bgColor = enabled and 0xC0C0C0 or 0xA0A0A0
  
  gpu.setBackground(bgColor)
  gpu.fill(x, y, w, 3, " ")
  
  if not pressed then
    -- Підняті краї
    gpu.setForeground(0xFFFFFF)
    gpu.fill(x, y, w, 1, "▀")
    gpu.fill(x, y, 1, 3, "▌")
    
    gpu.setForeground(0x404040)
    gpu.fill(x, y + 2, w, 1, "▄")
    gpu.fill(x + w - 1, y, 1, 3, "▐")
  else
    -- Натиснуті краї
    gpu.setForeground(0x404040)
    gpu.fill(x, y, w, 1, "▀")
    gpu.fill(x, y, 1, 3, "▌")
    
    gpu.setForeground(0xFFFFFF)
    gpu.fill(x, y + 2, w, 1, "▄")
    gpu.fill(x + w - 1, y, 1, 3, "▐")
  end
  
  -- Текст
  gpu.setForeground(enabled and 0x000000 or 0x808080)
  gpu.setBackground(bgColor)
  local tx = x + math.floor((w - #label) / 2)
  gpu.set(tx, y + 1, label)
end

-- Малювання scrollbar
local function drawScrollbar(gpu, x, y, h, scrollY, maxScrollY)
  if maxScrollY <= 0 then return end
  
  -- Трек scrollbar
  gpu.setBackground(0xC0C0C0)
  gpu.fill(x, y, 1, h, "░")
  
  -- Розмір та позиція thumb
  local thumbH = math.max(2, math.floor(h * 0.3))
  local trackH = h - thumbH
  local thumbY = y + math.floor((scrollY / maxScrollY) * trackH)
  
  -- Thumb (повзунок)
  gpu.setBackground(0x808080)
  gpu.fill(x, thumbY, 1, thumbH, "█")
  
  -- Кнопки вгору/вниз
  gpu.setBackground(0xC0C0C0)
  gpu.setForeground(0x000000)
  gpu.set(x, y, "▲")
  gpu.set(x, y + h - 1, "▼")
end

function settings.draw(win, gpu, x, y, w, h)
  local contentH = h - 3  -- Висота контенту
  local scrollbarW = 1    -- Ширина scrollbar
  local contentW = w - scrollbarW - 1  -- Ширина контенту
  
  -- Вкладки (як у Windows)
  gpu.setBackground(0xC0C0C0)
  local tabX = x
  
  for i, tab in ipairs(win.tabs) do
    local isActive = (win.selectedTab == i)
    local tabW = 13
    
    -- Фон вкладки
    if isActive then
      gpu.setBackground(0xFFFFFF)
      gpu.fill(tabX, y, tabW, 3, " ")
      
      -- Рамка активної вкладки
      gpu.setForeground(0x808080)
      gpu.set(tabX, y, "╔" .. string.rep("═", tabW - 2) .. "╗")
      gpu.set(tabX, y + 1, "║")
      gpu.set(tabX + tabW - 1, y + 1, "║")
      -- Низ злитий з контентом
      
      gpu.setForeground(0x000000)
      gpu.setBackground(0xFFFFFF)
    else
      gpu.setBackground(0xD0D0D0)
      gpu.fill(tabX, y + 1, tabW, 2, " ")
      
      -- Рамка неактивної вкладки
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
  
  -- Фон контенту
  gpu.setBackground(0xFFFFFF)
  gpu.fill(x, y + 3, contentW, contentH, " ")
  
  -- Рамка навколо контенту
  gpu.setForeground(0x808080)
  gpu.set(x, y + 2, "╔" .. string.rep("═", contentW - 1) .. "╗")
  for i = 1, contentH - 1 do
    gpu.set(x, y + 2 + i, "║")
    gpu.set(x + contentW, y + 2 + i, "║")
  end
  gpu.set(x, y + 2 + contentH, "╚" .. string.rep("═", contentW - 1) .. "╝")
  
  -- Scrollbar
  drawScrollbar(gpu, x + w - 1, y + 3, contentH, win.scrollY, win.maxScrollY)
  
  -- Малювання контенту вкладки з урахуванням scroll
  local cy = y + 4 - win.scrollY
  local cx = x + 2
  local cw = contentW - 4
  
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  
  -- ============ ВКЛАДКА SYSTEM ============
  if win.selectedTab == 1 then
    -- Заголовок
    gpu.setForeground(0x000080)
    gpu.setBackground(0xFFFFFF)
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.set(cx, cy, "System Information")
    end
    cy = cy + 2
    
    -- Група "Operating System"
    if cy + 4 >= y + 3 then
      drawGroup(gpu, cx, cy, cw, 5, "Operating System")
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, "Name:")
      gpu.setForeground(0x000080)
      gpu.set(cx + 15, cy, "FixOS")
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, "Version:")
      gpu.setForeground(0x000080)
      gpu.set(cx + 15, cy, win.version)
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, "Architecture:")
      gpu.setForeground(0x000080)
      gpu.set(cx + 15, cy, "Lua 5.3")
    end
    cy = cy + 3
    
    -- Група "Memory"
    local totalMem = computer.totalMemory()
    local freeMem = computer.freeMemory()
    local usedMem = totalMem - freeMem
    local memPct = usedMem / totalMem
    
    if cy + 5 >= y + 3 then
      drawGroup(gpu, cx, cy, cw, 6, "Memory")
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, string.format("Total: %d KB", math.floor(totalMem / 1024)))
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.set(cx + 2, cy, string.format("Used:  %d KB", math.floor(usedMem / 1024)))
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.set(cx + 2, cy, string.format("Free:  %d KB", math.floor(freeMem / 1024)))
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      local barColor = memPct > 0.8 and 0xFF0000 or (memPct > 0.6 and 0xFFAA00 or 0x0000AA)
      drawProgressBar(gpu, cx + 2, cy, cw - 4, memPct, barColor)
    end
    cy = cy + 3
    
    -- Група "Power"
    local energy = computer.energy()
    local maxEnergy = computer.maxEnergy()
    local energyPct = energy / maxEnergy
    
    if cy + 4 >= y + 3 then
      drawGroup(gpu, cx, cy, cw, 5, "Power Status")
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, string.format("⚡ Energy: %d / %d", math.floor(energy), math.floor(maxEnergy)))
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      drawProgressBar(gpu, cx + 2, cy, cw - 4, energyPct, 0xFFAA00)
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x606060)
      gpu.set(cx + 2, cy, "Uptime: " .. math.floor(computer.uptime()) .. "s")
    end
    
    win.maxScrollY = math.max(0, cy - (y + 3 + contentH) + 5)
  
  -- ============ ВКЛАДКА DISPLAY ============
  elseif win.selectedTab == 2 then
    gpu.setForeground(0x000080)
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.set(cx, cy, "Display Settings")
    end
    cy = cy + 2
    
    -- Поточна роздільність
    if cy + 3 >= y + 3 then
      drawGroup(gpu, cx, cy, cw, 4, "Current Resolution")
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, string.format("Active: %dx%d pixels", win.currentW, win.currentH))
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x606060)
      gpu.set(cx + 2, cy, string.format("Maximum: %dx%d pixels", win.maxW, win.maxH))
    end
    cy = cy + 3
    
    -- Доступні роздільності
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x000080)
      gpu.set(cx, cy, "Available Resolutions:")
    end
    cy = cy + 2
    
    for i, res in ipairs(win.resolutions) do
      if res.w <= win.maxW and res.h <= win.maxH then
        local isCurrent = (res.w == win.currentW and res.h == win.currentH)
        
        if cy >= y + 3 and cy < y + 3 + contentH then
          -- Радіо кнопка
          gpu.setForeground(0x000000)
          gpu.set(cx + 2, cy, isCurrent and "◉" or "○")
          
          -- Назва
          gpu.setForeground(isCurrent and 0x0000AA or 0x000000)
          gpu.set(cx + 5, cy, string.format("%s (%dx%d)", res.name, res.w, res.h))
          
          -- Опис
          gpu.setForeground(0x808080)
          if cy + 1 < y + 3 + contentH then
            gpu.set(cx + 8, cy + 1, res.desc)
          end
          
          -- Зберігаємо для кліку
          win["res_" .. i] = {x = cx + 2, y = cy, w = cw - 4, h = 2, res = res}
        end
        
        cy = cy + 3
      end
    end
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x606060)
      gpu.set(cx, cy, "Click to apply and restart")
    end
    
    win.maxScrollY = math.max(0, cy - (y + 3 + contentH) + 5)
  
  -- ============ ВКЛАДКА UPDATE ============
  elseif win.selectedTab == 3 then
    gpu.setForeground(0x000080)
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.set(cx, cy, "System Update")
    end
    cy = cy + 2
    
    -- Інфо про версію
    if cy + 3 >= y + 3 then
      drawGroup(gpu, cx, cy, cw, 4, "Version Information")
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, "Installed: " .. win.version)
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x606060)
      gpu.set(cx + 2, cy, "Source: GitHub/FixlutGames21")
    end
    cy = cy + 3
    
    -- Статус оновлення
    if cy + 5 >= y + 3 then
      drawGroup(gpu, cx, cy, cw, 6, "Update Status")
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, "Status: " .. win.updateStatus)
    end
    cy = cy + 2
    
    -- Прогрес
    if win.updateProgress > 0 then
      if cy >= y + 3 and cy < y + 3 + contentH then
        drawProgressBar(gpu, cx + 2, cy, cw - 4, win.updateProgress, 0x00AA00)
      end
      cy = cy + 1
      
      if cy >= y + 3 and cy < y + 3 + contentH then
        gpu.setForeground(0x606060)
        gpu.set(cx + 2, cy, string.format("%.0f%% complete", win.updateProgress * 100))
      end
    end
    cy = cy + 3
    
    -- Кнопка оновлення
    if cy >= y + 3 and cy < y + 3 + contentH then
      local enabled = component.isAvailable("internet")
      drawButton(gpu, cx + 2, cy, 20, "Check for Updates", enabled, false)
      win.updateButton = {x = cx + 2, y = cy, w = 20, h = 3}
    end
    cy = cy + 4
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x808080)
      gpu.set(cx, cy, component.isAvailable("internet") and 
        "Internet Card detected" or "⚠ Internet Card required")
    end
    
    win.maxScrollY = math.max(0, cy - (y + 3 + contentH) + 5)
  
  -- ============ ВКЛАДКА ABOUT ============
  elseif win.selectedTab == 4 then
    -- Логотип
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x0000AA)
      gpu.set(cx + math.floor(cw/2) - 5, cy, "╔═══════╗")
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.set(cx + math.floor(cw/2) - 5, cy, "║ FixOS ║")
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.set(cx + math.floor(cw/2) - 5, cy, "╚═══════╝")
    end
    cy = cy + 2
    
    -- Версія
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x000000)
      local verText = "Version " .. win.version
      gpu.set(cx + math.floor(cw/2) - math.floor(#verText/2), cy, verText)
    end
    cy = cy + 2
    
    -- Опис
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x606060)
      local desc = "Windows 2000 style OS"
      gpu.set(cx + math.floor(cw/2) - math.floor(#desc/2), cy, desc)
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      local desc2 = "for OpenComputers"
      gpu.set(cx + math.floor(cw/2) - math.floor(#desc2/2), cy, desc2)
    end
    cy = cy + 3
    
    -- Автор
    if cy + 3 >= y + 3 then
      drawGroup(gpu, cx, cy, cw, 4, "Credits")
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x000000)
      gpu.set(cx + 2, cy, "© 2024 FixlutGames21")
    end
    cy = cy + 1
    
    if cy >= y + 3 and cy < y + 3 + contentH then
      gpu.setForeground(0x606060)
      gpu.set(cx + 2, cy, "Licensed under MIT")
    end
    cy = cy + 3
    
    -- Features
    if cy + 7 >= y + 3 then
      drawGroup(gpu, cx, cy, cw, 8, "Features")
    end
    cy = cy + 1
    
    local features = {
      "✓ Windowed interface",
      "✓ Multiple programs",
      "✓ Easy customization",
      "✓ Fast rendering",
      "✓ Modular design",
      "✓ Windows 2000 style"
    }
    
    for _, feature in ipairs(features) do
      if cy >= y + 3 and cy < y + 3 + contentH then
        gpu.setForeground(0x00AA00)
        gpu.set(cx + 2, cy, feature)
      end
      cy = cy + 1
    end
    
    win.maxScrollY = math.max(0, cy - (y + 3 + contentH) + 5)
  end
end

function settings.click(win, x, y, button)
  -- x, y - це вже ВІДНОСНІ координати від початку контенту вікна
  -- НЕ треба їх додатково конвертувати!
  
  local contentH = 17
  local contentW = 56
  local scrollbarX = contentW + 2  -- Відносна позиція scrollbar
  
  -- Клік по вкладках (відносно початку вікна, y=0 це верх вікна)
  local tabX = 0
  for i, tab in ipairs(win.tabs) do
    if x >= tabX and x < tabX + 13 and y >= -2 and y < 1 then
      win.selectedTab = i
      win.scrollY = 0
      return true
    end
    tabX = tabX + 14
  end
  
  -- Клік по scrollbar (відносно контенту)
  if x >= scrollbarX and x <= scrollbarX and y >= 1 and y < 1 + contentH then
    local relY = y - 1
    
    if relY == 0 then
      -- Кнопка вгору
      win.scrollY = math.max(0, win.scrollY - 1)
      return true
    elseif relY == contentH - 1 then
      -- Кнопка вниз
      win.scrollY = math.min(win.maxScrollY, win.scrollY + 1)
      return true
    else
      -- Клік по треку
      if win.maxScrollY > 0 then
        local pct = relY / contentH
        win.scrollY = math.floor(win.maxScrollY * pct)
      end
      return true
    end
  end
  
  -- Клік по контенту - враховуємо scroll
  local contentY = y - 1  -- y=1 це перший рядок контенту
  local adjustedY = contentY + win.scrollY + 2  -- +2 для компенсації заголовка
  
  -- Клік по роздільності (вкладка Display)
  if win.selectedTab == 2 then
    for i, res in ipairs(win.resolutions) do
      local btn = win["res_" .. i]
      if btn then
        -- btn.y вже враховує scroll offset
        local btnScreenY = btn.y - win.scrollY - 2
        
        if x >= btn.x and x < btn.x + btn.w and 
           contentY >= btnScreenY and contentY < btnScreenY + btn.h then
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
          
          computer.shutdown(true)
          return true
        end
      end
    end
  end
  
  -- Клік по кнопці оновлення (вкладка Update)
  if win.selectedTab == 3 and win.updateButton then
    local btn = win.updateButton
    local btnScreenY = btn.y - win.scrollY - 2
    
    if x >= btn.x and x < btn.x + btn.w and 
       contentY >= btnScreenY and contentY < btnScreenY + btn.h then
      settings.checkUpdates(win)
      return true
    end
  end
  
  return false
end

-- Підтримка клавіатури для прокрутки
function settings.key(win, char, code)
  -- Page Up (код 201)
  if code == 201 then
    win.scrollY = math.max(0, win.scrollY - 5)
    return true
  
  -- Page Down (код 209)
  elseif code == 209 then
    win.scrollY = math.min(win.maxScrollY, win.scrollY + 5)
    return true
  
  -- Home (код 199)
  elseif code == 199 then
    win.scrollY = 0
    return true
  
  -- End (код 207)
  elseif code == 207 then
    win.scrollY = win.maxScrollY
    return true
  
  -- Стрілка вгору (код 200)
  elseif code == 200 then
    win.scrollY = math.max(0, win.scrollY - 1)
    return true
  
  -- Стрілка вниз (код 208)
  elseif code == 208 then
    win.scrollY = math.min(win.maxScrollY, win.scrollY + 1)
    return true
  end
  
  return false
end

-- Підтримка коліщатка миші (якщо є)
function settings.scroll(win, direction)
  if direction > 0 then
    -- Scroll вниз
    win.scrollY = math.min(win.maxScrollY, win.scrollY + 3)
  else
    -- Scroll вгору
    win.scrollY = math.max(0, win.scrollY - 3)
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
        win.updateStatus = "✓ Up to date!"
      else
        win.updateStatus = "⬇ Update available: v" .. remoteVer
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