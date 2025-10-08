---------------------------------------------
-- 🧠 FixOS Installer v3 by Fixlut
-- Автоматична установка FixOS + FixBIOS
---------------------------------------------
local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local term = require("term")
local eeprom = component.eeprom

---------------------------------------------
-- Вивід
---------------------------------------------
term.clear()
print("=====================================")
print("       FixOS INSTALLER PRO v3")
print("=====================================")
computer.sleep(0.5)

---------------------------------------------
-- Крок 1: Встановлення FixOS
---------------------------------------------
local installPath = "/"
print("\n📦 Installing FixOS...")

-- створимо структуру директорій
fs.makeDirectory(installPath .. "boot")
fs.makeDirectory(installPath .. "system")

-- створюємо головний файл FixOS
local fixos = [[
-------------------------------------
-- FixOS Boot File (boot/fixos.lua)
-------------------------------------
print("🔧 Booting FixOS...")
computer.sleep(0.5)

local fs = require("filesystem")
local term = require("term")

term.clear()
print("=====================================")
print("        Welcome to FixOS v2.0")
print("=====================================")

print("✅ System initialized successfully!")
print("Tip: Type 'help' to see available commands.")

while true do
  io.write("FixOS> ")
  local cmd = io.read()
  if cmd == "exit" then
    print("Goodbye!")
    break
  elseif cmd == "help" then
    print("Available commands: help, exit, about")
  elseif cmd == "about" then
    print("FixOS v2.0 by Fixlut")
  else
    print("Unknown command: " .. tostring(cmd))
  end
end
]]

local bootFile = io.open(installPath .. "boot/fixos.lua", "w")
bootFile:write(fixos)
bootFile:close()

print("✅ FixOS files installed successfully!")

---------------------------------------------
-- Крок 2: Запис FixBIOS в EEPROM
---------------------------------------------
print("\n⚙️  Writing FixBIOS to EEPROM...")

local bios = [[
-------------------------------------
-- FixBIOS v4
-- by Fixlut
-------------------------------------
local component = component
local computer = computer

-------------------------------------
-- Safe component check
-------------------------------------
local function safeIsAvailable(name)
  for addr, type in component.list() do
    if type == name then return true end
  end
  return false
end

-------------------------------------
-- GPU setup
-------------------------------------
local gpu, screen = component.list("gpu")(), component.list("screen")()
if gpu and screen then
  gpu = component.proxy(gpu)
  gpu.bind(screen)
  gpu.setResolution(50, 16)
  gpu.setBackground(0x000000)
  gpu.setForeground(0x00FF00)
  gpu.fill(1, 1, 50, 16, " ")
else
  gpu = nil
end

local line = 1
local function println(text)
  if gpu then
    gpu.set(2, line, text)
    line = line + 1
  end
end

-------------------------------------
-- Splash Screen
-------------------------------------
if gpu then
  gpu.setForeground(0x00FF00)
  gpu.fill(1, 1, 50, 16, " ")
  gpu.set(8, 3, "███████╗██╗██╗  ██╗ ██████╗ ███████╗")
  gpu.set(8, 4, "██╔════╝██║██║ ██╔╝██╔═══██╗██╔════╝")
  gpu.set(8, 5, "███████╗██║█████╔╝ ██║   ██║█████╗  ")
  gpu.set(8, 6, "╚════██║██║██╔═██╗ ██║   ██║██╔══╝  ")
  gpu.set(8, 7, "███████║██║██║  ██╗╚██████╔╝██║     ")
  gpu.set(8, 8, "╚══════╝╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     ")
  gpu.setForeground(0xFFFFFF)
  gpu.set(18, 10, "FixOS BIOS v4 — Deluxe Edition")
  gpu.set(20, 12, "Starting system...")
  computer.sleep(2)
  gpu.fill(1, 1, 50, 16, " ")
end

-------------------------------------
-- POST
-------------------------------------
println("FixBIOS v4 POST Sequence")
println("----------------------------------")

local function postCheck(name, pass)
  println(("[%s] %s"):format(pass and " OK " or "FAIL", name))
  if not pass then computer.beep(400, 0.4) end
end

local hasFS = safeIsAvailable("filesystem")
local hasEEPROM = safeIsAvailable("eeprom")
local hasGPU = safeIsAvailable("gpu")

postCheck("Filesystem", hasFS)
postCheck("EEPROM", hasEEPROM)
postCheck("GPU", hasGPU)
println("----------------------------------")

-------------------------------------
-- Bootloader
-------------------------------------
if not hasFS then
  println("❌ No filesystem detected.")
  println("Insert FixOS disk and reboot.")
  return
end

local fsAddr = component.list("filesystem")()
local fs = component.proxy(fsAddr)
local bootPaths = {"/boot/fixos.lua", "/init.lua", "/os/init.lua"}

local function tryBoot()
  for _, path in ipairs(bootPaths) do
    if fs.exists(path) then
      println("Booting: " .. path)
      local handle = fs.open(path, "r")
      local data = ""
      repeat
        local chunk = fs.read(handle, math.huge)
        data = data .. (chunk or "")
      until not chunk
      fs.close(handle)

      local ok, err = load(data, "="..path)
      if not ok then
        println("Boot error: " .. tostring(err))
        return false
      end

      println("Running FixOS...")
      ok()
      return true
    end
  end
  return false
end

if not tryBoot() then
  println("⚠️ FixOS not found on disk!")
  println("Please reinstall system.")
end
]]

eeprom.set(bios)
eeprom.setLabel("FixBIOS")
print("✅ FixBIOS successfully written to EEPROM!")

---------------------------------------------
-- Крок 3: Завершення
---------------------------------------------
print("\n🎉 Installation completed!")
print("You can reboot now and enjoy FixOS.")
io.write("\nReboot now? (y/n): ")
local ans = io.read()
if ans and ans:lower() == "y" then
  print("🔁 Rebooting...")
  computer.sleep(1)
  computer.shutdown(true)
else
  print("🚫 Reboot canceled.")
end
