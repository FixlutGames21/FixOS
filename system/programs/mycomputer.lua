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