-- ==============================================
-- FixOS 3.1.0 - Settings (WINDOWS 10 STYLE)
-- Flat design, optimized
-- ==============================================

local settings = {}

function settings.init(win)
  win.selectedTab = 1
  win.tabs = {"System", "Display", "Update", "About"}
  win.version = "3.1.0"
  win.updateStatus = "Ready"
  win.updateProgress = 0
  win.scrollY = 0
  win.maxScrollY = 0
  
  local fs = component.proxy(computer.getBootAddress())
  if fs.exists("/version.txt") then
    local h = fs.open("/version.txt", "r")
    if h then
      local v = fs.read(h, math.huge)
      fs.close(h)
      if v then win.version = v:match("[%d%.]+") or win.version end
    end
  end
  
  win.resolutions = {
    {w = 50, h = 16, name = "Tiny"},
    {w = 80, h = 25, name = "Standard"},
    {w = 100, h = 30, name = "Large"},
    {w = 120, h = 40, name = "Huge"},
    {w = 160, h = 50, name = "Maximum"}
  }
  
  local gpu = component.proxy(component.list("gpu")())
  win.currentW, win.currentH = gpu.getResolution()
  win.maxW, win.maxH = gpu.maxResolution()
  
  win.uiElements = {}
end

local function drawFlatCard(gpu, x, y, w, h, title)
  gpu.setBackground(0xF5F5F5)
  gpu.fill(x, y, w, h, " ")
  
  gpu.setBackground(0x0078D7)
  gpu.fill(x, y, w, 1, " ")
  
  gpu.setForeground(0xFFFFFF)
  gpu.set(x + 2, y, title)
  
  gpu.setBackground(0xFFFFFF)
end

