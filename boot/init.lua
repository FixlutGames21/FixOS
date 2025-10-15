-- boot/init.lua (minimal FixOS boot that reads personalization)
local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local term = require("term")
local unicode = require("unicode")

local configPath = "/etc/fixos.conf"
local conf = { theme = "green", label = "FixOS" }
if fs.exists(configPath) then
  local f = io.open(configPath,"r")
  if f then
    local s = f:read("*a"); f:close()
    local ok, t = pcall(function() return load("return " .. s)() end)
    if ok and type(t)=="table" then conf = t end
  end
end

local gpuAddr = component.list("gpu")()
local gpu = gpuAddr and component.proxy(gpuAddr)
local screen = component.list("screen")() and component.proxy(component.list("screen")())

if gpu and screen then
  pcall(function() gpu.bind(screen.address); pcall(gpu.setResolution,gpu,100,50); pcall(gpu.setBackground,gpu,0x000000); pcall(gpu.setForeground,gpu,0x00FF00); pcall(gpu.fill,gpu,1,1,100,50," ") end)
  local msg = ("Welcome to %s — theme: %s"):format(conf.label or "FixOS", conf.theme or "green")
  local w, h = pcall(gpu.getResolution, gpu); if w then w = select(2, gpu.getResolution()) end
  local len = unicode and unicode.len(msg) or #msg
  local x = math.floor(100/2 - len/2)
  pcall(gpu.set, gpu, x, 25, msg)
else
  print(("Welcome to %s — theme: %s"):format(conf.label or "FixOS", conf.theme or "green"))
end

-- keep console open a bit
computer.pullSignal(3)
