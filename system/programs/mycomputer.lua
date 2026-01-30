-- ==============================================
-- FixOS 2.0 - My Computer (FIXED)
-- system/programs/mycomputer.lua
-- ==============================================

local mycomp = {}

-- Ініціалізація
function mycomp.init(win)
  win.drives = {}
  
  -- Отримуємо всі файлові системи
  local bootAddr = computer.getBootAddress()
  
  for addr in component.list("filesystem") do
    local proxy = component.proxy(addr)
    if proxy then
      local drive = {
        address = addr:sub(1, 8),
        fullAddress = addr,
        label = "Unknown",
        total = 0,
        free = 0,
        readOnly = false,
        isBootDrive = (addr == bootAddr)
      }
      
      -- Отримуємо label
      local ok, label = pcall(function() return proxy.getLabel() end)
      if ok and label and label ~= "" then
        drive.label = label
      else
        drive.label = addr:sub(1, 8)
      end
      
      -- Отримуємо розмір
      local ok, total = pcall(function() return proxy.spaceTotal() end)
      if ok and total then
        drive.total = total
        
        -- Обчислюємо вільне місце
        local ok2, used = pcall(function() return proxy.spaceUsed() end)
        if ok2 and used then
          drive.free = total - used
        else
          drive.free = total
        end
      end
      
      -- Перевіряємо read-only
      local ok, ro = pcall(function() return proxy.isReadOnly() end)
      if ok then
        drive.readOnly = ro
      end
      
      -- Додаємо тільки диски більші за 10KB
      if drive.total > 10000 then
        table.insert(win.drives, drive)
      end
    end
  end
  
  -- Сортуємо: boot диск спочатку, потім за розміром
  table.sort(win.drives, function(a, b)
    if a.isBootDrive ~= b.isBootDrive then
      return a.isBootDrive
    end
    return a.total > b.total
  end)
end

-- Малювання
function mycomp.draw(win, gpu, x, y, w, h)
  -- Білий фон
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  gpu.fill(x, y, w, h, " ")
  
  -- Заголовок
  gpu.setForeground(0x000080)
  gpu.set(x + 2, y + 1, "Computer Drives:")
  
  -- Малюємо диски
  local yPos = y + 3
  
  for i, drive in ipairs(win.drives) do
    if yPos + 4 < y + h then
      -- Іконка та назва
      local icon = drive.isBootDrive and "[SYS]" or "[HDD]"
      local nameColor = drive.isBootDrive and 0x0000FF or 0x000000
      
      gpu.setForeground(nameColor)
      gpu.set(x + 2, yPos, icon .. " " .. drive.label)
      
      -- Індикатори
      if drive.isBootDrive then
        gpu.setForeground(0x00AA00)
        gpu.set(x + w - 7, yPos, "(BOOT)")
      end
      
      if drive.readOnly then
        gpu.setForeground(0xFF0000)
        gpu.set(x + w - 5, yPos, "(RO)")
      end
      
      -- Форматуємо розмір
      local function formatSize(bytes)
        if bytes > 1024 * 1024 then
          return string.format("%.1fMB", bytes / (1024 * 1024))
        elseif bytes > 1024 then
          return string.format("%.1fKB", bytes / 1024)
        else
          return bytes .. "B"
        end
      end
      
      local totalText = formatSize(drive.total)
      local freeText = formatSize(drive.free)
      
      -- Інформація
      gpu.setForeground(0x808080)
      gpu.set(x + 4, yPos + 1, "Address: " .. drive.address)
      gpu.set(x + 4, yPos + 2, "Total: " .. totalText .. " | Free: " .. freeText)
      
      -- Прогрес бар використання
      if drive.total > 0 then
        local used = drive.total - drive.free
        local usedPct = used / drive.total
        local barWidth = math.min(w - 8, 30)
        local filledWidth = math.floor(barWidth * usedPct)
        
        -- Відкриваюча дужка
        gpu.setForeground(0x000000)
        gpu.set(x + 4, yPos + 3, "[")
        
        -- Колір залежить від заповненості
        local barColor
        if usedPct < 0.7 then
          barColor = 0x00AA00 -- Зелений
        elseif usedPct < 0.9 then
          barColor = 0xFFAA00 -- Жовтий
        else
          barColor = 0xFF0000 -- Червоний
        end
        
        -- Заповнена частина
        gpu.setForeground(barColor)
        for k = 1, filledWidth do
          gpu.set(x + 4 + k, yPos + 3, "■")
        end
        
        -- Порожня частина
        gpu.setForeground(0xCCCCCC)
        for k = filledWidth + 1, barWidth do
          gpu.set(x + 4 + k, yPos + 3, "□")
        end
        
        -- Закриваюча дужка
        gpu.setForeground(0x000000)
        gpu.set(x + 5 + barWidth, yPos + 3, "]")
        
        -- Відсоток
        local pctText = string.format(" %.0f%%", usedPct * 100)
        gpu.set(x + 7 + barWidth, yPos + 3, pctText)
      end
      
      yPos = yPos + 5
    end
  end
  
  -- Підсумкова інформація
  if yPos < y + h - 1 then
    gpu.setForeground(0x808080)
    gpu.set(x + 2, y + h - 2, string.format("Total drives: %d", #win.drives))
  end
end

return mycomp