local component = require("component")
local event = require("event")
local gpu = component.gpu
local term = require("term")

local w,h = gpu.getResolution()

-- очистка екрану
local function clear()
  gpu.fill(1,1,w,h," ")
end

-- намалювати панель задач
local function drawTaskbar()
  gpu.setBackground(0x0000FF) -- синя як у WinXP
  gpu.fill(1,h,w,1," ")
  gpu.set(2,h,"Start")
  gpu.setBackground(0x000000) -- назад чорний
end

-- стартове вікно
local function drawDesktop()
  clear()
  gpu.set(2,2,"Welcome to FixOS (Windows-style)")
  gpu.set(2,4,"Press START to open menu")
  drawTaskbar()
end

-- меню "Start"
local function showMenu()
  gpu.setBackground(0xAAAAAA)
  gpu.fill(2,h-6,12,5," ")
  gpu.set(3,h-6,"1. Calc")
  gpu.set(3,h-5,"2. Echo")
  gpu.set(3,h-4,"3. Files")
  gpu.setBackground(0x000000)
end

-- "вікно" калькулятора
local function openCalc()
  clear()
  gpu.set(2,2,"Calculator:")
  io.write("Enter expression: ")
  local exp = io.read()
  local f = load("return "..exp)
  if f then
    local ok,res = pcall(f)
    if ok then print("Result:",res) else print("Error") end
  else
    print("Invalid input")
  end
  io.read()
  drawDesktop()
end

-- GUI loop
drawDesktop()

while true do
  local e,_,x,y = event.pull("touch")
  if y == h and x >= 2 and x <= 7 then
    showMenu()
  elseif y == h-6 and x >= 3 and x <= 12 then
    openCalc()
  elseif y == h-5 and x >= 3 and x <= 12 then
    term.clear()
    io.write("Echo text: ")
    local txt = io.read()
    print(txt)
    io.read()
    drawDesktop()
  elseif y == h-4 and x >= 3 and x <= 12 then
    term.clear()
    print("Files on disk:")
    for file in require("filesystem").list("/") do
      print(file)
    end
    io.read()
    drawDesktop()
  end
end
