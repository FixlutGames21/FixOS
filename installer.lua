-- ==============================================
-- ВИПРАВЛЕНИЙ BIOS КОД ДЛЯ EEPROM
-- ==============================================
-- ВАЖЛИВО: BIOS не може використовувати require()!
-- Використовуємо тільки component.proxy()

local BIOS_CODE = [[
local component_invoke = component.invoke
local component_list = component.list
local computer_getBootAddress = computer.getBootAddress
local computer_setBootAddress = computer.setBootAddress

-- Отримуємо компоненти без require
local gpu = component_list("gpu")()
local screen = component_list("screen")()

-- Показуємо екран завантаження
if gpu and screen then
  component_invoke(gpu, "bind", screen)
  component_invoke(gpu, "setResolution", 50, 16)
  component_invoke(gpu, "setBackground", 0x000000)
  component_invoke(gpu, "setForeground", 0x00FF00)
  component_invoke(gpu, "fill", 1, 1, 50, 16, " ")
  component_invoke(gpu, "set", 2, 2, "FixOS 2000 BIOS v1.0")
  component_invoke(gpu, "set", 2, 4, "Booting...")
end

-- Отримуємо boot адресу з EEPROM data
local bootAddr = component_invoke(component_list("eeprom")(), "getData")
if not bootAddr or bootAddr == "" then
  bootAddr = computer_getBootAddress()
end

-- Функція завантаження init.lua
local function boot()
  local fs = bootAddr and component_list("filesystem", bootAddr)()
  
  if not fs then
    -- Якщо не знайдено, шукаємо будь-яку filesystem
    fs = component_list("filesystem")()
  end
  
  if not fs then
    error("No filesystem found")
  end
  
  -- Читаємо /boot/init.lua
  local handle = component_invoke(fs, "open", "/boot/init.lua")
  if not handle then
    error("No /boot/init.lua found")
  end
  
  local buffer = ""
  repeat
    local chunk = component_invoke(fs, "read", handle, math.huge)
    if chunk then
      buffer = buffer .. chunk
    end
  until not chunk
  
  component_invoke(fs, "close", handle)
  
  -- Виконуємо init.lua
  local code, err = load(buffer, "=init")
  if not code then
    error("Boot error: " .. tostring(err))
  end
  
  code()
end

-- Запускаємо
local success, err = pcall(boot)
if not success then
  if gpu then
    component_invoke(gpu, "setForeground", 0xFF0000)
    component_invoke(gpu, "set", 2, 8, "Boot failed:")
    component_invoke(gpu, "set", 2, 9, tostring(err))
  end
  error(err)
end
]]

-- ==============================================
-- ФАЙЛ: installer.lua - ПОВНІСТЮ ПЕРЕПИСАНИЙ
-- ==============================================
local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")
local term = require("term")

local pull = computer.pullSignal

-- CONFIG
local GITHUB_USER = "FixlutGames21"
local GITHUB_REPO = "FixOS"
local GITHUB_BRANCH = "main"
local BASE_URL = string.format("https://raw.githubusercontent.com/%s/%s/%s", 
                               GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH)

local FILES = {
  "system/desktop.lua",
  "system/windows.lua",
  "boot/init.lua"
}

-- VERSION FILE
local VERSION_FILE = "version.txt"
local CURRENT_VERSION = "1.0.0"

-- COMPONENTS
local gpuAddr = component.list("gpu")()
local screenAddr = component.list("screen")()
local gpu = gpuAddr and component.proxy(gpuAddr) or nil
local internetAddr = component.list("internet")()
local internet = internetAddr and component.proxy(internetAddr) or nil
local eepromAddr = component.list("eeprom")()
local eeprom = eepromAddr and component.proxy(eepromAddr) or nil

-- UTILS
local function safeBind()
  if not gpu or not screenAddr then return false end
  pcall(gpu.bind, gpu, screenAddr, true)
  return true