local function drawFlatButton(gpu, x, y, w, label, enabled)
  local bg = enabled and 0x0078D7 or 0xCCCCCC
  
  gpu.setBackground(bg)
  gpu.fill(x, y, w, 1, " ")
  
  gpu.setForeground(0xFFFFFF)
  local tx = x + math.floor((w - #label) / 2)
  gpu.set(tx, y, label)
end

local function drawProgressBar(gpu, x, y, w, percent, color)
  gpu.setBackground(0xE0E0E0)
  gpu.fill(x, y, w, 1, " ")
  
  local filled = math.floor(w * percent)
  if filled > 0 then
    gpu.setBackground(color or 0x0078D7)
    gpu.fill(x, y, filled, 1, " ")
  end
  
  gpu.setForeground(0x000000)
  gpu.setBackground(0xE0E0E0)
  local pct = string.format("%.0f%%", percent * 100)
  gpu.set(x + math.floor((w - #pct) / 2), y, pct)
end

function settings.draw(win, gpu, x, y, w, h)
  gpu.setBackground(0xFFFFFF)
  gpu.fill(x, y, w, h, " ")
  
  -- Flat tabs
  local tabX = x
  for i, tab in ipairs(win.tabs) do
    local isActive = (win.selectedTab == i)
    local tabW = 14
    local tabBg = isActive and 0x0078D7 or 0xE0E0E0
    local tabFg = isActive and 0xFFFFFF or 0x666666
    
    gpu.setBackground(tabBg)
    gpu.setForeground(tabFg)
    gpu.fill(tabX, y, tabW, 1, " ")
    
    local labelX = tabX + math.floor((tabW - #tab) / 2)
    gpu.set(labelX, y, tab)
    tabX = tabX + tabW + 1
  end
  
  -- Content area
  gpu.setBackground(0xFFFFFF)
  local cy = y + 2
  local cx = x + 2
  local cw = w - 4
  
  win.uiElements = {}
  
  local function isVisible(elemY)
    return elemY >= y + 2 and elemY < y + h - 1
  end
  
  if win.selectedTab == 1 then
    -- System tab
    if isVisible(cy) then
      gpu.setForeground(0x0078D7)
      gpu.set(cx, cy, "● System Information")
    end
    cy = cy + 2
    
    if cy >= y + 2 - 5 then
      drawFlatCard(gpu, cx, cy, cw, 5, "Operating System")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x666666)
      gpu.set(cx + 2, cy, "Name: FixOS")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.set(cx + 2, cy, "Version: " .. win.version .. " - Win10 Edition")
    end
    cy = cy + 3
    
    -- Memory
    local totalMem = computer.totalMemory()
    local freeMem = computer.freeMemory()
    local usedMem = totalMem - freeMem
    local memPct = usedMem / totalMem
    
    if cy >= y + 2 - 5 then
      drawFlatCard(gpu, cx, cy, cw, 5, "Memory")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x666666)
      gpu.set(cx + 2, cy, string.format("Used: %dKB / %dKB", 
        math.floor(usedMem/1024), math.floor(totalMem/1024)))
    end
    cy = cy + 1
    
    if isVisible(cy) then
      local barColor = memPct > 0.8 and 0xE81123 or 0x10893E
      drawProgressBar(gpu, cx + 2, cy, cw - 4, memPct, barColor)
    end
    cy = cy + 3
    
    win.maxScrollY = 0
    
  elseif win.selectedTab == 2 then
    -- Display tab
    if isVisible(cy) then
      gpu.setForeground(0x0078D7)
      gpu.set(cx, cy, "● Display Settings")
    end
    cy = cy + 2
    
    if cy >= y + 2 - 4 then
      drawFlatCard(gpu, cx, cy, cw, 3, "Current Resolution")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x666666)
      gpu.set(cx + 2, cy, string.format("Active: %dx%d pixels", win.currentW, win.currentH))
    end
    cy = cy + 3
    
    if isVisible(cy) then
      gpu.setForeground(0x666666)
      gpu.set(cx, cy, "Available Resolutions:")
    end
    cy = cy + 1
    
    for i, res in ipairs(win.resolutions) do
      if res.w <= win.maxW and res.h <= win.maxH then
        local isCurrent = (res.w == win.currentW and res.h == win.currentH)
        
        if isVisible(cy) then
          local bg = isCurrent and 0x0078D7 or 0xF0F0F0
          local fg = isCurrent and 0xFFFFFF or 0x000000
          
          gpu.setBackground(bg)
          gpu.setForeground(fg)
          gpu.fill(cx, cy, cw, 1, " ")
          
          local text = string.format("%s (%dx%d)", res.name, res.w, res.h)
          gpu.set(cx + 2, cy, text)
          
          table.insert(win.uiElements, {
            type = "resolution",
            x = win.x + cx,
            y = cy,
            w = cw,
            h = 1,
            res = res
          })
        end
        
        cy = cy + 1
      end
    end
    
    win.maxScrollY = 0
    
  elseif win.selectedTab == 3 then
    -- Update tab
    if isVisible(cy) then
      gpu.setForeground(0x0078D7)
      gpu.set(cx, cy, "● System Update")
    end
    cy = cy + 2
    
    if cy >= y + 2 - 4 then
      drawFlatCard(gpu, cx, cy, cw, 4, "Version Information")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x666666)
      gpu.set(cx + 2, cy, "Installed: FixOS " .. win.version)
    end
    cy = cy + 3
    
    if cy >= y + 2 - 5 then
      drawFlatCard(gpu, cx, cy, cw, 5, "Update Status")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x666666)
      gpu.set(cx + 2, cy, "Status: " .. win.updateStatus)
    end
    cy = cy + 2
    
    if win.updateProgress > 0 and isVisible(cy) then
      drawProgressBar(gpu, cx + 2, cy, cw - 4, win.updateProgress, 0x10893E)
      cy = cy + 1
    end
    cy = cy + 2
    
    if isVisible(cy) then
      local enabled = component.isAvailable("internet")
      drawFlatButton(gpu, cx + 2, cy, 18, "Check Updates", enabled)
      
      table.insert(win.uiElements, {
        type = "button",
        action = "update",
        x = win.x + cx + 2,
        y = cy,
        w = 18,
        h = 1
      })
    end
    
    win.maxScrollY = 0
    
  elseif win.selectedTab == 4 then
    -- About tab
    if isVisible(cy) then
      gpu.setForeground(0x0078D7)
      local title = "FixOS"
      gpu.set(cx + math.floor(cw/2) - 3, cy, title)
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x666666)
      local ver = "Version " .. win.version
      gpu.set(cx + math.floor((cw - #ver)/2), cy, ver)
    end
    cy = cy + 1
    
    if isVisible(cy) then
      local ed = "WINDOWS 10 EDITION"
      gpu.set(cx + math.floor((cw - #ed)/2), cy, ed)
    end
    cy = cy + 3
    
    if cy >= y + 2 - 3 then
      drawFlatCard(gpu, cx, cy, cw, 3, "Credits")
    end
    cy = cy + 1
    
    if isVisible(cy) then
      gpu.setForeground(0x666666)
      gpu.set(cx + 2, cy, "© 2026 FixlutGames21")
    end
    
    win.maxScrollY = 0
  end
end

function settings.click(win, clickX, clickY, button)
  local tabX = win.x
  for i, tab in ipairs(win.tabs) do
    if clickY == win.y and clickX >= tabX and clickX < tabX + 14 then
      win.selectedTab = i
      return true
    end
    tabX = tabX + 15
  end
  
  for _, elem in ipairs(win.uiElements) do
    if clickX >= elem.x and clickX < elem.x + elem.w and
       clickY >= elem.y and clickY < elem.y + elem.h then
      
      if elem.type == "resolution" then
        local gpu = component.proxy(component.list("gpu")())
        gpu.setResolution(elem.res.w, elem.res.h)
        
        local fs = component.proxy(computer.getBootAddress())
        local h = fs.open("/settings.cfg", "w")
        if h then
          fs.write(h, string.format("resolution=%dx%d\n", elem.res.w, elem.res.h))
          fs.close(h)
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

function settings.checkUpdates(win)
  if not component.isAvailable("internet") then
    win.updateStatus = "Error: No Internet Card"
    return
  end
  
  win.updateStatus = "Checking..."
  win.updateProgress = 0.5
  
  local internet = component.internet
  local url = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/version.txt"
  
  local ok, handle = pcall(internet.request, url)
  if not ok or not handle then
    win.updateStatus = "Error: Cannot connect"
    win.updateProgress = 0
    return
  end
  
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
        win.updateStatus = "✓ Up to date!"
      else
        win.updateStatus = "⬇ Update: v" .. remoteVer
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
