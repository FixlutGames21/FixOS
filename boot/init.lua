-- FixOS 4.0.1 - init.lua
-- Повна переробка: чистий, надійний, без ризику обрізання (STABLE BUILD)

-- ============================================================
-- КРОК 0: Гарантована ініціалізація component API
-- ============================================================
local component = _G.component

if not component then
  local ok, lib = pcall(require, "component")
  if ok and lib then
    component = lib
    _G.component = lib
  end
end

if not component or not component.invoke then
  computer.beep(100, 1)
  error("FATAL: component API not available at boot")
end

-- ============================================================
-- КРОК 1: Безпечний виклик компонентів
-- ============================================================
local function safeCall(addr, method, ...)
  if not component or not component.invoke then return nil end
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
-- КРОК 3: Консоль для виводу повідомлень
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
    safeCall(gpuAddr, "setResolution", math.min(80, maxW), math.min(25, maxH))
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
-- КРОК 5: print
-- ============================================================
_G.print = function(...)
  local t = {...}
  local s = ""
  for i = 1, #t do
    s = s .. tostring(t[i]) .. (i < #t and "  " or "")
  end
  consolePrint(s)
end

-- ============================================================
-- КРОК 6: error
-- ============================================================
_G.error = function(msg)
  if gpuAddr and screenAddr then
    safeCall(gpuAddr, "setBackground", 0x0000CC)
    safeCall(gpuAddr, "setForeground", 0xFFFFFF)
    safeCall(gpuAddr, "fill", 1, 1, 80, 25, " ")
    safeCall(gpuAddr, "set", 28, 10, "Unrecoverable Error")
    safeCall(gpuAddr, "set", 5,  12, tostring(msg))
  end
  computer.beep(200, 0.5)
  computer.pullSignal(10)
  computer.shutdown()
end

-- ============================================================
-- КРОК 7: Component API wrapper
-- ============================================================
consolePrint("Initializing component API...")

local _rawComponent = component
if not _rawComponent then
  _G.error("Component API lost")
end

local comp = {}
comp.list    = _rawComponent.list
comp.type    = _rawComponent.type
comp.slot    = _rawComponent.slot
comp.methods = _rawComponent.methods
comp.invoke  = _rawComponent.invoke
comp.doc     = _rawComponent.doc

function comp.proxy(address)
  if not address then return nil end
  local t = _rawComponent.type(address)
  if not t then return nil end
  local p = { address = address, type = t }

  for name in pairs(_rawComponent.methods(address) or {}) do
    p[name] = function(...)
      return _rawComponent.invoke(address, name, ...)
    end
  end

  return p
end

function comp.isAvailable(typeName)
  return _rawComponent.list(typeName)() ~= nil
end

_G.component = comp

-- ============================================================
-- КРОК 8: Boot filesystem
-- ============================================================
consolePrint("Mounting boot filesystem...")

local bootAddr = computer.getBootAddress()
if not bootAddr then
  _G.error("No boot address")
end

local bootFS = comp.proxy(bootAddr)
if not bootFS then
  _G.error("Cannot access boot FS")
end

-- ============================================================
-- КРОК 9: loadfile / dofile
-- ============================================================
local function readFile(path)
  if not bootFS.exists(path) then
    return nil, "not found: " .. path
  end

  local h = bootFS.open(path, "r")
  if not h then return nil, "open fail: " .. path end

  local data = {}
  while true do
    local chunk = bootFS.read(h, 4096)
    if not chunk then break end
    data[#data+1] = chunk
  end

  bootFS.close(h)
  return table.concat(data)
end

local function loadfile_impl(path)
  local src, err = readFile(path)
  if not src then return nil, err end

  local fn, e = load(src, "="..path, "bt", _G)
  if not fn then return nil, e end

  return fn
end

_G.loadfile = loadfile_impl
_G.dofile = function(p)
  local f, e = loadfile_impl(p)
  if not f then _G.error(e) end
  return f()
end

-- ============================================================
-- КРОК 10: require
-- ============================================================
consolePrint("Setting up require...")

local loaded = {}

_G.require = function(name)
  if loaded[name] then return loaded[name] end

  local paths = {
    "/lib/"..name..".lua",
    "/lib/"..name:gsub("%.","/")..".lua",
    "/system/lib/"..name..".lua",
    "/system/lib/"..name:gsub("%.","/")..".lua"
  }

  for _,p in ipairs(paths) do
    if bootFS.exists(p) then
      local f = loadfile_impl(p)
      local r = f()
      loaded[name] = r or true
      return loaded[name]
    end
  end

  _G.error("module not found: "..name)
end

-- ============================================================
-- КРОК 11: os API
-- ============================================================
consolePrint("Building os API...")

_G.os = {}

function os.sleep(s)
  local t = computer.uptime() + (s or 0)
  repeat
    computer.pullSignal(t - computer.uptime())
  until computer.uptime() >= t
end

function os.clock()
  return computer.uptime()
end

function os.time()
  return math.floor(computer.uptime())
end

-- ============================================================
-- КРОК 12: Перевірка файлів
-- ============================================================
consolePrint("Checking system files...")

if not bootFS.exists("/system/desktop.lua") then
  _G.error("Missing desktop.lua")
end

-- ============================================================
-- КРОК 13: Запуск Desktop
-- ============================================================
consolePrint("Launching desktop...")
os.sleep(0.2)

local fn, err = loadfile_impl("/system/desktop.lua")
if not fn then _G.error(err) end

local ok, crash = pcall(fn)
if not ok then
  local h = bootFS.open("/crash.log", "w")
  if h then
    bootFS.write(h, crash)
    bootFS.close(h)
  end
  _G.error(crash)
end

-- ============================================================
-- КРОК 14: Завершення
-- ============================================================
consolePrint("System halted.")
os.sleep(1)
computer.shutdown()