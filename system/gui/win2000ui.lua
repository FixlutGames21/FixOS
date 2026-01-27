local ui = {}

function ui.box(x, y, w, h, title)
  local gpu = require("component").gpu
  gpu.setBackground(0xC0C0C0)
  gpu.fill(x, y, w, h, " ")
  gpu.setBackground(0x000080)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(x, y, w, 1, " ")
  gpu.set(x+1, y, title or "Window")
  gpu.setBackground(0xC0C0C0)
  gpu.setForeground(0x000000)
end

return ui