local component = require("component")
local term = require("term")
local gpu = component.gpu

gpu.fill(1,1,80,25," ")
gpu.set(2,2,"FixOS Kernel Loaded (Windows-style)")

local shell = loadfile("/boot/shell.lua")
if shell then shell() else
  gpu.set(2,4,"No shell.lua found")
end
