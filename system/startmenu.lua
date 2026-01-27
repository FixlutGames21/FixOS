local component = require("component")
local event = require("event")
local shell = require("shell")
local term = require("term")

local gpu = component.gpu
local w, h = gpu.getResolution()

gpu.setBackground(0xC0C0C0)
gpu.fill(1, h-5, 30, 6, " ")
gpu.setBackground(0x000080)
gpu.setForeground(0xFFFFFF)
gpu.fill(1, h-5, 30, 1, " ")
gpu.set(2, h-5, " Start Menu")
gpu.setBackground(0xC0C0C0)
gpu.setForeground(0x000000)
gpu.set(2, h-4, "1. Calculator")
gpu.set(2, h-3, "2. Text Editor")
gpu.set(2, h-2, "3. Terminal")
gpu.set(2, h-1, "Press 1-3 or ESC")

local _, _, _, char, key = event.pull("key_down")

gpu.setBackground(0x0000AA)
gpu.fill(1, h-5, 30, 6, " ")

if key == 2 then -- 1
  dofile("/bin/calc.lua")
elseif key == 3 then -- 2
  dofile("/bin/edit.lua")
elseif key == 4 then -- 3
  term.clear()
  shell.execute("sh")
end