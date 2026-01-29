-- ==============================================
-- FixOS 2.0 - boot/init.lua
-- Завантажувач системи
-- ==============================================

local component_invoke = component.invoke
local component_list = component.list
local component_proxy = component.proxy

-- GPU та екран
local gpu = component_list("gpu")()
local screen = component_list("screen")()

if gpu and screen then
  component_invoke(gpu, "bind", screen)
  
  local maxW, maxH = component_invoke(gpu, "maxResolution")
  local w = maxW > 80 and 80 or maxW
  local h = maxH > 25 and 25 or maxH
  component_invoke(gpu, "setResolution", w, h)
  
  component_invoke(gpu, "setBackground", 0x000000)
  component_invoke(gpu, "setForeground", 0x00FF00)
  component_invoke(gpu, "fill", 1, 1, w, h, " ")
  
  component_invoke(gpu, "set", 2, 2, "FixOS 2.0")
  component_invoke(gpu, "set", 2, 4, "Booting...")
  
  for i = 1, 3 do
    component_invoke(gpu, "set", 12 + i, 4, ".")
    local deadline = computer.uptime() + 0.3
    while computer.uptime() < deadline do end
  end
end

-- Завантаження базових бібліотек
_G._OSVERSION = "FixOS 2.0"

-- Шукаємо OpenOS boot
local hasOpenOS = false
for addr in component_list("filesystem") do
  local fs = component_proxy(addr)
  if fs and component_invoke(addr, "exists", "/lib/core/boot.lua") then
    hasOpenOS = true
    
    -- Завантажуємо OpenOS
    local handle = component_invoke(addr, "open", "/lib/core/boot.lua")
    if handle then
      local data = ""
      repeat
        local chunk = component_invoke(addr, "read", handle, math.huge)
        data = data .. (chunk or "")
      until not chunk
      component_invoke(addr, "close", handle)
      
      local code, reason = load(data, "=/lib/core/boot.lua", "bt", _G)
      if code then
        xpcall(code, debug.traceback)
      end
    end
    break
  end
end

-- Запускаємо desktop
local success = false

if hasOpenOS then
  -- З OpenOS
  success = pcall(function()
    dofile("/system/desktop.lua")
  end)
else
  -- Без OpenOS - прямий запуск
  for addr in component_list("filesystem") do
    local fs = component_proxy(addr)
    if fs and component_invoke(addr, "exists", "/system/desktop.lua") then
      local handle = component_invoke(addr, "open", "/system/desktop.lua")
      if handle then
        local data = ""
        repeat
          local chunk = component_invoke(addr, "read", handle, math.huge)
          data = data .. (chunk or "")
        until not chunk
        component_invoke(addr, "close", handle)
        
        local code, reason = load(data, "=desktop", "bt", _G)
        if code then
          success = pcall(code)
        end
      end
      break
    end
  end
end

if not success and gpu then
  component_invoke(gpu, "setForeground", 0xFF0000)
  component_invoke(gpu, "set", 2, 8, "Boot failed!")
  component_invoke(gpu, "set", 2, 10, "Press any key to shutdown")
  computer.pullSignal()
  computer.shutdown()
end