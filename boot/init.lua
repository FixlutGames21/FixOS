local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local term = require("term")

local gpu = component.gpu
gpu.setResolution(80, 25)
gpu.fill(1, 1, 80, 25, " ")
gpu.set(2, 2, "Booting FixOS Windows-style...")

local kernel = loadfile("/boot/kernel.lua")
if kernel then kernel() else
  gpu.set(2, 4, "Kernel not found!")
end
