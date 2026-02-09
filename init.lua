-- ==============================================
-- FixOS 2.0 - boot/init.lua (ОСТАТОЧНО ВИПРАВЛЕНО)
-- Правильний bootloader для OpenComputers
-- ==============================================

-- КРИТИЧНО ВАЖЛИВО: В OpenComputers boot/init.lua вже має доступ до component та computer
-- НЕ ТРЕБА робити local component = component!
-- Просто використовуємо їх напряму

-- ====================
-- ЕТАП 1: Базова ініціалізація GPU
-- ====================

local function safeInvoke(addr, method, ...)
  local result = table.pack(pcall(component.invoke, addr, method, ...))
  if result[1] then
    return table.unpack(result, 2, result.n)
  end
  return nil
end

-- Знаходимо GPU та екран
local gpu_addr = component.list("gpu", true)()
local screen_addr = component.list("screen", true)()

-- Функція для виводу тексту (наш власний "print")
local currentY = 1
local function bootPrint(text)
  if gpu_addr and screen_addr then
    safeInvoke(gpu_addr, "set", 2, currentY, tostring(text))
    currentY = currentY + 1
  end
end

if gpu_addr and screen_addr then
  -- Прив'язуємо GPU до екрану
  safeInvoke(gpu_addr, "bind", screen_addr)
  
  -- Встановлюємо розумну роздільну здатність
  local maxW, maxH = safeInvoke(gpu_addr, "maxResolution")
  if maxW and maxH then
    local w = math.min(80, maxW)
    local h = math.min(25, maxH)
    safeInvoke(gpu_addr, "setResolution", w, h)
  end
  
  -- Очищуємо екран
  safeInvoke(gpu_addr, "setBackground", 0x000000)
  safeInvoke(gpu_addr, "setForeground", 0x00FF00)
  safeInvoke(gpu_addr, "fill", 1, 1, 80, 25, " ")
  
  safeInvoke(gpu_addr, "set", 2, 1, "FixOS 2.0 - Booting...")
  currentY = 3
  
  -- Debug beep
  computer.beep(400, 0.1)
end

-- ====================
-- ЕТАП 2: Створення базових функцій
-- ====================

bootPrint("Loading base functions...")

-- Базова функція print
_G.print = function(...)
  local args = {...}
  local text = ""
  for i, v in ipairs(args) do
    text = text .. tostring(v)
    if i < #args then text = text .. "\t" end
  end
  bootPrint(text)
end

-- Базова функція error
_G.error = function(msg, level)
  print("ERROR: " .. tostring(msg))
  computer.beep(1000, 0.2)
  computer.pullSignal(3)
  computer.shutdown()
end

-- ====================
-- ЕТАП 3: Створення component proxy API
-- ====================

bootPrint("Creating component API...")

-- Створюємо зручний API для компонентів
local component_api = {}
component_api.list = component.list
component_api.type = component.type
component_api.slot = component.slot
component_api.methods = component.methods
component_api.invoke = component.invoke
component_api.doc = component.doc

-- Proxy для зручної роботи
function component_api.proxy(address)
  local type = component.type(address)
  if not type then return nil, "no such component" end
  
  local proxy = {address = address, type = type}
  for method in pairs(component.methods(address)) do
    proxy[method] = function(...)
      return component.invoke(address, method, ...)
    end
  end
  
  return proxy
end

-- Знаходження компонента за типом
function component_api.get(address, componentType)
  local type = component.type(address)
  if type == componentType or address:sub(1, #address) == address then
    return address
  end
  return nil, "no such component"
end

function component_api.isAvailable(componentType)
  return component.list(componentType)() ~= nil
end

_G.component = component_api

-- ====================
-- ЕТАП 4: Файлова система
-- ====================

bootPrint("Mounting filesystem...")

local boot_fs_addr = computer.getBootAddress()
local boot_fs = component_api.proxy(boot_fs_addr)

if not boot_fs then
  error("Cannot access boot filesystem!")
end

-- Примітивна функція завантаження файлу
local function loadfile_raw(path)
  if not boot_fs.exists(path) then
    return nil, "file not found: " .. path
  end
  
  local handle = boot_fs.open(path, "r")
  if not handle then
    return nil, "cannot open: " .. path
  end
  
  local data = ""
  repeat
    local chunk = boot_fs.read(handle, math.huge)
    if chunk then
      data = data .. chunk
    end
  until not chunk
  
  boot_fs.close(handle)
  
  -- Компілюємо код
  local func, err = load(data, "=" .. path, "bt", _G)
  if not func then
    return nil, "syntax error: " .. tostring(err)
  end
  
  return func
end

_G.loadfile = loadfile_raw

-- Функція dofile
_G.dofile = function(path)
  local func, err = loadfile(path)
  if not func then
    error(err)
  end
  return func()
end

-- ====================
-- ЕТАП 5: Простий require
-- ====================

bootPrint("Creating require system...")

local loaded = {}
_G.package = {loaded = loaded, path = "/lib/?.lua"}

_G.require = function(name)
  -- Якщо вже завантажено, повертаємо
  if loaded[name] then
    return loaded[name]
  end
  
  -- Шукаємо файл
  local paths = {
    "/lib/" .. name .. ".lua",
    "/lib/" .. name:gsub("%.", "/") .. ".lua",
    "/system/lib/" .. name .. ".lua"
  }
  
  for _, path in ipairs(paths) do
    if boot_fs.exists(path) then
      local func, err = loadfile(path)
      if not func then
        error("Error loading module '" .. name .. "': " .. tostring(err))
      end
      
      local result = func()
      loaded[name] = result or true
      return loaded[name]
    end
  end
  
  error("module '" .. name .. "' not found")
end

-- ====================
-- ЕТАП 6: Базові бібліотеки
-- ====================

-- Додаємо os.sleep
if not _G.os then _G.os = {} end
_G.os.sleep = function(seconds)
  local deadline = computer.uptime() + (seconds or 0)
  repeat
    computer.pullSignal(deadline - computer.uptime())
  until computer.uptime() >= deadline
end

-- Додаємо базовий os.date
_G.os.date = function(format, time)
  time = time or os.time()
  if format == "%H:%M" then
    local hours = math.floor((time / 3600) % 24)
    local minutes = math.floor((time / 60) % 60)
    return string.format("%02d:%02d", hours, minutes)
  end
  return tostring(time)
end

_G.os.time = function()
  return math.floor(computer.uptime())
end

-- ====================
-- ЕТАП 7: Запуск desktop.lua
-- ====================

bootPrint("Starting desktop...")
os.sleep(0.5)

-- Перевіряємо наявність desktop.lua
if not boot_fs.exists("/system/desktop.lua") then
  error("Desktop not found: /system/desktop.lua")
end

-- Завантажуємо та запускаємо
local desktop_func, load_err = loadfile("/system/desktop.lua")
if not desktop_func then
  error("Cannot load desktop: " .. tostring(load_err))
end

local ok, run_err = pcall(desktop_func)
if not ok then
  -- Зберігаємо помилку в лог
  local handle = boot_fs.open("/error.log", "w")
  if handle then
    boot_fs.write(handle, "Desktop error: " .. tostring(run_err))
    boot_fs.close(handle)
  end
  
  error("Desktop crashed: " .. tostring(run_err))
end

-- Якщо desktop завершився - shutdown
print("Desktop exited")
os.sleep(2)
computer.shutdown()