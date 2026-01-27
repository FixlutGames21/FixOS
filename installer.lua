-- installer.lua
-- FixOS 2000 Installer - ПОКРАЩЕНА ВЕРСІЯ
-- З кастомною прошивкою BIOS та надійним завантаженням
-- Встановлення: dofile("/home/installer.lua")

local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")
local term = require("term")
local unicode = _G.unicode or {}

local pull = computer.pullSignal

-- CONFIG
local GITHUB_USER = "FixlutGames21"
local GITHUB_REPO = "FixOS"
local GITHUB_BRANCH = "main"
local BASE_URL = string.format("https://raw.githubusercontent.com/%s/%s/%s", 
                               GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH)

local FILES = {
  "system/gui/win2000ui.lua",
  "system/desktop.lua",
  "system/startmenu.lua",
  "system/settings.lua",
  "boot/init.lua",
  "bin/ls.lua",
  "bin/echo.lua",
  "bin/cls.lua",
  "bin/edit.lua",
  "bin/calc.lua"
}

-- BIOS код для EEPROM
local BIOS_CODE = [[
local component = require("component")
local computer = require("computer")

local bootAddr = component.eeprom.getData()
local gpu = component.list("gpu")()
local screen = component.list("screen")()

if gpu and screen then
  local g = component.proxy(gpu)
  g.bind(screen)
  g.setResolution(50, 16)
  g.setBackground(0x000000)
  g.setForeground(0x00FF00)
  g.fill(1, 1, 50, 16, " ")
  g.set(2, 2, "FixOS 2000 BIOS")
  g.set(2, 4, "Booting from: " .. (bootAddr or "auto"):sub(1, 8))
end

local function tryBoot(addr)
  local fs = component.proxy(addr)
  if not fs then return false end
  
  local handle = fs.open("/boot/init.lua")
  if not handle then return false end
  
  local buffer = ""
  repeat
    local data = fs.read(handle, math.huge)
    buffer = buffer .. (data or "")
  until not data
  fs.close(handle)
  
  local fn, err = load(buffer, "=init")
  if not fn then
    error("Boot error: " .. tostring(err))
  end
  
  fn()
  return true
end

-- Спроба завантаження
local success = false
if bootAddr then
  success = pcall(tryBoot, bootAddr)
end

if not success then
  local bootFS = computer.getBootAddress()
  if bootFS then
    success = pcall(tryBoot, bootFS)
  end
end

if not success then
  error("No bootable device found")
end
]]

-- COMPONENTS
local gpuAddr = component.list("gpu")()
local screenAddr = component.list("screen")()
local gpu = gpuAddr and component.proxy(gpuAddr) or nil
local internetAddr = component.list("internet")()
local internet = internetAddr and component.proxy(internetAddr) or nil
local eepromAddr = component.list("eeprom")()
local eeprom = eepromAddr and component.proxy(eepromAddr) or nil

-- UTILS
local function txtlen(s)
  if unicode.len then return unicode.len(s) end
  return #s
end

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
  local x = math.floor(w / 2 - txtlen(text) / 2)
  drawText(math.max(1, x), row, color, text)
end

-- ПОКРАЩЕНЕ ЗАВАНТАЖЕННЯ З GITHUB
local function wget(url)
  if not internet then
    return nil, "No internet card"
  end
  
  -- Retry логіка
  local maxRetries = 3
  local retryDelay = 1
  
  for attempt = 1, maxRetries do
    local handle = internet.request(url)
    
    if handle then
      local result = {}
      local deadline = computer.uptime() + 30 -- 30 секунд на файл
      
      while computer.uptime() < deadline do
        local chunk = handle.read(math.huge)
        
        if chunk then
          table.insert(result, chunk)
        else
          -- nil означає кінець
          handle.close()
          local data = table.concat(result)
          
          if #data > 0 then
            -- Перевірка на 404
            if data:match("^%s*<!") or data:match("404: Not Found") then
              return nil, "File not found (404)"
            end
            return data
          else
            break -- Пуста відповідь, спробуємо ще раз
          end
        end
      end
      
      pcall(handle.close)
    end
    
    -- Якщо не вдалося - чекаємо і пробуємо знову
    if attempt < maxRetries then
      os.sleep(retryDelay)
    end
  end
  
  return nil, "Download failed after " .. maxRetries .. " attempts"
end

local function fetch_from_github(path)
  local url = BASE_URL .. "/" .. path
  return wget(url)
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
      local lx = x + math.floor((w - txtlen(label)) / 2)
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

-- Прошивка EEPROM
local function flash_bios()
  if not eeprom then
    return false, "No EEPROM found"
  end
  
  clearScreen(0x000080)
  draw_header("Flashing BIOS")
  
  centerY(8, 0xFFFFFF, "Writing custom BIOS to EEPROM...")
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
  os.sleep(1)
  
  return true
end

