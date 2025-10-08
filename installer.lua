-- FixOS Installer PRO v2
-- by Fixlut & GPT
local component = component
local computer = computer
local fs = component.proxy(computer.getBootAddress())
local eeprom = component.list("eeprom")() and component.proxy(component.list("eeprom")()) or nil
local gpu = component.list("gpu")() and component.proxy(component.list("gpu")()) or nil
local screen = component.list("screen")() and component.proxy(component.list("screen")()) or nil

------------------------------------------------------------
-- UI helpers
------------------------------------------------------------
local function initGPU()
  if gpu and screen then
    pcall(function()
      gpu.bind(screen.address)
      gpu.setResolution(50, 16)
      gpu.setBackground(0x000000)
      gpu.setForeground(0x00FF00)
      gpu.fill(1, 1, 50, 16, " ")
    end)
  end
end

local function center(y, text, color)
  if not gpu then return end
  local w, h = gpu.getResolution()
  local x = math.floor(w/2 - #text/2)
  gpu.setForeground(color or 0x00FF00)
  gpu.set(x, y, text)
end

local function log(msg)
  computer.pullSignal(0.05)
  center(8, msg, 0xAAAAAA)
end

------------------------------------------------------------
-- BIOS (FixBIOS vPro2)
------------------------------------------------------------
local FIXBIOS_CODE = [[
local component = component
local computer = computer
local function findProxy(kind)
  for addr, t in component.list() do
    if t == kind then return component.proxy(addr) end
  end
  return nil
end
local gpu = findProxy("gpu")
local screen = findProxy("screen")
local eeprom = findProxy("eeprom")
local function drawTextCentered(y, color, text)
  if not gpu then return end
  local w, h = gpu.getResolution()
  local x = math.floor(w/2 - #text/2)
  gpu.setForeground(color)
  gpu.set(x, y, text)
end
local function clearScreen()
  if gpu then
    local w, h = gpu.getResolution()
    gpu.setBackground(0x000000)
    gpu.fill(1, 1, w, h, " ")
  end
end
local function showStatus(msg, color)
  clearScreen()
  drawTextCentered(2, 0x00FF00, "FixBIOS vPro2")
  drawTextCentered(4, color or 0xAAAAAA, msg)
end
local function tryBoot(proxy)
  if not proxy then return false end
  local bootPaths = {"/boot/init.lua", "/boot/kernel.lua", "/boot/shell.lua", "/init.lua"}
  for _, path in ipairs(bootPaths) do
    if proxy.exists(path) then
      showStatus("Booting " .. path .. "...", 0x00FF00)
      local handle = proxy.open(path, "r")
      if not handle then return false end
      local data = ""
      repeat
        local chunk = proxy.read(handle, math.huge)
        data = data .. (chunk or "")
      until not chunk
      proxy.close(handle)
      local ok, err = load(data, "="..path)
      if not ok then
        showStatus("Error loading " .. path .. ":\n" .. tostring(err), 0xFF5555)
        return false
      end
      local ok2, err2 = pcall(ok)
      if not ok2 then
        showStatus("Runtime error: " .. tostring(err2), 0xFF5555)
        return false
      end
      return true
    end
  end
  return false
end
local function bootSystem()
  local addr = eeprom and eeprom.getData() or nil
  local bootProxy = addr and component.proxy(addr)
  if bootProxy and tryBoot(bootProxy) then return end
  for address in component.list("filesystem") do
    local proxy = component.proxy(address)
    if tryBoot(proxy) then
      if eeprom then eeprom.setData(address) end
      return
    end
  end
  showStatus("No bootable FixOS found.\nInsert disk & reboot.", 0xFF0000)
end
if gpu and screen then
  pcall(function()
    gpu.bind(screen.address)
    gpu.setResolution(50, 16)
  end)
end
showStatus("FixBIOS initializing...", 0xAAAAAA)
bootSystem()
]]

------------------------------------------------------------
-- Disk formatting
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
-- Install FixOS core
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
local function flashBIOS()
  if not eeprom then
    center(10, "No EEPROM found!", 0xFF0000)
    return
  end
  log("Flashing FixBIOS vPro2...")
  eeprom.set(FIXBIOS_CODE)
  eeprom.setLabel("FixBIOS vPro2")
  eeprom.setData(computer.getBootAddress())
end

------------------------------------------------------------
-- Main install process
------------------------------------------------------------
initGPU()
center(2, "FixOS Installer PRO", 0x00FF00)
log("Starting setup...")

formatDisk()
installFixOS()
flashBIOS()

center(12, "Installation Complete!", 0x00FF00)
center(13, "Rebooting...", 0xAAAAAA)
computer.shutdown(true)
