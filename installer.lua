-- FixOS Installer v5 (PRO SYSTEM EDITION)
-- Author: Fixlut & GPT
-- Compatible with OpenComputers

local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local term = require("term")

---------------------------------------
-- SETTINGS
---------------------------------------
local GITHUB_REPO = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/"
local FILES = {
  "boot/init.lua",
  "boot/kernel.lua",
  "boot/shell.lua",
  "FixBIOS.lua",
  "bin/calc.lua",
  "bin/cls.lua",
  "bin/echo.lua",
  "bin/edit.lua",
  "bin/ls.lua"
}

---------------------------------------
-- FUNCTIONS
---------------------------------------
local function printc(t)
  term.write("[FixOS Setup] " .. t .. "\n")
end

local function checkInternet()
  if not component.isAvailable("internet") then
    printc("❌ Немає інтернет-карти! Встановлення неможливе.")
    return false
  end
  return true
end

local function checkDisk()
  local addr = component.list("filesystem")()
  if not addr then
    printc("❌ Не знайдено файлової системи.")
    return nil
  end
  local disk = component.proxy(addr)
  printc("✅ Диск знайдено: " .. addr)
  return disk
end

local function formatDisk(disk)
  printc("🧹 Форматування диска...")
  for file in disk.list("/") do
    disk.remove(file)
  end
end

local function downloadFile(url, path)
  local handle, reason = component.internet.request(url)
  if not handle then
    printc("❌ Неможливо завантажити: " .. reason)
    return false
  end

  local data = ""
  for chunk in handle do
    data = data .. chunk
  end
  handle.close()

  local dir = path:match("(.+)/[^/]+$")
  if dir and not fs.exists(dir) then
    fs.makeDirectory(dir)
  end

  local f = io.open(path, "w")
  f:write(data)
  f:close()
  printc("✅ Завантажено: " .. path)
  return true
end

local function installFiles()
  printc("⬇️ Завантаження файлів з GitHub...")
  for _, path in ipairs(FILES) do
    local url = GITHUB_REPO .. path
    downloadFile(url, "/" .. path)
  end
end

local function writeBIOS()
  printc("⚙️ Встановлення FixBIOS v5 у EEPROM...")
  local eeprom = component.proxy(component.list("eeprom")())
  local file = io.open("/FixBIOS.lua", "r")
  if not file then
    printc("❌ Не знайдено FixBIOS.lua у корені.")
    return
  end
  local bios = file:read("*a")
  file:close()
  eeprom.set(bios)
  eeprom.setLabel("FixBIOS v5")
  printc("✅ BIOS встановлено успішно.")
end

---------------------------------------
-- MAIN INSTALLER LOGIC
---------------------------------------
term.clear()
printc("💿 Вітаємо у FixOS Installer v5!")
os.sleep(1)

if not checkInternet() then return end
local disk = checkDisk()
if not disk then return end

os.sleep(0.5)
formatDisk(disk)
os.sleep(0.5)
installFiles()
os.sleep(0.5)
writeBIOS()

printc("🎉 Установка FixOS завершена!")
printc("🔁 Перезавантаження через 3 секунди...")
os.sleep(3)
computer.shutdown(true)
