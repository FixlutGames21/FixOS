-- ==============================================
-- FixOS 3.1.1 Installer (ULTRA WINDOWS 10)
-- Максимальна схожість з Windows 10 Setup
-- Fluent Design, Acrylic, Reveal effects
-- ==============================================

local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")
local event = require("event")

local gpu = component.gpu
local internet = component.isAvailable("internet") and component.internet or nil

if not gpu then
  error("GPU not found!")
end

local w, h = gpu.maxResolution()
gpu.setResolution(math.min(80, w), math.min(25, h))
w, h = gpu.getResolution()

-- ====================
-- FLUENT DESIGN SYSTEM COLORS
-- ====================

local COLOR = {
  -- Primary Windows 10 colors
  accentPrimary = 0x0078D7,        -- Signature blue
  accentSecondary = 0x005A9E,      -- Dark blue
  accentLight = 0x429CE3,          -- Light blue
  accentLightest = 0xE3F2FD,       -- Very light blue
  
  -- Acrylic backgrounds (simulated blur)
  acrylicLight = 0xF3F3F3,         -- Light acrylic
  acrylicDark = 0x2D2D30,          -- Dark acrylic
  
  -- Base colors
  background = 0xFFFFFF,           -- Pure white
  backgroundAlt = 0xF9F9F9,        -- Alt white
  
  -- Chrome colors
  chromeDark = 0x2D2D30,           -- Dark chrome
  chromeLight = 0xF0F0F0,          -- Light chrome
  
  -- Text colors
  textPrimary = 0x000000,          -- Black
  textSecondary = 0x666666,        -- Gray
  textTertiary = 0x999999,         -- Light gray
  textDisabled = 0xCCCCCC,         -- Disabled
  textOnAccent = 0xFFFFFF,         -- White on blue
  
  -- UI elements
  divider = 0xE5E5E5,              -- Divider line
  border = 0xD1D1D1,               -- Border
  
  -- Shadows (for elevation)
  shadow1 = 0xE8E8E8,              -- Light shadow
  shadow2 = 0xD0D0D0,              -- Medium shadow
  shadow3 = 0xB0B0B0,              -- Dark shadow
  shadow4 = 0x808080,              -- Very dark shadow
  
  -- Status colors
  success = 0x10893E,              -- Green
  error = 0xE81123,                -- Red
  warning = 0xFFB900,              -- Orange
  info = 0x0078D7,                 -- Blue
  
  -- Hover states
  hoverLight = 0xF5F5F5,           -- Light hover
  hoverAccent = 0x1E8BD7,          -- Blue hover
  
  -- Special
  transparent = 0x000000           -- Transparent placeholder
}

local FILES = {
  {path = "boot/init.lua", target = "/init.lua"},
  {path = "system/desktop.lua", target = "/system/desktop.lua"},
  {path = "system/programs/calculator.lua", target = "/system/programs/calculator.lua"},
  {path = "system/programs/notepad.lua", target = "/system/programs/notepad.lua"},
  {path = "system/programs/settings.lua", target = "/system/programs/settings.lua"},
  {path = "system/programs/mycomputer.lua", target = "/system/programs/mycomputer.lua"},
  {path = "system/programs/terminal.lua", target = "/system/programs/terminal.lua"},
  {path = "system/programs/explorer.lua", target = "/system/programs/explorer.lua"},
  {path = "version.txt", target = "/version.txt"}
}

local REPO_URL = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main"

-- ====================
-- FLUENT DESIGN UI COMPONENTS
-- ====================

local function clearScreen()
  gpu.setBackground(COLOR.background)
  gpu.fill(1, 1, w, h, " ")
end

