local term = require("term")
local component = require("component")

if component.isAvailable("gpu") then
  local gpu = component.gpu
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  local w, h = gpu.getResolution()
  gpu.fill(1, 1, w, h, " ")
end

term.clear()
term.setCursor(1, 1)