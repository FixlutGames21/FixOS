-- installer.lua
-- FixOS PRO Installer (stable) — installs FixOS files + writes FixBIOS vPro to EEPROM
-- By Fixlut & GPT (stable build)

local component = require("component")
local fs_api = require("filesystem")
local term = require("term")
local computer = require("computer")
local shell = require("shell")

local haveInternet = component.isAvailable("internet")
local haveEEPROM = component.isAvailable("eeprom")

local GITHUB_RAW_BASE = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/"

-- list of repo files to install (path relative in repo)
local FILES = {
  "boot/init.lua",
  "boot/kernel.lua",
  "boot/shell.lua",
  "bin/echo.lua",
  "bin/ls.lua",
  "bin/cls.lua",
  "bin/calc.lua",
  "bin/edit.lua",
  "FixBIOS.lua" -- optional: installer will use local FixBIOS if present, else embedded
}

-- ===== helpers =====
local function printf(s, ...)
  term.write(string.format(s, ...) .. "\n")
end

local function pause(sec)
  if sec then os.sleep(sec) else os.sleep(0.05) end
end

local function find_fs_proxy()
  local addr = component.list("filesystem")()
  if not addr then return nil end
  return component.proxy(addr)
end

local function ensure_dir(path)
  if not fs_api.exists(path) then
    fs_api.makeDirectory(path)
  end
end

-- Recursive remove for component filesystem proxy
local function proxy_remove_recursive(proxy, path)
  -- proxy.list returns table indexed by names; iterate with pairs
  local list = proxy.list(path)
  for name, _ in pairs(list) do
    local sub = path .. (path:sub(-1) == "/" and "" or "/") .. name
    if proxy.isDirectory(sub) then
      proxy_remove_recursive(proxy, sub)
      -- remove directory itself
      pcall(proxy.remove, proxy, sub)
    else
      pcall(proxy.remove, proxy, sub)
    end
  end
end

-- format (clear) disk content using proxy
local function format_disk(proxy)
  printf("Formatting disk (safe remove)...")
  -- list root entries
  local rootList = proxy.list("/")
  for name,_ in pairs(rootList) do
    local path = "/" .. name
    if proxy.isDirectory(path) then
      proxy_remove_recursive(proxy, path)
      pcall(proxy.remove, proxy, path)
    else
      pcall(proxy.remove, proxy, path)
    end
  end
  printf("Disk formatted.")
end

-- fetch via internet.request (if available) or nil
local function fetch_remote(path)
  if not haveInternet then return nil, "no internet component" end
  local url = GITHUB_RAW_BASE .. path
  local ok, handle_or_err = pcall(function() return component.internet.request(url) end)
  if not ok or not handle_or_err then
    return nil, tostring(handle_or_err)
  end
  local data = ""
  -- handle is iterator; it yields chunks (string) on for loop
  for chunk in handle_or_err do
    data = data .. chunk
  end
  -- try to close if possible (some implementations)
  if handle_or_err.close then pcall(handle_or_err.close, handle_or_err) end
  -- sanity: if looks like HTML, treat as error
  if data:match("^%s*<") then
    return nil, "received HTML (bad raw URL or redirect)"
  end
  return data, nil
end

-- read local disk fallback at /disk/FixOS/<path>
local function fetch_local_disk(path)
  local localPath = "/disk/FixOS/" .. path
  if fs_api.exists(localPath) then
    local f = io.open(localPath, "r")
    if not f then return nil, "cannot open local file" end
    local content = f:read("*a")
    f:close()
    return content, nil
  end
  return nil, "no local fallback"
end

local function fetch_file_with_fallback(path)
  -- try remote first
  local data, err = fetch_remote(path)
  if data then return data end
  -- fallback local
  local d2, e2 = fetch_local_disk(path)
  if d2 then return d2 end
  return nil, (err or "") .. "; " .. (e2 or "")
end

-- write file to target path (root filesystem via standard fs API)
local function write_file(destPath, content)
  local dir = destPath:match("(.+)/[^/]+$")
  if dir and not fs_api.exists(dir) then fs_api.makeDirectory(dir) end
  local f, ferr = io.open(destPath, "w")
  if not f then return false, ferr end
  f:write(content)
  f:close()
  return true
end

-- ===== FixBIOS vPro embedded (safe, EEPROM-compatible) =====
local FIXBIOS_VPRO = [[
-- FixBIOS vPro (embedded)
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
if gpu and screen then
  pcall(function()
    gpu.bind(screen.address)
    local ok,w,h = pcall(gpu.getResolution, gpu)
    if ok and w and h and w>=50 and h>=16 then pcall(gpu.setResolution, gpu, 50, 16) end
    pcall(gpu.setBackground, gpu, 0x000000)
    pcall(gpu.setForeground, gpu, 0x00FF00)
    pcall(gpu.fill, gpu, 1,1,50,16," ")
    pcall(gpu.set, gpu, 2,2, "FixBIOS vPro — booting...")
  end)
end

local fs = findProxy("filesystem")
if not fs then
  if gpu then pcall(gpu.set, gpu, 2,4, "No filesystem found. Insert disk and reboot.") end
  return
end

local bootPaths = {"/boot/init.lua", "/init.lua", "/boot/fallback.lua", "/boot/recovery.lua"}
local function readAll(handle)
  local res = ""
  while true do
    local chunk = fs.read(handle, 65536)
    if not chunk or chunk == "" then break end
    res = res .. chunk
  end
  return res
end

for _, p in ipairs(bootPaths) do
  if fs.exists(p) then
    if gpu then pcall(gpu.set, gpu, 2,4, "Found: "..p.." — loading...") end
    local h = fs.open(p, "r")
    if h then
      local data = readAll(h)
      fs.close(h)
      local ok, chunkOrErr = load(data, "="..p)
      if not ok then
        if gpu then pcall(gpu.set, gpu, 2,6, "Boot load error: "..tostring(chunkOrErr)) end
        return
      end
      pcall(chunkOrErr)
      return
    end
  end
end

if gpu then pcall(gpu.set, gpu, 2,6, "FixOS not found on disk. Install FixOS and reboot.") end
]]

