local gpu = require("component").gpu
gpu.setBackground(0x0000AA)
gpu.setForeground(0xFFFFFF)
gpu.fill(1,20,30,5," ")
gpu.set(2,21,"1. Calculator")
gpu.set(2,22,"2. File Explorer")
gpu.set(2,23,"3. Terminal")
gpu.set(2,24,"Press 1-3 or any key to exit menu")

local event = require("event")
local _,_,_,_,_,key = event.pull("key_down")
if key == 2 then os.execute("/bin/calc.lua") end
if key == 3 then print("File Explorer TODO") end
if key == 4 then shell.execute("sh") end
