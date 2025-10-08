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
os.sleep(0.5)

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
os.sleep(0.5)

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
-- FixBIOS v3 (POST Boot System)
-- Created by Fixlut
-------------------------------------
local component = component
local computer = computer
local unicode = unicode

-- Boot sequence paths
local bootPaths = {
  "/boot/fixos.lua",
  "/init.lua",
  "/os/init.lua"
}

-- GPU init
local gpu, screen = component.list("gpu")(), component.list("screen")()
if gpu and screen then
  gpu = component.proxy(gpu)
  gpu.bind(screen)
  gpu.setResolution(50, 16)
  gpu.setForeground(0x00FF00)
  gpu.setBackground(0x000000)
  gpu.fill(1, 1, 50, 16, " ")
else
  gpu = nil
end

-- Print text safely
local line = 1
local function println(text)
  if gpu then
    gpu.set(2, line, text)
    line = line + 1
  end
end

-------------------------------------
-- POST (Power-On Self Test)
-------------------------------------
println("FixBIOS v3.0 initializing...")
println("----------------------------------")

local function postCheck(name, pass)
  println(("[%s] %s"):format(pass and " OK " or "FAIL", name))
  if not pass then
    computer.beep(400, 0.4)
  end
end

local hasFS = component.isAvailable("filesystem")
local hasEEPROM = component.isAvailable("eeprom")
local hasGPU = component.isAvailable("gpu")

postCheck("Filesystem", hasFS)
postCheck("EEPROM", hasEEPROM)
postCheck("GPU", hasGPU)
println("----------------------------------")

-------------------------------------
-- Bootloader
-------------------------------------
if not hasFS then
  println("❌ No filesystem detected.")
  println("Insert disk with FixOS and reboot.")
  return
end

local fsAddr = component.list("filesystem")()
local fs = component.proxy(fsAddr)

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
  println("⚠️  FixOS not found on disk!")
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
  os.sleep(1)
  computer.shutdown(true)
else
  print("🚫 Reboot canceled.")
end
