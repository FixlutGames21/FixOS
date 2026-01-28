-- ==============================================
-- ФАЙЛ: boot/init.lua
-- Завантажувач FixOS 2000
-- ==============================================
local component = require("component")
local computer = require("computer")

-- Перевірка GPU
if component.isAvailable("gpu") then
  local gpu = component.gpu
  
  -- Налаштування екрану
  local w, h = gpu.maxResolution()
  gpu.setResolution(math.min(80, w), math.min(25, h))
  
  -- Екран завантаження
  gpu.setBackground(0x000000)
  gpu.setForeground(0x00FF00)
  gpu.fill(1, 1, 80, 25, " ")
  gpu.set(2, 2, "FixOS 2000 booting...")
  gpu.set(2, 4, "Loading system...")
end

-- Затримка для ефекту
require("os").sleep(1.5)

-- Запуск робочого столу
local success, err = pcall(function()
  dofile("/system/desktop.lua")
end)

-- Обробка помилок
if not success then
  if component.isAvailable("gpu") then
    local gpu = component.gpu
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFF0000)
    gpu.fill(1, 1, 80, 25, " ")
    gpu.set(2, 2, "FixOS Boot Error:")
    gpu.set(2, 4, tostring(err))
    gpu.set(2, 6, "Press any key to shutdown...")
  else
    print("Boot failed: " .. tostring(err))
    print("Press any key to shutdown...")
  end
  
  require("event").pull("key_down")
  computer.shutdown()
end