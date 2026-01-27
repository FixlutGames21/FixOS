-- installer.lua
-- FixOS 2000 Installer (ВИПРАВЛЕНА ВЕРСІЯ)
-- Встановлення: помістіть як /home/installer.lua і запустіть: dofile("/home/installer.lua")

local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")
local term = require("term")
local unicode = _G.unicode

local pull = computer.pullSignal

-- CONFIG
local BASE_RAW = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main"
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

-- GRAPHICS PROXIES
local gpuAddr = component.list("gpu")()
local screenAddr = component.list("screen")()
local gpu = gpuAddr and component.proxy(gpuAddr) or nil
local internetAddr = component.list("internet")()
local internet = internetAddr and component.proxy(internetAddr) or nil
local eepromAddr = component.list("eeprom")()
local eeprom = eepromAddr and component.proxy(eepromAddr) or nil

-- UTILS
local function txtlen(s)
  if unicode and unicode.len then return unicode.len(s) else return #s end
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
    pcall(gpu.setResolution, gpu, w, h)
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
  local w, _ = resolution()
  local x = math.floor(w / 2 - txtlen(text) / 2)
  drawText(x, row, color, text)
end

-- Завантаження з GitHub (виправлена версія)
local function fetch_from_github(path)
  if not internet then
    return nil, "No internet card found"
  end
  
  local url = BASE_RAW .. "/" .. path
  local ok, handle = pcall(internet.request, internet, url)
  
  if not ok or not handle then
    return nil, "Request failed: " .. tostring(handle)
  end
  
  local data = ""
  local timeout = computer.uptime() + 10 -- 10 секунд таймаут
  
  -- Обробка відповіді (handle може бути функцією або таблицею)
  if type(handle) == "function" then
    -- handle є ітератором
    while true do
      if computer.uptime() > timeout then
        return nil, "Download timeout"
      end
      
      local chunk = handle()
      if not chunk then break end
      data = data .. chunk
    end
  elseif type(handle) == "table" then
    -- handle є таблицею з методами
    while true do
      if computer.uptime() > timeout then
        if handle.close then pcall(handle.close, handle) end
        return nil, "Download timeout"
      end
      
      local chunk, err = handle.read(math.huge)
      if not chunk then
        if err then
          if handle.close then pcall(handle.close, handle) end
          return nil, "Read error: " .. tostring(err)
        end
        break
      end
      data = data .. chunk
    end
    
    if handle.close then pcall(handle.close, handle) end
  end
  
  if data == "" then
    return nil, "Empty response"
  end
  
  -- Перевірка на HTML помилки (404 тощо)
  if data:match("^%s*<!") or data:match("^%s*<html") then
    return nil, "File not found (404)"
  end
  
  return data
end

-- Запис файлу
local function write_file(path, content)
  if type(content) ~= "string" then
    return false, "Content is not a string"
  end
  
  local dir = path:match("(.+)/[^/]+$")
  if dir and not filesystem.exists(dir) then
    local ok, err = filesystem.makeDirectory(dir)
    if not ok then
      return false, "Cannot create directory: " .. tostring(err)
    end
  end
  
  local f, err = io.open(path, "w")
  if not f then
    return false, "Cannot open file: " .. tostring(err)
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

-- Заголовок вікна
local function draw_header(title)
  local w, _ = resolution()
  local titleBg = 0x000080
  local titleFg = 0xFFFFFF
  pcall(function()
    gpu.setBackground(titleBg)
    gpu.fill(1, 1, w, 3, " ")
    gpu.setForeground(titleFg)
    gpu.set(2, 2, " FixOS 2000 Setup - " .. tostring(title))
    gpu.setBackground(0x000000)
  end)
end

-- EULA GUI
local function eula_gui()
  clearScreen(0x000080)
  draw_header("License Agreement")
  
  centerY(6, 0xFFFFFF, "End User License Agreement - FixOS 2000")
  centerY(8, 0xFFFFFF, "By installing this software you agree to the terms.")
  centerY(10, 0xFFFFFF, "Click Accept to continue or Reject to cancel.")
  
  BUTTONS = {}
  drawButton("accept", 24, 14, 14, 3, 0x00AA00, 0xFFFFFF, "Accept")
  drawButton("reject", 46, 14, 14, 3, 0xAA0000, 0xFFFFFF, "Reject")
  
  while true do
    local ev = {pull(0.5)}
    local evname = ev[1]
    
    if evname == "touch" or evname == "mouse_click" then
      local x, y = ev[3], ev[4]
      local id = hitButton(x, y)
      
      if id == "accept" then
        clearScreen(0x000080)
        centerY(12, 0x00FF00, "License accepted. Continuing...")
        os.sleep(1.0)
        return true
      elseif id == "reject" then
        clearScreen(0x000080)
        centerY(12, 0xFF4444, "Installation cancelled.")
        os.sleep(1.2)
        return false
      end
    elseif evname == "key_down" then
      local key = ev[4]
      if key == 28 then return true end -- Enter
      if key == 1 then return false end -- Esc
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
      info.readOnly = not not readOnly
      
      local ok4, total = pcall(proxy.spaceTotal, proxy)
      info.spaceTotal = ok4 and total or 0
      
      -- Пропускаємо tmpfs і дуже малі диски
      if info.spaceTotal > 100000 then
        table.insert(list, info)
      end
    end
  end
  
  table.sort(list, function(a, b)
    return (a.spaceTotal or 0) > (b.spaceTotal or 0)
  end)
  
  return list
