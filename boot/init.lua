-- FixOS 4.0.1 - init.lua
-- Повна переробка: чистий, надійний, без ризику обрізання

-- ============================================================
-- КРОК 1: Безпечний виклик компонентів
-- ============================================================
local function safeCall(addr, method, ...)
  local ok, a, b, c, d = pcall(component.invoke, addr, method, ...)
  if ok then return a, b, c, d end
  return nil
end

-- ============================================================
-- КРОК 2: Знайти GPU та Screen
-- ============================================================
local gpuAddr    = component.list("gpu",    true)()
local screenAddr = component.list("screen", true)()

-- ============================================================
-- КРОК 3: Консоль для виводу повідомлень під час завантаження
-- ============================================================
local consoleY = 1

local function consolePrint(msg)
  if gpuAddr and screenAddr then
    safeCall(gpuAddr, "set", 2, consoleY, tostring(msg))
    consoleY = consoleY + 1
  end
end

local function consoleClear()
  if gpuAddr and screenAddr then
    safeCall(gpuAddr, "fill", 1, 1, 80, 25, " ")
    consoleY = 1
  end
end

-- ============================================================
-- КРОК 4: Ініціалізація екрану
-- ============================================================
if gpuAddr and screenAddr then
  safeCall(gpuAddr, "bind", screenAddr)

  local maxW, maxH = safeCall(gpuAddr, "maxResolution")
  if maxW and maxH then
    local w = math.min(80, maxW)
    local h = math.min(25, maxH)
    safeCall(gpuAddr, "setResolution", w, h)
  end

  safeCall(gpuAddr, "setBackground", 0x000000)
  safeCall(gpuAddr, "setForeground", 0x00FF00)
  consoleClear()

  safeCall(gpuAddr, "set", 2, 1, "FixOS 4.0.1 - Bootloader")
  safeCall(gpuAddr, "set", 2, 2, string.rep("-", 40))
  consoleY = 4

  computer.beep(440, 0.05)
end

-- ============================================================
-- КРОК 5: Глобальна функція print
-- ============================================================
_G.print = function(...)
  local parts = {...}
  local line  = ""
  for i = 1, #parts do
    line = line .. tostring(parts[i])
    if i < #parts then line = line .. "  " end
  end
  consolePrint(line)
end

-- ============================================================
-- КРОК 6: Глобальна функція error (зупиняє систему)
-- ============================================================
_G.error = function(msg, level)
  if gpuAddr and screenAddr then
    safeCall(gpuAddr, "setBackground", 0x0000CC)
    safeCall(gpuAddr, "setForeground", 0xFFFFFF)
    safeCall(gpuAddr, "fill", 1, 1, 80, 25, " ")
    safeCall(gpuAddr, "set", 30, 10, "Unrecoverable Error")
    safeCall(gpuAddr, "set", 5,  12, "init.lua: " .. tostring(msg))
    safeCall(gpuAddr, "set", 20, 15, "Press any key to shutdown")
  end
  computer.beep(200, 0.5)
  computer.pullSignal(10)
  computer.shutdown()
end

-- ============================================================
-- КРОК 7: Розширений API компонентів
-- ============================================================
consolePrint("Initializing component API...")

local _rawComponent = component  -- зберігаємо оригінал

local comp = {}
comp.list    = _rawComponent.list
comp.type    = _rawComponent.type
comp.slot    = _rawComponent.slot
comp.methods = _rawComponent.methods
comp.invoke  = _rawComponent.invoke
comp.doc     = _rawComponent.doc

function comp.proxy(address)
  if not address then return nil, "address is nil" end
  local t = _rawComponent.type(address)
  if not t then return nil, "no component at address" end
  local p = { address = address, type = t }
  local methods = _rawComponent.methods(address)
  if methods then
    for name in pairs(methods) do
      p[name] = function(...)
        return _rawComponent.invoke(address, name, ...)
      end
    end
  end
  return p
end