-- ===== main installer flow =====
term.clear()
printf("=== FixOS PRO Installer ===")
pause(0.1)

-- find a filesystem proxy (the disk we will install to)
local diskAddr = component.list("filesystem")()
if not diskAddr then
  printf("ERROR: no filesystem device found. Insert a disk and retry.")
  return
end
local diskProxy = component.proxy(diskAddr)
printf("Target filesystem found: %s", diskAddr)

-- confirm formatting (explicit)
printf("")
printf("WARNING: Installer will ERASE the target disk root (safe remove).")
printf("If you have important data on the disk, cancel and back it up.")
io.write("Type EXACTLY: ERASE AND INSTALL  (caps) to continue, or press Enter to abort: ")
local consent = io.read()
if consent ~= "ERASE AND INSTALL" then
  printf("Aborted by user.")
  return
end

-- format disk (safe)
format_disk(diskProxy)

-- fetch and write files
printf("Installing files...")
for i, rel in ipairs(FILES) do
  printf("-> %s", rel)
  local content, err = fetch_file_with_fallback(rel)
  if not content then
    printf("Failed to obtain %s: %s", rel, tostring(err))
    printf("Aborting install. Disk left in cleaned state.")
    return
  end
  local ok, werr = write_file("/" .. rel, content)
  if not ok then
    printf("Failed writing /%s : %s", rel, tostring(werr))
    return
  end
end

-- create autorun to start boot/init
local autorun = [[
term.clear()
print("====================================")
print("        🪟 Welcome to FixOS")
print("====================================")
os.sleep(0.6)
local s = loadfile("/boot/shell.lua") or loadfile("/boot/init.lua")
if s then pcall(s) end
]]
write_file("/autorun.lua", autorun)

printf("Files installed successfully.")

-- EEPROM backup + write
if not haveEEPROM then
  printf("No EEPROM on this machine; skipping BIOS write. You can still boot with inserted disk.")
  printf("Install complete. Reboot recommended.")
  io.write("Reboot now? (y/n): ")
  local r = io.read()
  if r == "y" then os.sleep(0.5); computer.shutdown(true) else printf("Done.") end
  return
end

local eaddr = component.list("eeprom")()
local e = component.proxy(eaddr)
-- try read old content for backup
local ok, cur = pcall(function() return e.get() end)
if ok and cur and cur ~= "" then
  local bf = io.open("/eeprom_backup.lua", "w")
  if bf then bf:write(cur); bf:close(); printf("EEPROM backup saved -> /eeprom_backup.lua") end
else
  printf("No readable EEPROM content or backup skipped.")
end

-- if repo had FixBIOS.lua, use it; else use embedded
local bios_content = nil
local got_bios_local, bios_local_err = fetch_file_with_fallback("FixBIOS.lua")
if got_bios_local then
  bios_content = got_bios_local
  printf("Using FixBIOS.lua from source.")
else
  bios_content = FIXBIOS_VPRO
  printf("Using embedded FixBIOS vPro fallback.")
end

-- sanity: do not write if content looks like HTML
if bios_content:match("^%s*<") then
  printf("ERROR: BIOS content looks like HTML. Aborting EEPROM write.")
  return
end

-- confirm EEPROM write explicitly
printf("")
printf("About to write FixBIOS to EEPROM. This can break boot if wrong.")
io.write("Type EXACTLY: WRITE BIOS  (caps) to proceed, or press Enter to skip: ")
local conf = io.read()
if conf ~= "WRITE BIOS" then
  printf("Skipped EEPROM write. Install finished.")
  io.write("Reboot now to try booting from disk? (y/n): ")
  local rr = io.read()
  if rr == "y" then os.sleep(0.4); computer.shutdown(true) else printf("Done.") end
  return
end

-- write and label
local succ, serr = pcall(function() e.set(bios_content) end)
if not succ then
  printf("Failed writing EEPROM: %s", tostring(serr))
  printf("You can restore with /eeprom_backup.lua if present.")
  return
end
pcall(e.setLabel, e, "FixBIOS vPro")
printf("EEPROM flashed with FixBIOS vPro and labeled.")

-- create restore helper if backup present
if fs_api.exists("/eeprom_backup.lua") then
  local rf = io.open("/eeprom_restore.lua","w")
  rf:write([[
local component = require("component")
local eaddr = component.list("eeprom")()
local e = component.proxy(eaddr)
local f = io.open("/eeprom_backup.lua","r")
if not f then print("No /eeprom_backup.lua found") return end
local data = f:read("*a"); f:close()
pcall(e.set, data)
print("EEPROM restored from /eeprom_backup.lua")
]])
  rf:close()
  printf("Restore helper created -> /eeprom_restore.lua")
end

printf("Install complete. Reboot recommended.")
io.write("Reboot now? (y/n): ")
local r = io.read()
if r == "y" then os.sleep(0.4); computer.shutdown(true) else printf("Done.") end
