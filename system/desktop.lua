local gpu = require("component").gpu
local term = require("term")

local function drawDesktop()
  gpu.setBackground(0x0000AA)
  gpu.fill(1,1,80,25," ")
  gpu.setForeground(0xFFFFFF)
  gpu.set(2,2,"FixOS 2000 Desktop")
  gpu.set(2,24,"Start [S]   Settings [T]   Exit [X]")
end

drawDesktop()
while true do
  local _,_,_,_,_,key = term.pull("key_down")
  if key == 46 then os.execute("/system/startmenu.lua") end
  if key == 20 then os.execute("/system/settings.lua") end
  if key == 45 then os.exit() end
end