end

local function humanSize(n)
  if not n or n <= 0 then return "??" end
  if n > 1024 * 1024 then return string.format("%.1fMB", n / 1024 / 1024) end
  if n > 1024 then return string.format("%.1fKB", n / 1024) end
  return tostring(n) .. "B"
end

-- Вибір диска
local function choose_disk_gui()
  clearScreen(0x000080)
  draw_header("Choose Installation Disk")
  
  centerY(5, 0xFFFFFF, "Select target disk for installation")
  
  local list = list_filesystems()
  if #list == 0 then
    centerY(8, 0xFFAAAA, "No suitable filesystem found.")
    centerY(10, 0xFFFFFF, "Press any key to exit.")
    pull()
    return nil
  end
  
  BUTTONS = {}
  local startY = 8
  
  for i, info in ipairs(list) do
    local label = string.format("%d) %s [%s]", i, info.label, humanSize(info.spaceTotal))
    if info.readOnly then label = label .. " (READ-ONLY)" end
    
    drawButton("disk" .. i, 10, startY + (i - 1) * 3, 60, 2,
               info.readOnly and 0x777777 or 0xDDDDDD, 0x000000, label)
  end
  
  centerY(startY + #list * 3 + 1, 0xFFFFFF, "Click disk or press 1-9. ESC to cancel.")
  
  while true do
    local ev = {pull(0.5)}
    
    if ev[1] == "touch" or ev[1] == "mouse_click" then
      local x, y = ev[3], ev[4]
      local id = hitButton(x, y)
      
      if id and id:match("^disk(%d+)$") then
        local idx = tonumber(id:match("%d+"))
        local sel = list[idx]
        
        if sel and sel.readOnly then
          centerY(startY + #list * 3 + 3, 0xFF4444, "This disk is read-only!")
          os.sleep(1.5)
        else
          return sel.address
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

-- Форматування диска (ВИПРАВЛЕНА ВЕРСІЯ)
local function format_target(addr)
  -- Якщо це поточний диск, не форматуємо його повністю
  local currentRoot = filesystem.get("/")
  if currentRoot and currentRoot.address == addr then
    return true -- Не чіпаємо поточний диск
  end
  
  local ok, proxy = pcall(component.proxy, addr)
  if not ok or not proxy then
    return false, "Cannot access filesystem"
  end
  
  -- Видаляємо тільки конфліктуючі папки
  local dirs = {"system", "boot", "bin"}
  for _, dir in ipairs(dirs) do
    local path = "/" .. dir
    if proxy.exists(path) then
      pcall(proxy.remove, path)
    end
  end
  
  return true
end

-- Встановлення файлів (ВИПРАВЛЕНА ВЕРСІЯ)
local function install_to_target(addr)
  local total = #FILES
  
  for i, rel in ipairs(FILES) do
    centerY(9, 0xFFFFFF, string.format("Downloading %d/%d: %s", i, total, rel))
    
    -- Завантаження файлу
    local data, err = fetch_from_github(rel)
    if not data then
      centerY(11, 0xFFAAAA, "Download failed: " .. tostring(err))
      os.sleep(2)
      return false, "Download failed: " .. tostring(err)
    end
    
    -- Запис файлу у поточну файлову систему
    local full = "/" .. rel
    local okw, werr = write_file(full, data)
    if not okw then
      centerY(11, 0xFFAAAA, "Write failed: " .. tostring(werr))
      os.sleep(2)
      return false, "Write failed: " .. tostring(werr)
    end
    
    -- Прогрес бар
    local pct = i / total
    local barW = math.floor(pct * 60)
    
    if gpu then
      pcall(function()
        gpu.setBackground(0x00FF00)
        gpu.fill(10, 13, barW, 1, " ")
        gpu.setBackground(0x000080)
      end)
      centerY(15, 0xFFFFFF, string.format("%.0f%%", pct * 100))
    end
    
    os.sleep(0.1)
  end
  
  -- Налаштування EEPROM для завантаження з цього диска
  if eeprom and addr then
    pcall(function()
      eeprom.setData(addr)
      centerY(17, 0xFFFF00, "Boot device configured.")
    end)
    os.sleep(0.5)
  end
  
  return true
end

-- Головний цикл
local function main()
  safeBind()
  setResolution(100, 36)
  clearScreen(0x000080)
  draw_header("Welcome")
  
  centerY(5, 0xFFFFFF, "Welcome to FixOS 2000 Installer")
  centerY(7, 0xFFFFFF, "GUI Setup - Use mouse or keyboard")
  centerY(9, 0xAAAAAA, "Press ESC at any time to cancel")
  
  BUTTONS = {}
  drawButton("start_install", 35, 16, 18, 3, 0x00AA00, 0xFFFFFF, "Install")
  drawButton("quit", 35, 20, 18, 3, 0xAA0000, 0xFFFFFF, "Cancel")
  
  while true do
    local ev = {pull(0.5)}
    
    if ev[1] == "touch" or ev[1] == "mouse_click" then
      local x, y = ev[3], ev[4]
      local id = hitButton(x, y)
      
      if id == "start_install" then
        -- EULA
        if not eula_gui() then
          clearScreen(0x000080)
          centerY(12, 0xFFFFFF, "Installation cancelled.")
          os.sleep(1)
          return
        end
        
        -- Вибір диска
        local target = choose_disk_gui()
        if not target then
          clearScreen(0x000080)
          centerY(12, 0xFFFFFF, "No disk selected.")
          os.sleep(1)
          return
        end
        
        -- Підтвердження
        clearScreen(0x000080)
        draw_header("Confirm Installation")
        centerY(8, 0xFFFFFF, "Ready to install FixOS 2000")
        centerY(10, 0xFFFF00, "This will modify the selected disk.")
        
        BUTTONS = {}
        drawButton("confirm", 25, 14, 16, 3, 0x00AA00, 0xFFFFFF, "Continue")
        drawButton("cancel", 45, 14, 16, 3, 0xAA0000, 0xFFFFFF, "Cancel")
        
        while true do
          local e = {pull(0.5)}
          
          if e[1] == "touch" or e[1] == "mouse_click" then
            local xx, yy = e[3], e[4]
            local bid = hitButton(xx, yy)
            
            if bid == "confirm" then
              -- Форматування
              clearScreen(0x000080)
              draw_header("Installing")
              centerY(8, 0xFFFFFF, "Preparing disk...")
              
              local okf, ferr = format_target(target)
              if not okf then
                clearScreen(0x000080)
                centerY(10, 0xFF4444, "Format failed: " .. tostring(ferr))
                centerY(12, 0xFFFFFF, "Press any key to exit.")
                pull()
                return
              end
              
              -- Встановлення
              centerY(8, 0xFFFFFF, "Installing files...")
              local oki, ierr = install_to_target(target)
              
              if not oki then
                clearScreen(0x000080)
                centerY(10, 0xFF4444, "Installation failed!")
                centerY(12, 0xFFAAAA, tostring(ierr))
                centerY(14, 0xFFFFFF, "Press any key to exit.")
                pull()
                return
              end
              
              -- Успіх
              clearScreen(0x000080)
              centerY(10, 0x00FF00, "Installation completed successfully!")
              centerY(12, 0xFFFFFF, "FixOS 2000 is ready.")
              centerY(14, 0xFFFF00, "Rebooting in 3 seconds...")
              os.sleep(3)
              computer.shutdown(true)
              return
              
            elseif bid == "cancel" then
              clearScreen(0x000080)
              centerY(12, 0xFFFFFF, "Installation cancelled.")
              os.sleep(1)
              return
            end
          elseif e[1] == "key_down" then
            if e[4] == 1 then -- ESC
              clearScreen(0x000080)
              centerY(12, 0xFFFFFF, "Cancelled.")
              os.sleep(1)
              return
            end
          end
        end
        
      elseif id == "quit" then
        clearScreen(0x000080)
        centerY(12, 0xFFFFFF, "Installer closed.")
        os.sleep(1)
        return
      end
      
    elseif ev[1] == "key_down" then
      local key = ev[4]
      if key == 1 then -- ESC
        clearScreen(0x000080)
        centerY(12, 0xFFFFFF, "Installer cancelled.")
        os.sleep(1)
        return
      end
    end
  end
end

-- Запуск
local ok, err = pcall(main)
if not ok then
  print("Installer error: " .. tostring(err))
  print("Press any key to exit.")
  pull()
end