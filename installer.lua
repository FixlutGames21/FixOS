-- FixOS Installer PRO v3
-- by Fixlut & GPT
local component = component or require("component")
local computer = computer or require("computer")
local unicode = unicode or require("unicode")

local gpu = (component.list("gpu")() and component.proxy(component.list("gpu")())) or nil
local screen = (component.list("screen")() and component.proxy(component.list("screen")())) or nil
local eeprom = (component.list("eeprom")() and component.proxy(component.list("eeprom")())) or nil
local fs = component.proxy(computer.getBootAddress())

------------------------------------------------------------
-- GPU UI Helpers
------------------------------------------------------------
local function initGPU()
  if not gpu or not screen then return end
  pcall(function()
    gpu.bind(screen.address)
    gpu.setResolution(100, 50)
    gpu.setBackground(0x000000)
    gpu.setForeground(0x00FF00)
    gpu.fill(1, 1, 50, 16, " ")
  end)
end

local function center(y, text, color)
  if not gpu then return end
  local w, h = gpu.getResolution()
  local x = math.floor(w / 2 - unicode.len(text) / 2)
  gpu.setForeground(color or 0x00FF00)
  gpu.set(x, y, text)
end

local function log(msg)
  center(8, msg, 0xAAAAAA)
  computer.pullSignal(0.05)
end

------------------------------------------------------------
-- BIOS Variants
------------------------------------------------------------
local BIOS_LITE = [[
local c = component; local comp = computer
for addr, t in c.list("filesystem") do
  local proxy = c.proxy(addr)
  if proxy.exists("/boot/init.lua") then
    local f = proxy.open("/boot/init.lua","r")
    local data = ""
    repeat local chunk = proxy.read(f, math.huge) data=data..(chunk or "") until not chunk
    proxy.close(f)
    local ok, err = load(data, "=init")
    if ok then pcall(ok) else error(err) end
    return
  end
end
error("No bootable FixOS found")
]]

local BIOS_PRO = [[
local c, comp = component, computer
local gpu = (c.list("gpu")() and c.proxy(c.list("gpu")())) or nil
local scr = (c.list("screen")() and c.proxy(c.list("screen")())) or nil
if gpu and scr then pcall(function() gpu.bind(scr.address) gpu.setResolution(50,16) end) end
local function msg(t,col) if gpu then gpu.setForeground(col or 0x00FF00) gpu.set(2,2,t) end end
msg("FixBIOS Pro Booting...",0x00FF00)
for addr in c.list("filesystem") do
  local p = c.proxy(addr)
  if p.exists("/boot/init.lua") then
    msg("Booting from disk...",0xAAAAAA)
    local f = p.open("/boot/init.lua","r")
    local d="";repeat local b=p.read(f,math.huge)d=d..(b or "")until not b;p.close(f)
    local ok,err=load(d,"=init") if not ok then error(err) end
    local ok2,er2=pcall(ok) if not ok2 then error(er2) end
    return
  end
end
msg("No FixOS found!",0xFF0000)
]]

local BIOS_DEBUG = [[
local c, comp = component, computer
print("FixBIOS Debug Mode Loaded")
print("Listing filesystems:")
for addr, t in c.list("filesystem") do print(addr, t) end
print("End of Debug Listing.")
]]

------------------------------------------------------------
-- Disk Formatting
------------------------------------------------------------
local function formatDisk()
  log("Formatting disk...")
  for _, name in ipairs(fs.list("/") or {}) do
    if name ~= "rom/" then
      pcall(fs.remove, name)
    end
  end
  fs.makeDirectory("/boot")
  fs.makeDirectory("/bin")
  fs.makeDirectory("/home")
end

------------------------------------------------------------
-- Install Core FixOS
------------------------------------------------------------
local function installFixOS()
  log("Installing FixOS core...")
  local init = [[
print("Welcome to FixOS!")
print("System booted successfully.")
]]
  local handle = fs.open("/boot/init.lua", "w")
  fs.write(handle, init)
  fs.close(handle)
end

------------------------------------------------------------
-- Flash BIOS
------------------------------------------------------------
local function flashBIOS(code, label)
  if not eeprom then
    center(10, "No EEPROM found!", 0xFF0000)
    return
  end
  eeprom.set(code)
  eeprom.setLabel(label)
  eeprom.setData(computer.getBootAddress())
end

------------------------------------------------------------
-- BIOS Menu
------------------------------------------------------------
local function showMenu()
  initGPU()
  center(2, "FixOS Installer PRO v3", 0x00FF00)
  center(4, "Select BIOS Type:", 0xAAAAAA)
  center(6, "[1] Lite  |  [2] Pro  |  [3] Debug", 0xFFFFFF)
  local _, _, _, key = computer.pullSignal("key_down")
  if key == 2 then return "lite" end
  if key == 3 then return "pro" end
  if key == 4 then return "debug" end
  return "pro"
end

------------------------------------------------------------
-- Main Installer Logic
------------------------------------------------------------
initGPU()
local mode = showMenu()
log("Formatting...")
formatDisk()
installFixOS()

if mode == "lite" then
  flashBIOS(BIOS_LITE, "FixBIOS Lite")
elseif mode == "debug" then
  flashBIOS(BIOS_DEBUG, "FixBIOS Debug")
else
  flashBIOS(BIOS_PRO, "FixBIOS Pro")
end

center(13, "Installation Complete!", 0x00FF00)
center(14, "Rebooting...", 0xAAAAAA)
computer.shutdown(true)
