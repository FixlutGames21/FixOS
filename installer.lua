-- ==============================================
-- FixOS 2.0 Installer - Нова структура
-- ==============================================

local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")
local event = require("event")

-- COMPONENTS
local gpu = component.gpu
local internet = component.isAvailable("internet") and component.internet or nil

local w, h = gpu.maxResolution()
gpu.setResolution(math.min(80, w), math.min(25, h))
w, h = gpu.getResolution()

-- COLORS
local COLOR = {
  bg = 0x0000AA,
  panel = 0x000080,
  white = 0xFFFFFF,
  lightGray = 0xCCCCCC,
  gray = 0x808080,
  darkGray = 0x404040,
  green = 0x00FF00,
  darkGreen = 0x00AA00,
  red = 0xFF0000,
  darkRed = 0xAA0000,
  yellow = 0xFFFF00,
  cyan = 0x00FFFF
}

-- НОВА СТРУКТУРА ФАЙЛІВ
local FILES = {
  {path = "boot/init.lua", target = "/boot/init.lua"},
  {path = "system/desktop.lua", target = "/system/desktop.lua"},
  {path = "system/programs/calculator.lua", target = "/system/programs/calculator.lua"},
  {path = "system/programs/notepad.lua", target = "/system/programs/notepad.lua"},
  {path = "system/programs/settings.lua", target = "/system/programs/settings.lua"},
  {path = "system/programs/mycomputer.lua", target = "/system/programs/mycomputer.lua"},
  {path = "version.txt", target = "/version.txt"}
}

local REPO_URL = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main"

-- GUI FUNCTIONS (залишаються ті самі)
local function clearScreen()
  gpu.setBackground(COLOR.bg)
  gpu.fill(1, 1, w, h, " ")
end