-- EULA
local function eula_gui()
  clearScreen(0x000080)
  draw_header("License Agreement")
  
  centerY(6, 0xFFFFFF, "FixOS 2000 - End User License Agreement")
  centerY(8, 0xFFFFFF, "By installing you agree to use this software")
  centerY(9, 0xFFFFFF, "for educational and entertainment purposes.")
  centerY(11, 0xFFFFFF, "Click Accept to continue or Reject to cancel.")
  
  BUTTONS = {}
  drawButton("accept", 24, 15, 14, 3, 0x00AA00, 0xFFFFFF, "Accept")
  drawButton("reject", 46, 15, 14, 3, 0xAA0000, 0xFFFFFF, "Reject")
  
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
      if ev[4] == 28 then return true end -- Enter
      if ev[4] == 1 then return false end -- Esc
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
      
      -- Фільтр: тільки великі диски
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
  
  centerY(startY + #list * 3 + 2, 0xFFFFFF, "Click disk or press number. ESC to cancel.")
  
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
      if key == 1 then return nil end -- Esc
      
      -- Цифри 1-9
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
    return true -- Поточний диск
  end
  
  local proxy = component.proxy(addr)
  if not proxy then
    return false, "Cannot access disk"
  end
  
  -- Видаляємо старі файли FixOS
  local dirs = {"system", "boot", "bin"}
  for _, dir in ipairs(dirs) do
    pcall(proxy.remove, "/" .. dir)
  end
  
  return true
end

-- Встановлення файлів
local function install_files(targetAddr)
  local total = #FILES
  local installed = 0
  
  for i, rel in ipairs(FILES) do
    -- Показуємо прогрес
    clearScreen(0x000080)
    draw_header("Installing FixOS 2000")
    
    centerY(7, 0xFFFFFF, string.format("File %d/%d", i, total))
    centerY(8, 0xAAAAAA, rel)
    
    -- Прогрес бар
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
    
    -- Завантаження
    centerY(15, 0xFFFF00, "Downloading...")
    local data, err = fetch_from_github(rel)
    
    if not data then
      centerY(17, 0xFF4444, "Error: " .. tostring(err))
      os.sleep(2)
      return false, "Download failed: " .. rel
    end
    
    -- Запис
    centerY(15, 0xFFFF00, "Writing to disk...    ")
    local ok, werr = write_file("/" .. rel, data)
    
    if not ok then
      centerY(17, 0xFF4444, "Error: " .. tostring(werr))
      os.sleep(2)
      return false, "Write failed: " .. rel
    end
    
    installed = installed + 1
    os.sleep(0.1)
  end
  
  -- Фінальний прогрес
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
  
  -- Налаштування EEPROM
  if eeprom and targetAddr then
    centerY(16, 0xFFFF00, "Configuring boot device...")
    pcall(eeprom.setData, targetAddr)
    os.sleep(0.5)
  end
  
  return true
end

-- Головна функція
local function main()
  -- Перевірка інтернету
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
  centerY(7, 0xAAAAAA, "Version 1.0 - Classic Edition")
  centerY(9, 0xFFFFFF, "This will install FixOS on your computer")
  centerY(10, 0xFFFFFF, "and flash a custom BIOS to EEPROM.")
  
  BUTTONS = {}
  drawButton("install", 25, 14, 20, 3, 0x00AA00, 0xFFFFFF, "Install")
  drawButton("bios_only", 25, 18, 20, 3, 0x0088FF, 0xFFFFFF, "Flash BIOS Only")
  drawButton("quit", 25, 22, 20, 3, 0xAA0000, 0xFFFFFF, "Exit")
  
  while true do
    local ev = {pull(0.5)}
    
    if ev[1] == "touch" then
      local x, y = ev[3], ev[4]
      local id = hitButton(x, y)
      
      if id == "install" then
        -- Повна інсталяція
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
        
        -- Підготовка
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
        
        -- Встановлення
        ok, err = install_files(target)
        if not ok then
          clearScreen(0x000080)
          centerY(10, 0xFF4444, "Installation failed!")
          centerY(12, 0xFFAAAA, tostring(err))
          os.sleep(3)
          return
        end
        
        -- Прошивка BIOS
        ok, err = flash_bios()
        if not ok then
          clearScreen(0x000080)
          centerY(10, 0xFFFF00, "Warning: BIOS flash failed")
          centerY(12, 0xFFAAAA, tostring(err))
          centerY(14, 0xFFFFFF, "System installed but may not boot automatically.")
          os.sleep(3)
        end
        
        -- Успіх
        clearScreen(0x000080)
        draw_header("Complete")
        centerY(9, 0x00FF00, "FixOS 2000 installed successfully!")
        centerY(11, 0xFFFFFF, "Custom BIOS has been flashed.")
        centerY(13, 0xFFFF00, "Rebooting in 3 seconds...")
        os.sleep(3)
        computer.shutdown(true)
        return
        
      elseif id == "bios_only" then
        -- Тільки прошивка BIOS
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
      if ev[4] == 1 then -- ESC
        clearScreen(0x000080)
        centerY(12, 0xFFFFFF, "Cancelled.")
        os.sleep(1)
        return
      end
    end
  end
end

-- Запуск з обробкою помилок
local ok, err = pcall(main)
if not ok then
  clearScreen(0x000000)
  print("Installer Error:")
  print(tostring(err))
  print("")
  print("Press any key to exit.")
  pull()
end
