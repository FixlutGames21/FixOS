local gpu = require("component").gpu
local term = require("term")
local event = require("event")

local w, h = gpu.getResolution()

gpu.setBackground(0x0000AA)
gpu.fill(1, 1, w, h, " ")
gpu.setForeground(0xFFFF00)
gpu.set(2, 2, "FixOS 2000 Settings")
gpu.setForeground(0xFFFFFF)
gpu.set(2, 4, "Version: 1.0")
gpu.set(2, 5, "Author: FixlutGames21")
gpu.set(2, 7, "No settings available yet.")
gpu.set(2, 9, "Press any key to return.")

event.pull("key_down")