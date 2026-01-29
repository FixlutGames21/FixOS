-- ==============================================
-- FixOS 2.0 - My Computer Program (ПОКРАЩЕНО)
-- system/programs/mycomputer.lua
-- ==============================================

local mycomp = {}

function mycomp.init(win)
  win.drives = {}
  local component = require("component")
  
  for addr in component.list("filesystem") do
    local proxy = component.proxy(addr)
    local label = "Unknown"
    local isBootDrive = false
    
    pcall(function() 
      label = proxy.getLabel() or addr:sub(1, 8)
    end)
    
    -- Перевірка чи це boot диск
    pcall(function()
      if component.computer and component.computer.getBootAddress then
        isBootDrive = (component.computer.getBootAddress() == addr)
      end
    end)
    
    local total = 0
    local free = 0
    local readOnly = false
    
    pcall(function() 
      total = proxy.spaceTotal()
      local used = proxy.spaceUsed and proxy.spaceUsed() or 0
      free = total - used
      readOnly = proxy.isReadOnly and proxy.isReadOnly() or false
    end)
    
    -- Пропускаємо дуже маленькі диски (tmpfs тощо)
    if total > 10000 then
      table.insert(win.drives, {
        label = label,
        address = addr:sub(1, 8),
        fullAddress = addr,
        total = total,
        free = free,
        readOnly = readOnly,
        isBootDrive = isBootDrive
      })
    end
  end
  
  -- Сортуємо: спочатку boot, потім за розміром
  table.sort(win.drives, function(a, b)
    if a.isBootDrive ~= b.isBootDrive then
      return a.isBootDrive
    end
    return a.total > b.total
  end)
end

function mycomp.draw(win, gpu, x, y, w, h)
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  gpu.fill(x, y, w, h, " ")
  
  -- Заголовок
  gpu.setForeground(0x000080)
  gpu.set(x + 2, y + 1, "Computer Drives:")
  
  local yPos = y + 3
  for i, drive in ipairs(win.drives) do
    if yPos < y + h - 1 then
      -- Іконка та назва
      local icon = drive.isBootDrive and "[SYS]" or "[HDD]"
      local nameColor = drive.isBootDrive and 0x0000FF or 0x000000
      
      gpu.setForeground(nameColor)
      gpu.set(x + 2, yPos, icon .. " " .. drive.label)
      
      -- Boot indicator
      if drive.isBootDrive then
        gpu.setForeground(0x00AA00)
        gpu.set(x + w - 7, yPos, "(BOOT)")
      end
      
      -- Read-only indicator
      if drive.readOnly then
        gpu.setForeground(0xFF0000)
        gpu.set(x + w - 5, yPos, "(RO)")
      end
      
      -- Розмір
      local totalText = "??"
      local freeText = "??"
      
      if drive.total > 1024*1024 then
        totalText = string.format("%.1fMB", drive.total / (1024*1024))
        freeText = string.format("%.1fMB", drive.free / (1024*1024))
      elseif drive.total > 1024 then
        totalText = string.format("%.1fKB", drive.total / 1024)
        freeText = string.format("%.1fKB", drive.free / 1024)
      else
        totalText = drive.total .. "B"
        freeText = drive.free .. "B"
      end
      
      gpu.setForeground(0x808080)
      gpu.set(x + 4, yPos + 1, "Address: " .. drive.address)
      gpu.set(x + 4, yPos + 2, "Total: " .. totalText .. " | Free: " .. freeText)
      
      -- Прогрес бар використання
      if drive.total > 0 then
        local used = drive.total - drive.free
        local usedPct = (used / drive.total)
        local barWidth = math.min(w - 8, 30)
        local filledWidth = math.floor(barWidth * usedPct)
        
        gpu.setForeground(0x000000)
        gpu.set(x + 4, yPos + 3, "[")
        
        -- Колір залежно від заповненості
        if usedPct < 0.7 then
          gpu.setForeground(0x00AA00)
        elseif usedPct < 0.9 then
          gpu.setForeground(0xFFAA00)
        else
          gpu.setForeground(0xFF0000)
        end
        
        for k = 1, filledWidth do
          gpu.set(x + 4 + k, yPos + 3, "■")
        end
        
        gpu.setForeground(0xCCCCCC)
        for k = filledWidth + 1, barWidth do
          gpu.set(x + 4 + k, yPos + 3, "□")
        end
        
        gpu.setForeground(0x000000)
        gpu.set(x + 5 + barWidth, yPos + 3, "]")
        
        -- Відсоток
        local pctText = string.format(" %.0f%%", usedPct * 100)
        gpu.set(x + 7 + barWidth, yPos + 3, pctText)
      end
      
      yPos = yPos + 5
    end
  end
  
  -- Додаткова інформація внизу
  if yPos < y + h - 2 then
    gpu.setForeground(0x808080)
    gpu.set(x + 2, y + h - 2, string.format("Total drives: %d", #win.drives))
  end
end

return mycomp