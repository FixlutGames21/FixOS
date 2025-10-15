-- /boot/init.lua — FixOS core bootstrap (minimal)
local component = require("component")
local computer = require("computer")
local term = require("term")
local gpu = component.isAvailable and component.isAvailable("gpu") and component.proxy(component.list("gpu")()) or nil

if gpu then
  pcall(function()
    gpu.setResolution(100,50)
    gpu.setBackground(0x000000)
    gpu.fill(1,1,100,50," ")
    gpu.setForeground(0x00FF00)
    gpu.set(10,20,"✅ FixOS successfully booted! (minimal init)")
  end)
else
  print("✅ FixOS successfully booted! (minimal init)")
end

-- keep console open for a bit
computer.pullSignal(3)
