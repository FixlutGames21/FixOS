local component = require("component")
local term = require("term")
local event = require("event")

local gpu = component.gpu

local function drawDesktop()
  gpu.setBackground(0x0000AA)
  gpu.fill(1,1,80,25," ")
  gpu.setForeground(0xFFFFFF)
  gpu.set(2,2,"FixOS 2000 Desktop")
  gpu.set(2,24,"Start [S]   Settings [T]   Exit [X]")
end

drawDesktop()
while true do
  local _,_,_,char,code = event.pull("key_down")
  -- S key (code 31) for Start Menu
  if code == 31 then 
    dofile("/system/startmenu.lua")
    drawDesktop() -- Redraw after returning
  end
  -- T key (code 20) for Settings
  if code == 20 then 
    dofile("/system/settings.lua")
    -- Settings already returns to desktop
  end
  -- X key (code 45) for Exit
  if code == 45 then 
    term.clear()
    os.exit() 
  end
end