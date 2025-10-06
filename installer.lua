-------------------------------------------------------
-- FixOS Installer PRO MAX
-- by Fixlut 💿
-------------------------------------------------------
local component = require("component")
local computer = require("computer")
local term = require("term")
local fs = require("filesystem")

local gpu = component.isAvailable("gpu") and component.gpu or nil
local internet = component.isAvailable("internet") and component.internet or nil

-------------------------------------------------------
-- UI helpers
-------------------------------------------------------
local function printCentered(text)
  local w, _ = gpu.getResolution()
  term.setCursor((w - #text) // 2, select(2, term.getCursor()))
  print(text)
end

local function banner()
  term.clear()
  print("====================================")
  printCentered("🚀  FIXOS INSTALLER  PRO  MAX  🚀")
  print("====================================")
  print()
end

local function progressBar(cur, total)
  local percent = math.floor((cur / total) * 100)
  local bar = string.rep("█", percent // 5) .. string.rep(" ", 20 - (percent // 5))
  term.write(string.format("\r[%s] %d%%", bar, percent))
end

-------------------------------------------------------
-- Setup
-------------------------------------------------------
banner()
print("Checking system components...")

if not gpu then
  io.stderr:write("❌ No GPU detected!\n")
  return
end

if not internet then
  io.stderr:write("❌ No Internet Card detected!\n")
  io.stderr:write("Insert card or use offline installer (/disk/FixOS)\n")
  return
end

local function hasHTTP()
  local ok, result = pcall(function()
    local handle = internet.request("http://example.com")
    if handle then handle.close() end
    return true
  end)
  return ok and result
end

if not hasHTTP() then
  print("⚠️  HTTP request failed, switching to proxy...")
end

-------------------------------------------------------
-- File list to download
-------------------------------------------------------
local baseURL = "http://raw.githack.com/FixlutGames21/FixOS/main/"
local files = {
  "boot/init.lua",
  "boot/system.lua",
  "bin/shell.lua",
  "bin/ls.lua",
  "bin/edit.lua"
}

-------------------------------------------------------
-- Download and install
-------------------------------------------------------
print("\nInstalling FixOS...")
local total = #files

for i, path in ipairs(files) do
  local url = baseURL .. path
  local fullPath = "/" .. path
  fs.makeDirectory(fs.path(fullPath))

  local handle = internet.request(url)
  local result = ""
  if handle then
    for chunk in handle do
      result = result .. chunk
    end
    handle.close()
    local f = io.open(fullPath, "w")
    f:write(result)
    f:close()
  else
    io.stderr:write("\n❌ Failed to download: " .. url .. "\n")
  end

  progressBar(i, total)
  os.sleep(0.1)
end

print("\n✅ Installation complete!")
print("💾 You can now reboot and enjoy FixOS!")
