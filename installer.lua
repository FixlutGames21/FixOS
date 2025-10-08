-- installer.lua  (PRO MAX v4 safe)
local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local term = require("term")
local shell = require("shell")

local gpu = component.isAvailable("gpu") and component.gpu or nil
local inet = component.isAvailable("internet") and component.internet or nil
local eeprom = component.isAvailable("eeprom") and component.eeprom or nil

local function center(t)
  if not gpu then print(t); return end
  local w = ({gpu.getResolution()})[1]
  local curY = select(2, term.getCursor())
  term.setCursor(math.max(1, (w - #t)//2), curY)
  print(t)
end

term.clear(); print("=== FixOS Installer PRO MAX v4 ==="); print()

-- network check
local function netOK()
  if not inet then return false end
  local ok, handle = pcall(inet.request, "http://example.com")
  if ok and handle then handle.close(); return true end
  return false
end

local baseHTTP = "http://raw.githack.com/FixlutGames21/FixOS/main/"

if not netOK() then
  print("⚠ No HTTP reachable. Installer will try local /disk/FixOS fallback.")
end

-- files list (match your repo)
local files = {
  "boot/init.lua",
  "boot/kernel.lua",
  "boot/shell.lua",
  "bin/echo.lua",
  "bin/ls.lua",
  "bin/cls.lua",
  "bin/calc.lua",
  "bin/edit.lua"
}

-- download helper
local function fetch(path)
  -- try network first
  if netOK() then
    local url = baseHTTP .. path
    local ok, handle = pcall(inet.request, url)
    if ok and handle then
      local content = ""
      for chunk in handle do content = content .. chunk end
      handle.close()
      -- detect HTML
      if content:match("^%s*<") then
        return nil, "received HTML (bad URL or redirect)"
      end
      return content
    end
  end
  -- fallback: local disk
  local diskPath = "/disk/FixOS/" .. path
  if fs.exists(diskPath) then
    local f = io.open(diskPath, "r")
    if f then
      local c = f:read("*a"); f:close()
      return c
    end
  end
  return nil, "not available (net/local)"
end

-- install files
print("Installing files...")
for i, p in ipairs(files) do
  local content, err = fetch(p)
  if not content then
    print("Failed to get "..p..": "..tostring(err))
    print("Aborting install.")
    return
  end
  local dest = "/" .. p
  fs.makeDirectory(fs.path(dest))
  local f = io.open(dest, "w")
  if not f then
    print("Cannot write "..dest)
    return
  end
  f:write(content); f:close()
  io.write(string.format("Installed: %s\n", dest))
end

-- autorun
local autorun = [[
term.clear()
print("====================================")
print("        🪟 Welcome to FixOS")
print("====================================")
os.sleep(0.6)
local ok, err = pcall(function() os.sleep(0) end)
-- start shell
local s = loadfile("/boot/shell.lua")
if s then s() end
]]
local f = io.open("/autorun.lua","w")
f:write(autorun); f:close()
print("Autorun written -> /autorun.lua")

-- prepare FixBIOS for EEPROM
local biosContent = nil
do
  -- get FixBIOS.lua either from repo or local disk
  local ok, data = pcall(function() return fetch("FixBIOS.lua") end)
  if ok and data then biosContent = data end
  -- if not present, fallback to built-in safe BIOS (we'll embed)
  if not biosContent then
    biosContent = [[
-- builtin FixBIOS v4 fallback: minimal, safe boot
local component = component
local computer = computer
local function safeList(kind)
  for a,t in component.list() do if t==kind then return a end end
  return nil
end
local gpuAddr = safeList("gpu")
local screenAddr = safeList("screen")
if gpuAddr and screenAddr then
  local gpu = component.proxy(gpuAddr); gpu.bind(screenAddr)
  pcall(function() gpu.setResolution(50,16); gpu.setBackground(0x000000); gpu.setForeground(0x00FF00); gpu.fill(1,1,50,16," ") end)
end
local fsAddr = safeList("filesystem")
if not fsAddr then return end
local fs = component.proxy(fsAddr)
local bootPaths = {"/boot/fixos.lua","/init.lua","/os/init.lua"}
for _,p in ipairs(bootPaths) do
  if fs.exists(p) then
    local h = fs.open(p,"r"); local data = ""
    repeat local chunk = fs.read(h, math.huge); data = data .. (chunk or "") until not chunk
    fs.close(h)
    local chunk,err = load(data,"="..p)
    if not chunk then return end
    chunk(); return
  end
end
]]
  end
end

-- EEPROM backup + write (if possible)
if eeprom then
  local ok, cur = pcall(eeprom.get)
  if ok and cur then
    local bf = io.open("/eeprom_backup.lua","w")
    if bf then bf:write(cur); bf:close(); print("EEPROM backup saved -> /eeprom_backup.lua") end
  end
  print("Writing FixBIOS to EEPROM (will ask confirmation)...")
  io.write("Type EXACTLY 'FORMAT EEPROM' to write BIOS (or press Enter to skip): ")
  local confirm = io.read()
  if confirm == "FORMAT EEPROM" then
    local success, err = pcall(eeprom.set, biosContent)
    if success then
      pcall(function() eeprom.setLabel("FixBIOS v4") end)
      print("✅ EEPROM flashed with FixBIOS.")
      -- create restore helper
      local rf = io.open("/eeprom_restore.lua","w")
      rf:write([[
local component = require("component")
local e = component.proxy(component.list("eeprom")())
local f = io.open("/eeprom_backup.lua","r")
if f then local d = f:read("*a"); f:close(); e.set(d); print("EEPROM restored") else print("No backup found") end
]])
      rf:close()
      print("Restore helper created -> /eeprom_restore.lua")
    else
      print("EEPROM write failed: "..tostring(err))
    end
  else
    print("Skipped EEPROM write.")
  end
else
  print("No EEPROM component found; skipping EEPROM step.")
end

print("\nInstall finished. Reboot recommended.")
io.write("Reboot now? (y/n): ")
local r = io.read()
if r == "y" then
  print("Rebooting...")
  os.sleep(0.6)
  computer.shutdown(true)
else
  print("Done. Start FixOS with /boot/init.lua or reboot.")
end
