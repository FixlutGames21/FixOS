local component = require("component")
local term = require("term")
local event = require("event")

if not component.isAvailable("gpu") then
  print("ERROR: No GPU available!")
  os.exit()
end

local gpu = component.gpu

local maxW, maxH = gpu.maxResolution()
gpu.setResolution(math.min(80, maxW), math.min(25, maxH))

local function drawDesktop()
  local w, h = gpu.getResolution()
  gpu.setBackground(0x0000AA)
  gpu.fill(1, 1, w, h, " ")
  gpu.setForeground(0xFFFFFF)
  gpu.set(2, 2, "FixOS 2000 Desktop")
  gpu.set(2, h-1, "Start [S]   Settings [T]   Exit [X]")
end

drawDesktop()

while true do
  local _, _, _, char, code = event.pull("key_down")
  
  if code == 31 then -- S key
    dofile("/system/startmenu.lua")
    drawDesktop()
  elseif code == 20 then -- T key
    dofile("/system/settings.lua")
    drawDesktop()
  elseif code == 45 then -- X key
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    term.clear()
    print("FixOS 2000 shutdown.")
    os.exit()
  end
end