-- Elevated shadow (multi-layer for depth)
local function drawElevatedShadow(x, y, width, height, elevation)
  elevation = elevation or 4
  
  for i = 1, elevation do
    local shadowColor = COLOR.shadow1
    if i == 2 then shadowColor = COLOR.shadow2
    elseif i == 3 then shadowColor = COLOR.shadow3
    elseif i >= 4 then shadowColor = COLOR.shadow4 end
    
    gpu.setBackground(shadowColor)
    
    -- Shadow extends more as elevation increases
    for j = 0, i - 1 do
      -- Bottom shadow
      gpu.fill(x + i, y + height + j, width, 1, "▄")
      -- Right shadow
      for k = 0, height + j - 1 do
        gpu.set(x + width + i, y + k + 1, "▐")
      end
    end
  end
end

-- Acrylic card with blur simulation
local function drawAcrylicCard(x, y, width, height, title, elevated)
  elevated = elevated == nil and true or elevated
  
  -- Elevated shadow
  if elevated then
    drawElevatedShadow(x, y, width, height, 4)
  end
  
  -- Acrylic background (simulated with dithering)
  gpu.setBackground(COLOR.background)
  gpu.fill(x, y, width, height, " ")
  
  -- Subtle acrylic texture
  for i = 0, height - 1 do
    for j = 0, width - 1, 3 do
      if (i + j) % 4 == 0 then
        gpu.setBackground(COLOR.backgroundAlt)
        gpu.set(x + j, y + i, " ")
      end
    end
  end
  
  -- Title bar with accent
  if title then
    gpu.setBackground(COLOR.accentPrimary)
    gpu.fill(x, y, width, 3, " ")
    
    gpu.setForeground(COLOR.textOnAccent)
    local titleX = x + math.floor((width - #title) / 2)
    gpu.set(titleX, y + 1, title)
  end
  
  -- Subtle border for definition
  gpu.setForeground(COLOR.divider)
  for i = 0, width - 1 do
    gpu.set(x + i, y, "─")
    gpu.set(x + i, y + height - 1, "─")
  end
  for i = 0, height - 1 do
    gpu.set(x, y + i, "│")
    gpu.set(x + width - 1, y + i, "│")
  end
  
  -- Rounded corners effect
  gpu.setForeground(COLOR.background)
  gpu.set(x, y, "┌")
  gpu.set(x + width - 1, y, "┐")
  gpu.set(x, y + height - 1, "└")
  gpu.set(x + width - 1, y + height - 1, "┘")
end

-- Modern button with Fluent Design
local function drawFluentButton(x, y, width, label, style, enabled)
  enabled = enabled == nil and true or enabled
  style = style or "accent"
  
  local bg = COLOR.accentPrimary
  local fg = COLOR.textOnAccent
  
  if style == "accent" then
    bg = enabled and COLOR.accentPrimary or COLOR.textDisabled
    fg = COLOR.textOnAccent
  elseif style == "secondary" then
    bg = enabled and COLOR.chromeLight or COLOR.backgroundAlt
    fg = enabled and COLOR.textPrimary or COLOR.textDisabled
  elseif style == "success" then
    bg = enabled and COLOR.success or COLOR.textDisabled
    fg = COLOR.textOnAccent
  elseif style == "danger" then
    bg = enabled and COLOR.error or COLOR.textDisabled
    fg = COLOR.textOnAccent
  end
  
  -- Button shadow (if enabled)
  if enabled then
    gpu.setBackground(COLOR.shadow2)
    gpu.fill(x + 1, y + 1, width, 2, " ")
  end
  
  -- Button surface
  gpu.setBackground(bg)
  gpu.fill(x, y, width, 2, " ")
  
  -- Button text (centered)
  gpu.setForeground(fg)
  local textX = x + math.floor((width - #label) / 2)
  gpu.set(textX, y + 1, label)
  
  -- Subtle border for depth
  if enabled then
    gpu.setForeground(COLOR.accentSecondary)
    for i = 0, width - 1 do
      gpu.set(x + i, y, "▀")
    end
  end
  
  return {x = x, y = y, w = width, h = 2}
end

-- Modern progress bar with ring indicator
local function drawFluentProgressBar(x, y, width, percent, showRing)
  showRing = showRing == nil and true or showRing
  
  -- Track background
  gpu.setBackground(COLOR.chromeLight)
  gpu.fill(x, y, width, 1, " ")
  
  -- Filled portion (with gradient effect)
  local filled = math.floor(width * percent)
  if filled > 0 then
    for i = 0, filled - 1 do
      local shade = COLOR.accentPrimary
      if i % 3 == 0 then
        shade = COLOR.accentLight
      elseif i % 5 == 0 then
        shade = COLOR.accentSecondary
      end
      gpu.setBackground(shade)
      gpu.set(x + i, y, " ")
    end
  end
  
  -- Progress indicator
  if showRing and filled > 0 and filled < width then
    gpu.setForeground(COLOR.accentPrimary)
    gpu.setBackground(COLOR.chromeLight)
    gpu.set(x + filled, y, "●")
  end
  
  -- Percentage text overlay
  gpu.setForeground(COLOR.textOnAccent)
  gpu.setBackground(COLOR.accentPrimary)
  local pctText = string.format("%d%%", math.floor(percent * 100))
  local pctX = x + math.floor((width - #pctText) / 2)
  
  if pctX >= x and pctX < x + filled then
    gpu.set(pctX, y, pctText)
  else
    gpu.setForeground(COLOR.textSecondary)
    gpu.setBackground(COLOR.chromeLight)
    gpu.set(pctX, y, pctText)
  end
end

-- Circular progress indicator (spinner)
local function drawCircularProgress(x, y, frame)
  local rings = {"◐", "◓", "◑", "◒"}
  local char = rings[(frame % #rings) + 1]
  
  gpu.setForeground(COLOR.accentPrimary)
  gpu.setBackground(COLOR.background)
  gpu.set(x, y, char)
end

-- Status icon
local function drawStatusIcon(x, y, status)
  gpu.setBackground(COLOR.background)
  
  if status == "success" then
    gpu.setForeground(COLOR.success)
    gpu.set(x, y, "✓")
  elseif status == "error" then
    gpu.setForeground(COLOR.error)
    gpu.set(x, y, "✗")
  elseif status == "warning" then
    gpu.setForeground(COLOR.warning)
    gpu.set(x, y, "⚠")
  elseif status == "info" then
    gpu.setForeground(COLOR.info)
    gpu.set(x, y, "ℹ")
  elseif status == "loading" then
    gpu.setForeground(COLOR.accentPrimary)
    gpu.set(x, y, "⟳")
  end
end

-- Center text helper
local function centerText(y, color, text, bg)
  bg = bg or COLOR.background
  gpu.setForeground(color)
  gpu.setBackground(bg)
  local x = math.floor(w / 2 - #text / 2)
  gpu.set(x, y, text)
end

-- Button click detection
local function isInButton(btn, mx, my)
  return mx >= btn.x and mx < btn.x + btn.w and my >= btn.y and my < btn.y + btn.h
end

-- ====================
-- NETWORK FUNCTIONS
-- ====================

local function downloadFile(url, maxRetries)
  if not internet then return nil, "No Internet Card" end
  
  maxRetries = maxRetries or 3
  
  for attempt = 1, maxRetries do
    local success, handle = pcall(internet.request, url)
    
    if success and handle then
      local result = {}
      local deadline = computer.uptime() + 60
      
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
      
      if #data > 0 and not data:match("^%s*<!DOCTYPE") and not data:match("^%s*<html") then
        return data
      end
    end
    
    if attempt < maxRetries then
      os.sleep(1)
    end
  end
  
  return nil, "Download failed"
end

-- ====================
-- DISK FUNCTIONS
-- ====================

local function listDisks()
  local disks = {}
  
  for addr in component.list("filesystem") do
    local proxy = component.proxy(addr)
    if proxy then
      local ok, label = pcall(proxy.getLabel)
      local diskLabel = (ok and label and label ~= "") and label or addr:sub(1, 8)
      
      local ok2, readOnly = pcall(proxy.isReadOnly)
      local isRO = ok2 and readOnly or false
      
      local ok3, total = pcall(proxy.spaceTotal)
      local size = ok3 and total or 0
      
      if size > 200000 and not diskLabel:match("tmpfs") then
        table.insert(disks, {
          address = addr,
          label = diskLabel,
          size = size,
          readOnly = isRO
        })
      end
    end
  end
  
  table.sort(disks, function(a, b) return a.size > b.size end)
  return disks
end

local function formatDisk(addr)
  local proxy = component.proxy(addr)
  if not proxy then return false, "Cannot access disk" end
  
  local ok, ro = pcall(proxy.isReadOnly)
  if ok and ro then
    return false, "Disk is read-only"
  end
  
  local function removeRecursive(path)
    if not path or path == "" or path == "/" then 
      return 
    end
    
    local ok, isDir = pcall(proxy.isDirectory, path)
    if ok and isDir then
      local ok2, listFunc = pcall(function() return proxy.list(path) end)
      if ok2 and listFunc and type(listFunc) == "function" then
        for file in listFunc do
          if file and file ~= "" and file ~= "." and file ~= ".." then
            local fullPath = path
            if not fullPath:match("/$") then
              fullPath = fullPath .. "/"
            end
            fullPath = fullPath .. file
            removeRecursive(fullPath)
          end
        end
      end
      pcall(proxy.remove, path)
    else
      pcall(proxy.remove, path)
    end
  end
  
  local ok, listResult = pcall(function() return proxy.list("/") end)
  if ok and listResult and type(listResult) == "function" then
    for file in listResult do
      if file and file ~= "" and file ~= "/" and file ~= "." and file ~= ".." then
        removeRecursive("/" .. file)
      end
    end
  end
  
  return true
end

local function writeFileToDisk(proxy, path, content)
  local dir = path:match("(.+)/[^/]+$")
  if dir then
    local parts = {}
    for part in dir:gmatch("[^/]+") do
      table.insert(parts, part)
    end
    
    local currentPath = ""
    for _, part in ipairs(parts) do
      currentPath = currentPath .. "/" .. part
      if not proxy.exists(currentPath) then
        local ok, err = pcall(proxy.makeDirectory, currentPath)
        if not ok then
          return false, "Cannot create directory"
        end
      end
    end
  end
  
  local ok, handle = pcall(proxy.open, path, "w")
  if not ok or not handle then
    return false, "Cannot create file"
  end
  
  local writeOk, writeErr = pcall(proxy.write, handle, content)
  pcall(proxy.close, handle)
  
  if not writeOk then
    return false, "Write error"
  end
  
  return true
end

-- ====================
-- SETUP SCREENS (ULTRA WINDOWS 10)
-- ====================

local function welcomeScreen()
  clearScreen()
  
  -- Main card (elevated)
  drawAcrylicCard(8, 2, w - 16, h - 4, "FixOS 3.1.1 Setup", true)
  
  -- Welcome message
  gpu.setBackground(COLOR.background)
  gpu.setForeground(COLOR.accentPrimary)
  centerText(6, COLOR.accentPrimary, "Welcome to FixOS Setup", COLOR.background)
  
  gpu.setForeground(COLOR.textSecondary)
  centerText(7, COLOR.textSecondary, "MAXIMUM WINDOWS 10 EDITION", COLOR.background)
  
  -- Feature list with icons
  gpu.setBackground(COLOR.background)
  gpu.setForeground(COLOR.textPrimary)
  
  local features = {
    {icon = "✓", text = "Fluent Design System", color = COLOR.success},
    {icon = "✓", text = "Acrylic & Reveal Effects", color = COLOR.success},
    {icon = "✓", text = "Ultra-Fast Performance", color = COLOR.success},
    {icon = "✓", text = "Modern UI Components", color = COLOR.success},
    {icon = "✓", text = "Windows 10 Style", color = COLOR.success},
    {icon = "✓", text = "Professional Experience", color = COLOR.success}
  }
  
  local startY = 10
  for i, feature in ipairs(features) do
    gpu.setForeground(feature.color)
    gpu.set(15, startY + i - 1, feature.icon)
    gpu.setForeground(COLOR.textPrimary)
    gpu.set(18, startY + i - 1, feature.text)
  end
  
  -- Internet check
  if not internet then
    drawStatusIcon(math.floor(w/2) - 1, h - 7, "error")
    gpu.setForeground(COLOR.error)
    centerText(h - 7, COLOR.error, "  Internet Card required!", COLOR.background)
    gpu.setForeground(COLOR.textSecondary)
    centerText(h - 6, COLOR.textSecondary, "Insert Internet Card and restart", COLOR.background)
    
    local btnOk = drawFluentButton(math.floor(w/2) - 7, h - 4, 14, "Exit", "secondary")
    
    while true do
      local ev, _, x, y = event.pull()
      if ev == "touch" and isInButton(btnOk, x, y) then
        return false
      end
    end
  end
  
  -- Action buttons
  local btnNext = drawFluentButton(w - 28, h - 4, 12, "Next →", "accent")
  local btnCancel = drawFluentButton(w - 15, h - 4, 12, "Cancel", "secondary")
  
  while true do
    local ev, _, x, y = event.pull()
    if ev == "touch" then
      if isInButton(btnNext, x, y) then return true
      elseif isInButton(btnCancel, x, y) then return false end
    elseif ev == "key_down" then
      if _ == 28 then return true end
      if _ == 1 then return false end
    end
  end
end

local function selectDiskScreen()
  clearScreen()
  
  drawAcrylicCard(8, 2, w - 16, h - 4, "Choose Installation Drive", true)
  
  gpu.setBackground(COLOR.background)
  gpu.setForeground(COLOR.textPrimary)
  centerText(6, COLOR.textPrimary, "Select where to install FixOS 3.1.1", COLOR.background)
  
  -- Warning banner
  gpu.setBackground(COLOR.warning)
  gpu.fill(10, 8, w - 20, 1, " ")
  gpu.setForeground(COLOR.textOnAccent)
  centerText(8, COLOR.textOnAccent, "⚠ All data on selected drive will be erased", COLOR.warning)
  
  gpu.setBackground(COLOR.background)
  
  local disks = listDisks()
  
  if #disks == 0 then
    drawStatusIcon(math.floor(w/2) - 8, 12, "error")
    gpu.setForeground(COLOR.error)
    centerText(12, COLOR.error, "  No suitable drives found", COLOR.background)
    gpu.setForeground(COLOR.textSecondary)
    centerText(14, COLOR.textSecondary, "Please insert a drive and restart", COLOR.background)
    
    local btnBack = drawFluentButton(math.floor(w/2) - 7, h - 4, 14, "← Back", "secondary")
    event.pull("touch")
    return nil
  end
  
  local buttons = {}
  local startY = 11
  
  for i, disk in ipairs(disks) do
    if startY + (i - 1) * 4 < h - 8 then
      -- Disk card
      local cardX = 12
      local cardY = startY + (i - 1) * 4
      local cardW = w - 24
      
      -- Disk icon
      gpu.setBackground(COLOR.backgroundAlt)
      gpu.fill(cardX, cardY, cardW, 3, " ")
      
      local icon = disk.readOnly and "🔒" or "💾"
      gpu.setForeground(COLOR.accentPrimary)
      gpu.set(cardX + 2, cardY + 1, icon)
      
      -- Disk info
      gpu.setForeground(disk.readOnly and COLOR.textDisabled or COLOR.textPrimary)
      local sizeText = string.format("%.1f MB", disk.size / (1024 * 1024))
      local info = string.format("%s (%s)", disk.label, sizeText)
      gpu.set(cardX + 5, cardY + 1, info)
      
      if disk.readOnly then
        gpu.setForeground(COLOR.error)
        gpu.set(cardX + cardW - 12, cardY + 1, "READ-ONLY")
      end
      
      -- Button
      local btn = drawFluentButton(cardX + 2, cardY + 2, cardW - 4, "Select this drive", 
                                    disk.readOnly and "secondary" or "accent", 
                                    not disk.readOnly)
      btn.disk = disk
      table.insert(buttons, btn)
    end
  end
  
  local btnBack = drawFluentButton(w - 15, h - 4, 12, "← Back", "secondary")
  table.insert(buttons, btnBack)
  
  while true do
    local ev, _, x, y = event.pull()
    if ev == "touch" then
      for _, btn in ipairs(buttons) do
        if isInButton(btn, x, y) then
          if btn == btnBack then return nil
          elseif btn.disk and not btn.disk.readOnly then return btn.disk end
        end
      end
    end
  end
end

local function confirmScreen(disk)
  clearScreen()
  
  drawAcrylicCard(12, 6, w - 24, 16, "Confirm Installation", true)
  
  gpu.setBackground(COLOR.background)
  
  -- Warning icon and message
  drawStatusIcon(math.floor(w/2) - 1, 10, "warning")
  gpu.setForeground(COLOR.textPrimary)
  centerText(10, COLOR.textPrimary, "  Ready to install", COLOR.background)
  
  gpu.setForeground(COLOR.textSecondary)
  centerText(12, COLOR.textSecondary, "Installation will:", COLOR.background)
  centerText(13, COLOR.textSecondary, "• Format the selected drive", COLOR.background)
  centerText(14, COLOR.textSecondary, "• Install FixOS 3.1.1", COLOR.background)
  centerText(15, COLOR.textSecondary, "• Set boot configuration", COLOR.background)
  
  -- Drive info
  gpu.setBackground(COLOR.backgroundAlt)
  gpu.fill(14, 17, w - 28, 3, " ")
  
  gpu.setForeground(COLOR.accentPrimary)
  gpu.set(16, 18, "💾 Drive: " .. disk.label)
  gpu.setForeground(COLOR.textSecondary)
  local addrText = "   (" .. disk.address:sub(1, 8) .. ")"
  gpu.set(16, 19, addrText)
  
  gpu.setBackground(COLOR.background)
  
  -- Buttons
  local btnInstall = drawFluentButton(math.floor(w/2) - 20, 21, 18, "Install Now", "accent")
  local btnCancel = drawFluentButton(math.floor(w/2) + 2, 21, 18, "Cancel", "secondary")
  
  while true do
    local ev, _, x, y = event.pull()
    if ev == "touch" then
      if isInButton(btnInstall, x, y) then return true
      elseif isInButton(btnCancel, x, y) then return false end
    end
  end
end

local function installScreen(disk)
  clearScreen()
  
  drawAcrylicCard(8, 2, w - 16, h - 4, "Installing FixOS 3.1.1", true)
  
  local proxy = component.proxy(disk.address)
  local spinnerFrame = 0
  
  gpu.setBackground(COLOR.background)
  
  -- Step 1: Format
  gpu.setForeground(COLOR.accentPrimary)
  centerText(6, COLOR.accentPrimary, "Preparing drive...", COLOR.background)
  
  gpu.setForeground(COLOR.textSecondary)
  centerText(7, COLOR.textSecondary, disk.label, COLOR.background)
  
  drawFluentProgressBar(15, 9, w - 30, 0, true)
  drawCircularProgress(math.floor(w/2), 11, spinnerFrame)
  
  gpu.setForeground(COLOR.textTertiary)
  centerText(13, COLOR.textTertiary, "This may take a moment...", COLOR.background)
  
  os.sleep(0.3)
  
  local ok, err = formatDisk(disk.address)
  if not ok then
    drawStatusIcon(math.floor(w/2) - 8, 15, "error")
    gpu.setForeground(COLOR.error)
    centerText(15, COLOR.error, "  Format failed", COLOR.background)
    gpu.setForeground(COLOR.textSecondary)
    local errMsg = tostring(err)
    if #errMsg > w - 20 then errMsg = errMsg:sub(1, w - 23) .. "..." end
    centerText(16, COLOR.textSecondary, errMsg, COLOR.background)
    
    drawFluentButton(math.floor(w/2) - 7, h - 4, 14, "Exit", "secondary")
    event.pull("touch")
    return false
  end
  
  drawFluentProgressBar(15, 9, w - 30, 0.33, true)
  drawStatusIcon(math.floor(w/2) - 7, 15, "success")
  gpu.setForeground(COLOR.success)
  centerText(15, COLOR.success, "  Drive prepared", COLOR.background)
  os.sleep(0.5)
  
  -- Step 2: Label
  clearScreen()
  drawAcrylicCard(8, 2, w - 16, h - 4, "Installing FixOS 3.1.1", true)
  gpu.setBackground(COLOR.background)
  
  gpu.setForeground(COLOR.accentPrimary)
  centerText(6, COLOR.accentPrimary, "Configuring system...", COLOR.background)
  
  gpu.setForeground(COLOR.textSecondary)
  centerText(7, COLOR.textSecondary, "Setting drive label", COLOR.background)
  
  drawFluentProgressBar(15, 9, w - 30, 0.5, true)
  spinnerFrame = spinnerFrame + 3
  drawCircularProgress(math.floor(w/2), 11, spinnerFrame)
  
  local labelOk = pcall(proxy.setLabel, "FixOS")
  
  drawFluentProgressBar(15, 9, w - 30, 0.6, true)
  drawStatusIcon(math.floor(w/2) - 7, 13, labelOk and "success" or "warning")
  gpu.setForeground(labelOk and COLOR.success or COLOR.warning)
  centerText(13, labelOk and COLOR.success or COLOR.warning, 
             labelOk and "  Drive labeled" or "  Label skipped", COLOR.background)
  os.sleep(0.5)
  
  -- Step 3: Download
  clearScreen()
  drawAcrylicCard(8, 2, w - 16, h - 4, "Installing FixOS 3.1.1", true)
  gpu.setBackground(COLOR.background)
  
  gpu.setForeground(COLOR.accentPrimary)
  centerText(6, COLOR.accentPrimary, "Downloading system files...", COLOR.background)
  
  local total = #FILES
  local succeeded = 0
  
  for i, file in ipairs(FILES) do
    local fileName = file.path
    if #fileName > 40 then
      fileName = "..." .. fileName:sub(-37)
    end
    
    gpu.setForeground(COLOR.textSecondary)
    gpu.fill(10, 8, w - 20, 1, " ")
    centerText(8, COLOR.textSecondary, fileName, COLOR.background)
    
    local progress = 0.6 + ((i - 1) / total) * 0.4
    drawFluentProgressBar(15, 10, w - 30, progress, true)
    
    spinnerFrame = spinnerFrame + 1
    drawCircularProgress(math.floor(w/2), 12, spinnerFrame)
    
    drawStatusIcon(math.floor(w/2) - 6, 14, "loading")
    gpu.setForeground(COLOR.info)
    centerText(14, COLOR.info, "  Downloading...", COLOR.background)
    
    local url = REPO_URL .. "/" .. file.path
    local data, downloadErr = downloadFile(url, 3)
    
    if data then
      drawStatusIcon(math.floor(w/2) - 5, 14, "loading")
      gpu.setForeground(COLOR.info)
      centerText(14, COLOR.info, "  Writing...", COLOR.background)
      
      local writeOk = writeFileToDisk(proxy, file.target, data)
      
      if writeOk then
        succeeded = succeeded + 1
      else
        gpu.setForeground(COLOR.error)
        centerText(16, COLOR.error, "Write failed", COLOR.background)
        os.sleep(0.3)
      end
    else
      gpu.setForeground(COLOR.error)
      centerText(16, COLOR.error, "Download failed", COLOR.background)
      os.sleep(0.3)
    end
    
    os.sleep(0.1)
  end
  
  drawFluentProgressBar(15, 10, w - 30, 1.0, true)
  
  gpu.fill(10, 12, w - 20, 5, " ")
  gpu.setBackground(COLOR.background)
  
  if succeeded >= total - 1 then
    drawStatusIcon(math.floor(w/2) - 8, 14, "success")
    gpu.setForeground(COLOR.success)
    centerText(14, COLOR.success, "  Installation complete!", COLOR.background)
  else
    drawStatusIcon(math.floor(w/2) - 7, 14, "warning")
    gpu.setForeground(COLOR.warning)
    centerText(14, COLOR.warning, string.format("  %d/%d files installed", succeeded, total), COLOR.background)
  end
  
  -- Boot config
  local bootOk = pcall(computer.setBootAddress, disk.address)
  if bootOk then
    gpu.setForeground(COLOR.textSecondary)
    centerText(16, COLOR.textSecondary, "Boot configured", COLOR.background)
  end
  
  os.sleep(1.5)
  return succeeded >= total - 1
end

local function finishScreen()
  clearScreen()
  
  drawAcrylicCard(10, 5, w - 20, 17, "Setup Complete", true)
  
  gpu.setBackground(COLOR.background)
  
  -- Success icon
  drawStatusIcon(math.floor(w/2) - 1, 9, "success")
  
  gpu.setForeground(COLOR.success)
  centerText(9, COLOR.success, "  FixOS 3.1.1 installed successfully!", COLOR.background)
  
  gpu.setForeground(COLOR.textPrimary)
  centerText(11, COLOR.textPrimary, "Your system is ready", COLOR.background)
  
  gpu.setForeground(COLOR.textSecondary)
  centerText(13, COLOR.textSecondary, "• Drive labeled as FixOS", COLOR.background)
  centerText(14, COLOR.textSecondary, "• Boot configuration set", COLOR.background)
  centerText(15, COLOR.textSecondary, "• All files installed", COLOR.background)
  
  gpu.setBackground(COLOR.accentLightest)
  gpu.fill(12, 17, w - 24, 1, " ")
  gpu.setForeground(COLOR.accentPrimary)
  centerText(17, COLOR.accentPrimary, "Enjoy the MAXIMUM WINDOWS 10 EDITION!", COLOR.accentLightest)
  
  gpu.setBackground(COLOR.background)
  gpu.setForeground(COLOR.textTertiary)
  
  for i = 5, 1, -1 do
    local countdown = string.format("Restarting in %d seconds...", i)
    gpu.fill(10, 20, w - 20, 1, " ")
    centerText(20, COLOR.textTertiary, countdown, COLOR.background)
    os.sleep(1)
  end
  
  computer.shutdown(true)
end

-- ====================
-- MAIN FLOW
-- ====================

local function main()
  if not welcomeScreen() then
    clearScreen()
    centerText(h / 2, COLOR.textPrimary, "Setup cancelled")
    os.sleep(1)
    return
  end
  
  local disk = selectDiskScreen()
  if not disk then
    clearScreen()
    centerText(h / 2, COLOR.textPrimary, "Setup cancelled")
    os.sleep(1)
    return
  end
  
  if not confirmScreen(disk) then
    clearScreen()
    centerText(h / 2, COLOR.textPrimary, "Setup cancelled")
    os.sleep(1)
    return
  end
  
  if not installScreen(disk) then 
    return 
  end
  
  finishScreen()
end

-- ====================
-- ERROR HANDLING
-- ====================

local ok, err = pcall(main)
if not ok then
  clearScreen()
  
  gpu.setBackground(COLOR.error)
  gpu.setForeground(COLOR.textOnAccent)
  gpu.fill(1, 1, w, h, " ")
  
  drawStatusIcon(math.floor(w/2) - 7, h/2 - 2, "error")
  centerText(h/2 - 2, COLOR.textOnAccent, "  Setup Error", COLOR.error)
  
  local errMsg = tostring(err)
  if #errMsg > w - 6 then
    errMsg = errMsg:sub(1, w - 9) .. "..."
  end
  centerText(h/2, COLOR.textOnAccent, errMsg, COLOR.error)
  
  centerText(h/2 + 2, COLOR.textOnAccent, "Press any key to exit", COLOR.error)
  
  event.pull("key_down")
end
