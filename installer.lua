-------------------------------------------------------
-- FixOS Installer PRO MAX v3
-- by Fixlut 💿
-------------------------------------------------------
local component = require("component")
local term = require("term")
local fs = require("filesystem")
local shell = require("shell")
local computer = require("computer") -- ✅ виправлено

local gpu = component.isAvailable("gpu") and component.gpu or nil
local inet = component.isAvailable("internet") and component.internet or nil

-------------------------------------------------------
-- helpers
-------------------------------------------------------
local function center(text)
  if not gpu then print(text) return end
  local w = ({gpu.getResolution()})[1]
  term.setCursor((w - #text) // 2, select(2, term.getCursor()))
  print(text)
end

local function banner()
  term.clear()
  print("====================================")
  center("🚀  FIXOS INSTALLER  PRO  MAX v3  🚀")
  print("====================================")
  print()
end

local function bar(i, total)
  local p = math.floor((i / total) * 100)
  local filled = string.rep("█", p // 5)
  local empty = string.rep(" ", 20 - (p // 5))
  term.write(string.format("\r[%s%s] %d%%", filled, empty, p))
end

-------------------------------------------------------
-- checks
-------------------------------------------------------
banner()
print("Checking components...\n")

if not inet then
  io.stderr:write("❌  Internet card not found!\n")
  io.stderr:write("Insert card or use /disk/FixOS offline.\n")
  return
end

-------------------------------------------------------
-- basic HTTP check
-------------------------------------------------------
local function netOK()
  local ok, handle = pcall(inet.request, "http://example.com")
  if ok and handle then handle.close() return true end
  return false
end

local baseURL = "http://raw.githack.com/FixlutGames21/FixOS/main/"
if not netOK() then
  print("⚠️  Can't reach http://example.com, continuing anyway.")
end

-------------------------------------------------------
-- files to pull
-------------------------------------------------------
local files = {
  "boot/init.lua",
  "boot/system.lua",
  "bin/shell.lua",
  "bin/ls.lua",
  "bin/edit.lua"
}

-------------------------------------------------------
-- download
-------------------------------------------------------
print("Installing FixOS...\n")
local total = #files
for i, path in ipairs(files) do
  local url = baseURL .. path
  local dest = "/" .. path
  fs.makeDirectory(fs.path(dest))

  local content = ""
  local ok, handle = pcall(inet.request, url)
  if ok and handle then
    for chunk in handle do content = content .. chunk end
    handle.close()
  end

  if content:match("^%s*<") then
    io.stderr:write("\n❌  HTML instead of Lua at: " .. path .. "\n")
    io.stderr:write("Check your network or GitHub raw link.\n")
    return
  end

  local f = io.open(dest, "w")
  if f then f:write(content) f:close() end
  bar(i, total)
  os.sleep(0.05)
end

-------------------------------------------------------
-- autorun setup
-------------------------------------------------------
print("\n\n✅  FixOS installed successfully!")
print("💾  Creating autorun.lua ...")
local autorun = io.open("/autorun.lua", "w")
autorun:write([[
term.clear()
print("====================================")
print("        🪟 Welcome to FixOS 🪟       ")
print("====================================")
os.sleep(1)
shell.execute("/bin/shell.lua")
]])
autorun:close()

print("💾  You can reboot now and enjoy FixOS.\n")

local choice
repeat
  io.write("Reboot now? (y/n): ")
  choice = io.read()
until choice == "y" or choice == "n"

if choice == "y" then
  print("Rebooting...")
  os.sleep(1)
  computer.shutdown(true)
end
