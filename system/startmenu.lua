local component = require("component")
local event = require("event")
local shell = require("shell")

local gpu = component.gpu

gpu.setBackground(0xC0C0C0)
gpu.fill(1,20,30,5," ")
gpu.setBackground(0x000080)
gpu.setForeground(0xFFFFFF)
gpu.fill(1,20,30,1," ")
gpu.set(2,20," Start Menu")
gpu.setBackground(0xC0C0C0)
gpu.setForeground(0x000000)
gpu.set(2,21,"1. Calculator")
gpu.set(2,22,"2. Text Editor")
gpu.set(2,23,"3. Terminal")
gpu.set(2,24,"Press 1-3 or ESC to exit")

local _,_,_,char,key = event.pull("key_down")

-- Restore desktop background before executing
gpu.setBackground(0x0000AA)
gpu.fill(1,20,80,5," ")

if key == 2 then -- 1 key
  dofile("/bin/calc.lua")
elseif key == 3 then -- 2 key
  dofile("/bin/edit.lua")
elseif key == 4 then -- 3 key
  shell.execute("sh")
end

-- Return to desktop
dofile("/system/desktop.lua")