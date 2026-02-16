-- ==============================================
-- FixOS 3.1.0 - My Computer (WIN10 STYLE)
-- ==============================================

local mycomp = {}

function mycomp.init(win)
  win.drives = {}
  
  local bootAddr = computer.getBootAddress()
  
  for addr in component.list("filesystem") do
    local proxy = component.proxy(addr)
    if proxy then
      local drive = {
        address = addr:sub(1, 8),
        label = "Unknown",
        total = 0,
        free = 0,
        isBootDrive = (addr == bootAddr)
      }
      
      local ok, label = pcall(function() return proxy.getLabel() end)
      if ok and label and label ~= "" then
        drive.label = label
      else
        drive.label = addr:sub(1, 8)
      end
      
      local ok, total = pcall(function() return proxy.spaceTotal() end)
      if ok and total then
        drive.total = total
        local ok2, used = pcall(function() return proxy.spaceUsed() end)
        if ok2 and used then
          drive.free = total - used
        else
          drive.free = total
        end
      end
      
      if drive.total > 10000 then
        table.insert(win.drives, drive)
      end
    end
  end
  
  table.sort(win.drives, function(a, b)
    if a.isBootDrive ~= b.isBootDrive then return a.isBootDrive end
    return a.total > b.total
  end)
end

function mycomp.draw(win, gpu, x, y, w, h)
  gpu.setBackground(0xFFFFFF)
  gpu.fill(x, y, w, h, " ")
  
  -- Header (flat)
  gpu.setBackground(0xF0F0F0)
  gpu.setForeground(0x0078D7)
  gpu.fill(x, y, w, 1, " ")
  gpu.set(x + 2, y, "💻 This PC")
  
  gpu.setBackground(0xFFFFFF)
  
  local yPos = y + 2
  
  for i, drive in ipairs(win.drives) do
    if yPos + 5 < y + h then
      -- Drive card (flat)
      local cardColor = drive.isBootDrive and 0xE8F5E9 or 0xF5F5F5
      gpu.setBackground(cardColor)
      gpu.fill(x + 2, yPos, w - 4, 5, " ")
      
      -- Drive icon and name
      local icon = drive.isBootDrive and "💾" or "📀"
      gpu.setForeground(0x0078D7)
      gpu.set(x + 3, yPos, icon .. " " .. drive.label)
      
      if drive.isBootDrive then
        gpu.setForeground(0x10893E)
        gpu.set(x + w - 9, yPos, "(BOOT)")
      end
      
      -- Size info
      local function formatSize(bytes)
        if bytes > 1024 * 1024 then
          return string.format("%.1fMB", bytes / (1024 * 1024))
        elseif bytes > 1024 then
          return string.format("%.1fKB", bytes / 1024)
        else
          return bytes .. "B"
        end
      end
      
      gpu.setForeground(0x666666)
      gpu.set(x + 4, yPos + 1, "Address: " .. drive.address)
      gpu.set(x + 4, yPos + 2, "Total: " .. formatSize(drive.total))
      gpu.set(x + 4, yPos + 3, "Free: " .. formatSize(drive.free))
      
      -- Progress bar (flat)
      if drive.total > 0 then
        local used = drive.total - drive.free
        local usedPct = used / drive.total
        local barWidth = w - 10
        local filledWidth = math.floor(barWidth * usedPct)
        
        gpu.setBackground(0xE0E0E0)
        gpu.fill(x + 4, yPos + 4, barWidth, 1, " ")
        
        local barColor = usedPct < 0.7 and 0x10893E or (usedPct < 0.9 and 0xFFB900 or 0xE81123)
        gpu.setBackground(barColor)
        gpu.fill(x + 4, yPos + 4, filledWidth, 1, " ")
        
        gpu.setForeground(0x000000)
        gpu.setBackground(0xE0E0E0)
        local pctText = string.format("%.0f%%", usedPct * 100)
        gpu.set(x + 4 + math.floor((barWidth - #pctText) / 2), yPos + 4, pctText)
      end
      
      yPos = yPos + 6
    end
  end
  
  -- Summary
  gpu.setBackground(0xFFFFFF)
  if yPos < y + h - 1 then
    gpu.setForeground(0x666666)
    gpu.set(x + 2, y + h - 1, string.format("Total drives: %d", #win.drives))
  end
end

return mycomp