local function drawBox(x, y, width, height, title)
  gpu.setBackground(COLOR.darkGray)
  gpu.fill(x + 1, y + 1, width, height, " ")
  gpu.setBackground(COLOR.lightGray)
  gpu.fill(x, y, width, height, " ")
  
  if title then
    gpu.setBackground(COLOR.panel)
    gpu.fill(x, y, width, 2, " ")
    gpu.setForeground(COLOR.white)
    local titleX = x + math.floor((width - #title) / 2)
    gpu.set(titleX, y + 1, title)
  end
  
  gpu.setForeground(COLOR.white)
  for i = 0, width - 1 do gpu.set(x + i, y, "▀") end
  for i = 0, height - 1 do gpu.set(x, y + i, "▌") end
  
  gpu.setForeground(COLOR.darkGray)
  for i = 0, width - 1 do gpu.set(x + i, y + height - 1, "▄") end
  for i = 0, height - 1 do gpu.set(x + width - 1, y + i, "▐") end
end

local function drawButton(x, y, width, label, bgColor)
  gpu.setBackground(bgColor)
  gpu.fill(x, y, width, 3, " ")
  
  gpu.setForeground(COLOR.white)
  for i = 0, width - 1 do gpu.set(x + i, y, "▀") end
  for i = 0, 2 do gpu.set(x, y + i, "▌") end
  
  gpu.setForeground(COLOR.darkGray)
  for i = 0, width - 1 do gpu.set(x + i, y + 2, "▄") end
  for i = 0, 2 do gpu.set(x + width - 1, y + i, "▐") end
  
  gpu.setForeground(COLOR.white)
  local labelX = x + math.floor((width - #label) / 2)
  gpu.set(labelX, y + 1, label)
  
  return {x = x, y = y, w = width, h = 3}
end

local function centerText(y, color, text)
  gpu.setForeground(color)
  local x = math.floor(w / 2 - #text / 2)
  gpu.set(x, y, text)
end

local function drawProgressBar(x, y, width, percent)
  gpu.setBackground(COLOR.darkGray)
  gpu.fill(x, y, width, 2, " ")
  
  local filled = math.floor((width - 2) * percent)
  gpu.setBackground(COLOR.green)
  gpu.fill(x + 1, y, filled, 2, " ")
  
  gpu.setBackground(COLOR.darkGray)
  gpu.setForeground(COLOR.white)
  local pctText = string.format("%.0f%%", percent * 100)
  local pctX = x + math.floor(width / 2) - 1
  gpu.set(pctX, y + 1, pctText)
end

local function isInButton(btn, mx, my)
  return mx >= btn.x and mx < btn.x + btn.w and my >= btn.y and my < btn.y + btn.h
end

-- WORK FUNCTIONS
local function downloadFile(url)
  if not internet then return nil, "No Internet Card" end
  
  local handle = internet.request(url)
  if not handle then return nil, "Connection failed" end
  
  local result = {}
  local deadline = computer.uptime() + 30
  
  while computer.uptime() < deadline do
    local chunk = handle.read(math.huge)
    if chunk then
      table.insert(result, chunk)
    else
      break
    end
  end
  
  handle.close()
  local data = table.concat(result)
  
  if #data == 0 then return nil, "Empty response" end
  if data:match("404") or data:match("<!DOCTYPE") then return nil, "File not found (404)" end
  
  return data
end

local function listDisks()
  local disks = {}
  for addr in component.list("filesystem") do
    local proxy = component.proxy(addr)
    if proxy then
      local ok, label = pcall(proxy.getLabel, proxy)
      local diskLabel = (ok and label and label ~= "") and label or addr:sub(1, 8)
      
      local ok2, readOnly = pcall(proxy.isReadOnly, proxy)
      local isRO = ok2 and readOnly or false
      
      local ok3, total = pcall(proxy.spaceTotal, proxy)
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
  
  local function removeRecursive(path)
    if proxy.isDirectory(path) then
      for file in proxy.list(path) do
        removeRecursive(path .. "/" .. file)
      end
      pcall(proxy.remove, path)
    else
      pcall(proxy.remove, path)
    end
  end
  
  for file in proxy.list("/") do
    removeRecursive("/" .. file)
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
        proxy.makeDirectory(currentPath)
      end
    end
  end
  
  local handle = proxy.open(path, "w")
  if not handle then return false, "Cannot create file" end
  
  proxy.write(handle, content)
  proxy.close(handle)
  
  return true
end

-- SCREENS
local function welcomeScreen()
  clearScreen()
  drawBox(8, 2, w - 16, h - 4, "FixOS 2.0 Setup")
  
  centerText(6, COLOR.white, "Welcome to FixOS 2.0 Installer")
  centerText(8, COLOR.cyan, "Windows 2000 Style Operating System")
  
  centerText(11, COLOR.white, "New modular structure:")
  gpu.setForeground(COLOR.lightGray)
  gpu.set(15, 13, "• Separate program files")
  gpu.set(15, 14, "• /boot/init.lua for booting")
  gpu.set(15, 15, "• /system/programs/ folder")
  gpu.set(15, 16, "• Easy to add new apps")
  
  if not internet then
    centerText(19, COLOR.red, "ERROR: Internet Card required!")
    centerText(20, COLOR.yellow, "Press any key to exit")
    event.pull("key_down")
    return false
  end
  
  local btnNext = drawButton(w / 2 - 18, h - 6, 15, "Next", COLOR.darkGreen)
  local btnCancel = drawButton(w / 2 + 3, h - 6, 15, "Cancel", COLOR.darkRed)
  
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
  drawBox(8, 2, w - 16, h - 4, "Select Installation Disk")
  
  centerText(6, COLOR.white, "Choose where to install FixOS 2.0")
  centerText(8, COLOR.yellow, "WARNING: Selected disk will be formatted!")
  
  local disks = listDisks()
  
  if #disks == 0 then
    centerText(12, COLOR.red, "No suitable disks found!")
    centerText(14, COLOR.lightGray, "Press any key to exit")
    event.pull("key_down")
    return nil
  end
  
  local buttons = {}
  local startY = 11
  
  for i, disk in ipairs(disks) do
    local sizeText = string.format("%.1f MB", disk.size / (1024 * 1024))
    local label = string.format("%d. %s [%s]", i, disk.label, sizeText)
    if disk.readOnly then label = label .. " (READ-ONLY)" end
    
    local btnColor = disk.readOnly and COLOR.gray or COLOR.lightGray
    local btn = drawButton(12, startY + (i - 1) * 4, w - 24, label, btnColor)
    btn.disk = disk
    table.insert(buttons, btn)
  end
  
  local btnBack = drawButton(w / 2 - 8, h - 6, 15, "Back", COLOR.gray)
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
    elseif ev == "key_down" then
      if _ == 1 then return nil end
      if _ >= 2 and _ <= 10 then
        local idx = _ - 1
        if disks[idx] and not disks[idx].readOnly then return disks[idx] end
      end
    end
  end
end

local function confirmFormatScreen(disk)
  clearScreen()
  drawBox(10, 8, w - 20, 14, "Confirm Format")
  
  centerText(12, COLOR.white, "You are about to format:")
  centerText(14, COLOR.yellow, disk.label)
  centerText(15, COLOR.lightGray, "(" .. disk.address:sub(1, 8) .. ")")
  centerText(17, COLOR.red, "ALL DATA WILL BE LOST!")
  centerText(19, COLOR.white, "Do you want to continue?")
  
  local btnYes = drawButton(w / 2 - 18, 21, 15, "Yes", COLOR.darkGreen)
  local btnNo = drawButton(w / 2 + 3, 21, 15, "No", COLOR.darkRed)
  
  while true do
    local ev, _, x, y = event.pull()
    if ev == "touch" then
      if isInButton(btnYes, x, y) then return true
      elseif isInButton(btnNo, x, y) then return false end
    elseif ev == "key_down" then
      if _ == 21 then return true end
      if _ == 49 then return false end
      if _ == 1 then return false end
    end
  end
end

local function installScreen(disk)
  clearScreen()
  drawBox(8, 2, w - 16, h - 4, "Installing FixOS 2.0")
  
  local proxy = component.proxy(disk.address)
  
  -- Formatting
  centerText(8, COLOR.white, "Step 1/2: Formatting disk...")
  centerText(10, COLOR.lightGray, disk.label)
  drawProgressBar(15, 12, w - 30, 0)
  os.sleep(0.5)
  
  local ok, err = formatDisk(disk.address)
  if not ok then
    centerText(15, COLOR.red, "Format failed: " .. tostring(err))
    centerText(17, COLOR.lightGray, "Press any key to exit")
    event.pull("key_down")
    return false
  end
  
  drawProgressBar(15, 12, w - 30, 0.5)
  centerText(14, COLOR.green, "Disk formatted successfully!")
  os.sleep(1)
  
  -- Downloading files
  centerText(8, COLOR.white, "Step 2/2: Downloading files...        ")
  
  local total = #FILES
  
  for i, file in ipairs(FILES) do
    centerText(10, COLOR.lightGray, file.path .. string.rep(" ", 50))
    
    local progress = (i - 1) / total
    drawProgressBar(15, 12, w - 30, 0.5 + progress * 0.5)
    
    centerText(14, COLOR.yellow, "Downloading...        ")
    local url = REPO_URL .. "/" .. file.path
    local data, downloadErr = downloadFile(url)
    
    if not data then
      centerText(16, COLOR.red, "Download failed: " .. tostring(downloadErr))
      centerText(18, COLOR.lightGray, "Press any key to exit")
      event.pull("key_down")
      return false
    end
    
    centerText(14, COLOR.yellow, "Writing to disk...    ")
    local writeOk, writeErr = writeFileToDisk(proxy, file.target, data)
    
    if not writeOk then
      centerText(16, COLOR.red, "Write failed: " .. tostring(writeErr))
      centerText(18, COLOR.lightGray, "Press any key to exit")
      event.pull("key_down")
      return false
    end
    
    os.sleep(0.2)
  end
  
  drawProgressBar(15, 12, w - 30, 1.0)
  centerText(14, COLOR.green, "Installation complete!     ")
  
  computer.setBootAddress(disk.address)
  os.sleep(1.5)
  return true
end

local function finishScreen()
  clearScreen()
  drawBox(10, 6, w - 20, 16, "Installation Complete")
  
  centerText(10, COLOR.green, "FixOS 2.0 installed successfully!")
  centerText(13, COLOR.white, "The computer will now reboot")
  centerText(14, COLOR.white, "and start FixOS 2.0")
  centerText(17, COLOR.cyan, "Enjoy your retro OS experience!")
  centerText(20, COLOR.lightGray, "Rebooting in 5 seconds...")
  
  for i = 5, 1, -1 do
    centerText(20, COLOR.lightGray, string.format("Rebooting in %d seconds...  ", i))
    os.sleep(1)
  end
  
  computer.shutdown(true)
end

-- MAIN
local function main()
  if not welcomeScreen() then
    clearScreen()
    centerText(h / 2, COLOR.white, "Installation cancelled")
    os.sleep(1)
    return
  end
  
  local disk = selectDiskScreen()
  if not disk then
    clearScreen()
    centerText(h / 2, COLOR.white, "Installation cancelled")
    os.sleep(1)
    return
  end
  
  if not confirmFormatScreen(disk) then
    clearScreen()
    centerText(h / 2, COLOR.white, "Installation cancelled")
    os.sleep(1)
    return
  end
  
  if not installScreen(disk) then return end
  
  finishScreen()
end

local ok, err = pcall(main)
if not ok then
  clearScreen()
  centerText(h / 2 - 1, COLOR.red, "Installer Error:")
  centerText(h / 2, COLOR.white, tostring(err))
  centerText(h / 2 + 2, COLOR.lightGray, "Press any key to exit")
  event.pull("key_down")
end