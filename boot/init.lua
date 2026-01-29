-- ==============================================
-- FixOS 2.0 - boot/init.lua
-- Завантажувач системи (ПОКРАЩЕНО)
-- ==============================================

local component_invoke = component.invoke
local component_list = component.list
local component_proxy = component.proxy

-- Безпечна функція виклику компонентів
local function safeInvoke(addr, method, ...)
  local result = table.pack(pcall(component_invoke, addr, method, ...))
  if result[1] then
    return table.unpack(result, 2, result.n)
  end
  return nil
end

-- GPU та екран
local gpu = component_list("gpu")()
local screen = component_list("screen")()

if gpu and screen then
  safeInvoke(gpu, "bind", screen)
  
  local maxW, maxH = safeInvoke(gpu, "maxResolution")
  if maxW and maxH then
    local w = maxW > 80 and 80 or maxW
    local h = maxH > 25 and 25 or maxH
    safeInvoke(gpu, "setResolution", w, h)
    
    safeInvoke(gpu, "setBackground", 0x000000)
    safeInvoke(gpu, "setForeground", 0x00FF00)
    safeInvoke(gpu, "fill", 1, 1, w, h, " ")
    
    safeInvoke(gpu, "set", 2, 2, "FixOS 2.0")
    safeInvoke(gpu, "set", 2, 4, "Booting...")
    
    -- Анімація завантаження
    for i = 1, 3 do
      safeInvoke(gpu, "set", 12 + i, 4, ".")
      local deadline = computer.uptime() + 0.3
      while computer.uptime() < deadline do end
    end
  end
end

-- Завантаження базових бібліотек
_G._OSVERSION = "FixOS 2.0"

-- Функція завантаження файлу
local function loadFile(addr, path)
  local handle = safeInvoke(addr, "open", path)
  if not handle then return nil end
  
  local data = ""
  local chunk
  repeat
    chunk = safeInvoke(addr, "read", handle, math.huge)
    if chunk then
      data = data .. chunk
    end
  until not chunk
  
  safeInvoke(addr, "close", handle)
  return data
end

-- Шукаємо OpenOS boot
local hasOpenOS = false
for addr in component_list("filesystem") do
  local fs = component_proxy(addr)
  if fs and safeInvoke(addr, "exists", "/lib/core/boot.lua") then
    hasOpenOS = true
    
    if gpu then
      safeInvoke(gpu, "set", 2, 6, "Loading OpenOS...")
    end
    
    -- Завантажуємо OpenOS
    local data = loadFile(addr, "/lib/core/boot.lua")
    if data then
      local code, reason = load(data, "=/lib/core/boot.lua", "bt", _G)
      if code then
        local ok = xpcall(code, function(err)
          if gpu then
            safeInvoke(gpu, "setForeground", 0xFFFF00)
            safeInvoke(gpu, "set", 2, 8, "OpenOS warning: " .. tostring(err))
          end
          return err
        end)
      end
    end
    break
  end
end

-- Запускаємо desktop
local success = false
local desktopPath = "/system/desktop.lua"

if gpu then
  safeInvoke(gpu, "set", 2, 8, "Starting Desktop...")
end

if hasOpenOS then
  -- З OpenOS - використовуємо dofile
  success = pcall(function()
    dofile(desktopPath)
  end)
else
  -- Без OpenOS - прямий запуск
  for addr in component_list("filesystem") do
    local fs = component_proxy(addr)
    if fs and safeInvoke(addr, "exists", desktopPath) then
      local data = loadFile(addr, desktopPath)
      if data then
        local code, reason = load(data, "=desktop", "bt", _G)
        if code then
          success = pcall(code)
          if success then
            break
          end
        end
      end
    end
  end
end

-- Обробка помилок
if not success and gpu then
  safeInvoke(gpu, "setForeground", 0xFF0000)
  safeInvoke(gpu, "set", 2, 10, "Boot failed!")
  safeInvoke(gpu, "set", 2, 11, "Desktop not found or error occurred")
  safeInvoke(gpu, "set", 2, 13, "Troubleshooting:")
  safeInvoke(gpu, "setForeground", 0xFFFFFF)
  safeInvoke(gpu, "set", 2, 14, "1. Check if /system/desktop.lua exists")
  safeInvoke(gpu, "set", 2, 15, "2. Reinstall FixOS using installer")
  safeInvoke(gpu, "set", 2, 16, "3. Check filesystem permissions")
  safeInvoke(gpu, "set", 2, 18, "Press any key to shutdown")
  computer.pullSignal()
  computer.shutdown()
end