function comp.get(partialAddr, wantedType)
  for addr in _rawComponent.list(wantedType or "") do
    if addr:sub(1, #partialAddr) == partialAddr then
      return addr
    end
  end
  return nil, "not found"
end

function comp.isAvailable(typeName)
  return _rawComponent.list(typeName)() ~= nil
end

_G.component = comp

-- ============================================================
-- КРОК 8: Файлова система (boot диск)
-- ============================================================
consolePrint("Mounting boot filesystem...")

local bootAddr = computer.getBootAddress()
if not bootAddr then
  _G.error("computer.getBootAddress() returned nil")
end

local bootFS = comp.proxy(bootAddr)
if not bootFS then
  _G.error("Cannot proxy boot filesystem: " .. tostring(bootAddr))
end

-- ============================================================
-- КРОК 9: loadfile і dofile
-- ============================================================
local function readFile(path)
  if not bootFS.exists(path) then
    return nil, "file not found: " .. tostring(path)
  end

  local handle, err = bootFS.open(path, "r")
  if not handle then
    return nil, "cannot open: " .. tostring(path)
  end

  local chunks = {}
  while true do
    local chunk = bootFS.read(handle, math.huge)
    if not chunk then break end
    chunks[#chunks + 1] = chunk
  end
  bootFS.close(handle)

  return table.concat(chunks)
end

local function loadfile_impl(path)
  local src, err = readFile(path)
  if not src then
    return nil, err
  end

  local fn, compErr = load(src, "=" .. path, "bt", _G)
  if not fn then
    return nil, "compile error in " .. path .. ": " .. tostring(compErr)
  end

  return fn
end

_G.loadfile = loadfile_impl

_G.dofile = function(path)
  local fn, err = loadfile_impl(path)
  if not fn then
    _G.error(tostring(err))
    return
  end
  return fn()
end

-- ============================================================
-- КРОК 10: Система require
-- ============================================================
consolePrint("Setting up require system...")

local _loaded = {}

_G.package = {
  loaded = _loaded,
  path   = "/lib/?.lua;/system/lib/?.lua",
}

_G.require = function(name)
  if type(name) ~= "string" then
    _G.error("require: name must be a string, got " .. type(name))
    return nil
  end

  if _loaded[name] ~= nil then
    return _loaded[name]
  end

  local searchPaths = {
    "/lib/"        .. name .. ".lua",
    "/lib/"        .. name:gsub("%.", "/") .. ".lua",
    "/system/lib/" .. name .. ".lua",
    "/system/lib/" .. name:gsub("%.", "/") .. ".lua",
    "/"            .. name .. ".lua",
  }

  for _, path in ipairs(searchPaths) do
    local ok, exists = pcall(function() return bootFS.exists(path) end)
    if ok and exists then
      local fn, err = loadfile_impl(path)
      if fn then
        local result = fn()
        _loaded[name] = (result ~= nil) and result or true
        return _loaded[name]
      else
        _G.error("require('" .. name .. "'): " .. tostring(err))
        return nil
      end
    end
  end

  _G.error("module '" .. name .. "' not found")
  return nil
end

-- ============================================================
-- КРОК 11: os API
-- ============================================================
consolePrint("Building os API...")

if not _G.os then _G.os = {} end

_G.os.sleep = function(seconds)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then return end
  local target = computer.uptime() + seconds
  repeat
    local remaining = target - computer.uptime()
    if remaining > 0 then
      computer.pullSignal(remaining)
    end
  until computer.uptime() >= target
end

_G.os.time = function()
  return math.floor(computer.uptime())
end

_G.os.clock = function()
  return computer.uptime()
end

_G.os.date = function(format, t)
  t      = t or computer.uptime()
  format = format or "%H:%M:%S"

  local total   = math.floor(t)
  local hours   = math.floor(total / 3600) % 24
  local minutes = math.floor(total / 60)   % 60
  local seconds = total % 60

  if format == "*t" then
    return {
      year  = 2000,
      month = 1,
      day   = 1,
      hour  = hours,
      min   = minutes,
      sec   = seconds,
      wday  = 1,
      yday  = 1,
      isdst = false,
    }
  end

  local result = tostring(format)
  result = result:gsub("%%H", string.format("%02d", hours))
  result = result:gsub("%%M", string.format("%02d", minutes))
  result = result:gsub("%%S", string.format("%02d", seconds))
  result = result:gsub("%%I", string.format("%02d", hours % 12 == 0 and 12 or hours % 12))
  result = result:gsub("%%p", hours < 12 and "AM" or "PM")

  return result
end

_G.os.exit = function()
  computer.shutdown()
end

-- ============================================================
-- КРОК 12: io API (мінімальний, для сумісності)
-- ============================================================
if not _G.io then _G.io = {} end

_G.io.write = function(...)
  local parts = {...}
  local line  = ""
  for i = 1, #parts do line = line .. tostring(parts[i]) end
  consolePrint(line)
end

_G.io.read = function()
  return nil
end

-- ============================================================
-- КРОК 13: Перевірка критичних файлів перед запуском
-- ============================================================
consolePrint("Checking system files...")

local required_files = {
  "/system/ui.lua",
  "/system/desktop.lua",
}

for _, path in ipairs(required_files) do
  local ok, exists = pcall(function() return bootFS.exists(path) end)
  if not ok or not exists then
    _G.error("Missing critical file: " .. path)
  end
end

consolePrint("All system files OK.")

-- ============================================================
-- КРОК 14: Запуск Desktop
-- ============================================================
consolePrint("Launching desktop...")
os.sleep(0.3)

local desktop_fn, desktop_err = loadfile_impl("/system/desktop.lua")
if not desktop_fn then
  _G.error("Failed to load desktop: " .. tostring(desktop_err))
end

local ok, run_err = pcall(desktop_fn)

if not ok then
  -- Записати лог помилки
  local logOk, logH = pcall(bootFS.open, "/crash.log", "w")
  if logOk and logH then
    pcall(bootFS.write, logH, "CRASH @ " .. tostring(computer.uptime()) .. "\n")
    pcall(bootFS.write, logH, tostring(run_err) .. "\n")
    pcall(bootFS.close, logH)
  end
  _G.error("Desktop crashed: " .. tostring(run_err))
end

-- ============================================================
-- КРОК 15: Завершення
-- ============================================================
consolePrint("Desktop exited normally.")
os.sleep(1)
computer.shutdown()