end

local function resolution()
  if not gpu then return 80, 25 end
  local ok, w, h = pcall(gpu.getResolution, gpu)
  if ok and w and h then return w, h end
  return 80, 25
end

local function setResolution(w, h)
  if not gpu then return false end
  pcall(function()
    safeBind()
    local maxW, maxH = gpu.maxResolution()
    gpu.setResolution(math.min(w, maxW), math.min(h, maxH))
  end)
  return true
end

local function clearScreen(bg)
  if not gpu then
    term.clear()
    term.setCursor(1, 1)
    return
  end
  pcall(function()
    local w, h = resolution()
    gpu.setBackground(bg or 0x000080)
    gpu.fill(1, 1, w, h, " ")
  end)
end

local function drawText(x, y, color, text)
  if not gpu then
    term.setCursor(math.max(1, x), math.max(1, y))
    io.write(text)
    return
  end
  pcall(function()
    gpu.setForeground(color or 0xFFFFFF)
    gpu.set(x, y, tostring(text))
  end)
end

local function centerY(row, color, text)
  local w = resolution()
  local x = math.floor(w / 2 - #text / 2)
  drawText(math.max(1, x), row, color, text)
end

-- ПОКРАЩЕНЕ ЗАВАНТАЖЕННЯ
local function wget(url)
  if not internet then
    return nil, "No internet card"
  end
  
  for attempt = 1, 3 do
    local handle = internet.request(url)
    
    if handle then
      local result = {}
      local deadline = computer.uptime() + 30
      
      while computer.uptime() < deadline do
        local chunk = handle.read(math.huge)
        
        if chunk then
          table.insert(result, chunk)
        else
          handle.close()
          local data = table.concat(result)
          
          if #data > 0 then
            if data:match("^%s*<!") or data:match("404") then
              return nil, "File not found (404)"
            end
            return data
          else
            break
          end
        end
      end
      
      pcall(handle.close)
    end
    
    if attempt < 3 then
      os.sleep(1)
    end
  end
  
  return nil, "Download failed after 3 attempts"
end

local function fetch_from_github(path)
  return wget(BASE_URL .. "/" .. path)
end

-- Запис файлу
local function write_file(path, content)
  if type(content) ~= "string" then
    return false, "Content is not a string"
  end
  
  local dir = path:match("(.+)/[^/]+$")
  if dir and not filesystem.exists(dir) then
    filesystem.makeDirectory(dir)
  end
  
  local f, err = io.open(path, "w")
  if not f then
    return false, "Cannot open: " .. tostring(err)
  end
  
  f:write(content)
  f:close()
  return true
end

-- BUTTONS
local BUTTONS = {}

local function drawButton(id, x, y, w, h, bg, fg, label)
  if gpu then
    pcall(function()
      gpu.setBackground(bg)
      gpu.fill(x, y, w, h, " ")
      local lx = x + math.floor((w - #label) / 2)
      gpu.setForeground(fg)
      gpu.set(lx, y + math.floor(h / 2), label)
      gpu.setBackground(0x000080)
    end)
  else
    print(("[%s] %s"):format(id, label))
  end
  BUTTONS[id] = {x = x, y = y, w = w, h = h}
end

local function hitButton(x, y)
  for id, b in pairs(BUTTONS) do
    if x >= b.x and x <= b.x + b.w - 1 and y >= b.y and y <= b.y + b.h - 1 then
      return id
    end
  end
  return nil
end

local function draw_header(title)
  local w = resolution()
  pcall(function()
    gpu.setBackground(0x000080)
    gpu.fill(1, 1, w, 3, " ")
    gpu.setForeground(0xFFFFFF)
    gpu.set(2, 2, " FixOS 2000 Setup - " .. tostring(title))
  end)
end

-- Прошивка BIOS - ВИПРАВЛЕНА ВЕРСІЯ
local function flash_bios()
  if not eeprom then
    return false, "No EEPROM found"
  end
  
  clearScreen(0x000080)
  draw_header("Flashing BIOS")
  
  centerY(8, 0xFFFFFF, "Writing FixOS BIOS to EEPROM...")
  centerY(10, 0xFFFF00, "Do not turn off the computer!")
  
  os.sleep(0.5)
  
  -- Встановлюємо код BIOS
  local ok, err = pcall(function()
    eeprom.set(BIOS_CODE)
    eeprom.setLabel("FixOS BIOS")
  end)
  
  if not ok then
    return false, "Flash failed: " .. tostring(err)
  end
  
  centerY(12, 0x00FF00, "BIOS flashed successfully!")
  centerY(13, 0xFFFFFF, "Computer will boot from FixOS now")
  os.sleep(1.5)
  
  return true
end

-- EULA
local function eula_gui()
  clearScreen(0x000080)
  draw_header("License Agreement")
  
  centerY(6, 0xFFFFFF, "FixOS 2000 - End User License Agreement")
  centerY(8, 0xFFFFFF, "By installing you agree to use this software")
  centerY(9, 0xFFFFFF, "for educational and entertainment purposes.")
  centerY(11, 0xFFFFFF, "Press Enter to Accept or Esc to Cancel")
  
  BUTTONS = {}
  drawButton("accept", 28, 15, 14, 3, 0x00AA00, 0xFFFFFF, "Accept")
  drawButton("reject", 44, 15, 14, 3, 0xAA0000, 0xFFFFFF, "Cancel")
  
  while true do
    local ev = {pull(0.5)}
    
    if ev[1] == "touch" then
      local x, y = ev[3], ev[4]
      local id = hitButton(x, y)
      
      if id == "accept" then
        return true
      elseif id == "reject" then
        return false
      end
    elseif ev[1] == "key_down" then
      if ev[4] == 28 then return true end
      if ev[4] == 1 then return false end
    end
  end
end

-- Список дисків
local function list_filesystems()
  local list = {}
  for addr in component.list("filesystem") do
    local ok, proxy = pcall(component.proxy, addr)
    if ok and proxy then
      local info = {address = addr}
      
      local ok2, label = pcall(proxy.getLabel, proxy)
      info.label = (ok2 and label and label ~= "") and label or addr:sub(1, 8)
      
      local ok3, readOnly = pcall(proxy.isReadOnly, proxy)
      info.readOnly = readOnly or false
      
      local ok4, total = pcall(proxy.spaceTotal, proxy)
      info.spaceTotal = ok4 and total or 0
      
      if info.spaceTotal > 100000 and not info.label:match("tmpfs") then
        table.insert(list, info)
      end
    end
  end
  
  table.sort(list, function(a, b)
    return a.spaceTotal > b.spaceTotal
  end)
  
  return list
end

local function humanSize(n)
  if not n or n <= 0 then return "??" end
  if n >= 1024 * 1024 then
    return string.format("%.1fMB", n / (1024 * 1024))
  elseif n >= 1024 then
    return string.format("%.1fKB", n / 1024)
  end
  return tostring(n) .. "B"
end

-- Вибір диска
local function choose_disk_gui()
  clearScreen(0x000080)
  draw_header("Choose Installation Disk")
  
  centerY(5, 0xFFFFFF, "Select target disk for FixOS 2000")
  
  local list = list_filesystems()
  if #list == 0 then
    centerY(8, 0xFFAAAA, "No suitable filesystem found!")
    centerY(10, 0xFFFFFF, "Press any key to exit.")
    pull()
    return nil
  end
  
  BUTTONS = {}
  local startY = 8
  
  for i, info in ipairs(list) do
    local label = string.format("%d) %s [%s]", i, info.label, humanSize(info.spaceTotal))
    if info.readOnly then label = label .. " (READ-ONLY)" end
    
    drawButton("disk" .. i, 8, startY + (i - 1) * 3, 64, 2,
               info.readOnly and 0x555555 or 0xCCCCCC, 0x000000, label)
  end
  
  centerY(startY + #list * 3 + 2, 0xFFFFFF, "Click disk or press 1-9. ESC to cancel.")
  
  while true do
    local ev = {pull(0.5)}
    
    if ev[1] == "touch" then
      local x, y = ev[3], ev[4]
      local id = hitButton(x, y)
      
      if id and id:match("^disk(%d+)$") then
        local idx = tonumber(id:match("%d+"))
        local sel = list[idx]
        
        if sel then
          if sel.readOnly then
            centerY(startY + #list * 3 + 4, 0xFF4444, "Cannot install to read-only disk!")
            os.sleep(1.5)
          else
            return sel.address
          end
        end
      end
    elseif ev[1] == "key_down" then
      local key = ev[4]
      if key == 1 then return nil end
      
      if key >= 2 and key <= 10 then
        local idx = key - 1
        if list[idx] and not list[idx].readOnly then
          return list[idx].address
        end
      end
    end
  end
end

-- Підготовка диска
local function prepare_disk(addr)
  local currentRoot = filesystem.get("/")
  if currentRoot and currentRoot.address == addr then
    return true
  end
  
  local proxy = component.proxy(addr)
  if not proxy then
    return false, "Cannot access disk"
  end
  
  local dirs = {"system", "boot"}
  for _, dir in ipairs(dirs) do
    pcall(proxy.remove, "/" .. dir)
  end
  
  return true
end

-- Встановлення файлів
local function install_files(targetAddr)
  local total = #FILES
  
  for i, rel in ipairs(FILES) do
    clearScreen(0x000080)
    draw_header("Installing FixOS 2000")
    
    centerY(7, 0xFFFFFF, string.format("File %d/%d", i, total))
    centerY(8, 0xAAAAAA, rel)
    
    local pct = (i - 1) / total
    local barW = math.floor(pct * 60)
    if gpu then
      pcall(function()
        gpu.setBackground(0x555555)
        gpu.fill(10, 11, 60, 1, " ")
        gpu.setBackground(0x00FF00)
        gpu.fill(10, 11, barW, 1, " ")
        gpu.setBackground(0x000080)
      end)
    end
    centerY(13, 0xFFFFFF, string.format("%.0f%%", pct * 100))
    
    centerY(15, 0xFFFF00, "Downloading...")
    local data, err = fetch_from_github(rel)
    
    if not data then
      centerY(17, 0xFF4444, "Error: " .. tostring(err))
      os.sleep(2)
      return false, "Download failed: " .. rel
    end
    
    centerY(15, 0xFFFF00, "Writing to disk...    ")
    local ok, werr = write_file("/" .. rel, data)
    
    if not ok then
      centerY(17, 0xFF4444, "Error: " .. tostring(werr))
      os.sleep(2)
      return false, "Write failed: " .. rel
    end
    
    os.sleep(0.1)
  end
  
  -- Створюємо version.txt
  write_file("/version.txt", CURRENT_VERSION)
  
  clearScreen(0x000080)
  draw_header("Installing FixOS 2000")
  centerY(10, 0x00FF00, "All files installed successfully!")
  
  if gpu then
    pcall(function()
      gpu.setBackground(0x00FF00)
      gpu.fill(10, 12, 60, 1, " ")
      gpu.setBackground(0x000080)
    end)
  end
  centerY(14, 0xFFFFFF, "100%")
  os.sleep(1)
  
  if eeprom and targetAddr then
    centerY(16, 0xFFFF00, "Configuring boot device...")
    pcall(eeprom.setData, targetAddr)
    os.sleep(0.5)
  end
  
  return true
end

-- Головна функція
local function main()
  if not internet then
    print("ERROR: Internet Card required!")
    print("Install an Internet Card and try again.")
    print("Press any key to exit.")
    pull()
    return
  end
  
  safeBind()
  setResolution(80, 30)
  
  clearScreen(0x000080)
  draw_header("Welcome")
  
  centerY(5, 0xFFFFFF, "Welcome to FixOS 2000 Installer")
  centerY(7, 0xAAAAAA, "Version 1.0 - Windowed Edition")
  centerY(9, 0xFFFFFF, "This will install FixOS with:")
  centerY(10, 0xFFFFFF, "- Windowed interface")
  centerY(11, 0xFFFFFF, "- System update support")
  centerY(12, 0xFFFFFF, "- Custom BIOS")
  
  BUTTONS = {}
  drawButton("install", 25, 16, 20, 3, 0x00AA00, 0xFFFFFF, "Install")
  drawButton("bios_only", 25, 20, 20, 3, 0x0088FF, 0xFFFFFF, "Flash BIOS Only")
  drawButton("quit", 25, 24, 20, 3, 0xAA0000, 0xFFFFFF, "Exit")
  
  while true do
    local ev = {pull(0.5)}
    
    if ev[1] == "touch" then
      local x, y = ev[3], ev[4]
      local id = hitButton(x, y)
      
      if id == "install" then
        if not eula_gui() then
          clearScreen(0x000080)
          centerY(12, 0xFFFFFF, "Installation cancelled.")
          os.sleep(1)
          return
        end
        
        local target = choose_disk_gui()
        if not target then
          clearScreen(0x000080)
          centerY(12, 0xFFFFFF, "No disk selected.")
          os.sleep(1)
          return
        end
        
        clearScreen(0x000080)
        draw_header("Preparing")
        centerY(10, 0xFFFFFF, "Preparing disk...")
        
        local ok, err = prepare_disk(target)
        if not ok then
          clearScreen(0x000080)
          centerY(10, 0xFF4444, "Prepare failed: " .. tostring(err))
          os.sleep(2)
          return
        end
        
        ok, err = install_files(target)
        if not ok then
          clearScreen(0x000080)
          centerY(10, 0xFF4444, "Installation failed!")
          centerY(12, 0xFFAAAA, tostring(err))
          os.sleep(3)
          return
        end
        
        ok, err = flash_bios()
        if not ok then
          clearScreen(0x000080)
          centerY(10, 0xFFFF00, "Warning: BIOS flash failed")
          centerY(12, 0xFFAAAA, tostring(err))
          centerY(14, 0xFFFFFF, "System installed but may not boot.")
          os.sleep(3)
        end
        
        clearScreen(0x000080)
        draw_header("Complete")
        centerY(9, 0x00FF00, "FixOS 2000 installed successfully!")
        centerY(11, 0xFFFFFF, "Custom BIOS has been flashed.")
        centerY(13, 0xFFFF00, "Rebooting in 3 seconds...")
        os.sleep(3)
        computer.shutdown(true)
        return
        
      elseif id == "bios_only" then
        local ok, err = flash_bios()
        if ok then
          clearScreen(0x000080)
          centerY(12, 0x00FF00, "BIOS flashed successfully!")
          os.sleep(2)
        else
          clearScreen(0x000080)
          centerY(12, 0xFF4444, "Flash failed: " .. tostring(err))
          os.sleep(2)
        end
        main()
        return
        
      elseif id == "quit" then
        clearScreen(0x000080)
        centerY(12, 0xFFFFFF, "Installer closed.")
        os.sleep(1)
        return
      end
    elseif ev[1] == "key_down" then
      if ev[4] == 1 then
        clearScreen(0x000080)
        centerY(12, 0xFFFFFF, "Cancelled.")
        os.sleep(1)
        return
      end
    end
  end
end

local ok, err = pcall(main)
if not ok then
  clearScreen(0x000000)
  print("Installer Error:")
  print(tostring(err))
  print("")
  print("Press any key to exit.")
  pull()
end