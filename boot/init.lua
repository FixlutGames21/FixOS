local component = require("component")
local computer = require("computer")

if component.isAvailable("gpu") then
  local gpu = component.gpu
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  local w, h = gpu.maxResolution()
  gpu.setResolution(math.min(80, w), math.min(25, h))
  gpu.fill(1, 1, 80, 25, " ")
  gpu.set(2, 2, "FixOS 2000 booting...")
end

require("os").sleep(1.5)

local success, err = pcall(function()
  dofile("/system/desktop.lua")
end)

if not success then
  print("Boot failed: " .. tostring(err))
  print("Press any key to shutdown...")
  require("term").read()
  computer.shutdown()
end
