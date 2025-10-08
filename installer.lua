-- installer.lua
-- FixOS Installer PRO (stable) — vFinal
-- by Fixlut & GPT (adapted)

-- safe requires / globals fallback
local ok, component = pcall(require, "component"); if not ok then component = _G.component end
local ok2, computer = pcall(require, "computer"); if not ok2 then computer = _G.computer end
local ok3, fs_api = pcall(require, "filesystem"); if not ok3 then fs_api = _G.filesystem end
local ok4, term = pcall(require, "term"); if not ok4 then term = _G.term end

local unicode = unicode -- available globally in OC
local haveInternet = component and component.isAvailable and component.isAvailable("internet")
local haveEEPROM   = component and component.isAvailable and component.isAvailable("eeprom")
local haveGPU      = component and component.isAvailable and component.isAvailable("gpu")
local haveScreen   = component and component.isAvailable and component.isAvailable("screen")

-- CONFIG
local GITHUB_RAW_BASE = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/"
local FILES = {
  "boot/init.lua",
  "boot/kernel.lua",
  "boot/shell.lua",
  "bin/echo.lua",
  "bin/ls.lua",
  "bin/cls.lua",
  "bin/calc.lua",
  "bin/edit.lua",
  "FixBIOS.lua"
}

-- helpers
local function printf(fmt, ...) term.write(string.format(fmt, ...) .. "\n") end
local function pause(s) if s then os.sleep(s) else os.sleep(0.05) end end

-- try to get proxies
local function getProxy(kind)
  local addr = component.list(kind)()
  if not addr then return nil end
  return component.proxy(addr)
end

local eepromProxy = getProxy("eeprom")
local gpuProxy    = getProxy("gpu")
local screenAddr  = component.list("screen")() -- address only for bind

-- attempt set resolution 100x50 safely
local function safeSetResolution(resW, resH)
  if not gpuProxy or not screenAddr then return false end
  pcall(function()
    gpuProxy.bind(screenAddr, true)
    -- only try if supported
    local ok, w, h = pcall(gpuProxy.getResolution, gpuProxy)
    if ok and w and h then
      -- try to set 100x50; if unsupported, pcall will fail quietly
      pcall(gpuProxy.setResolution, gpuProxy, resW, resH)
    end
  end)
  return true
end

-- UI helpers (center using unicode length)
local function drawCenteredLine(y, text, color)
  if not gpuProxy then return end
  local ok, w = pcall(gpuProxy.getResolution, gpuProxy)
  if not ok or not w then return end
  local len = unicode and unicode.len(text) or #text
  local x = math.floor(w/2 - len/2)
  if color then pcall(gpuProxy.setForeground, gpuProxy, color) end
  pcall(gpuProxy.set, gpuProxy, x, y, text)
end

local function clearScreen()
  if not gpuProxy then return end
  local ok, w, h = pcall(gpuProxy.getResolution, gpuProxy)
  if ok and w and h then
    pcall(gpuProxy.setBackground, gpuProxy, 0x000000)
    pcall(gpuProxy.fill, gpuProxy, 1, 1, w, h, " ")
  end
end

-- fetch remote (internet) safe
local function fetch_remote(path)
  if not haveInternet then return nil, "no internet component" end
  local url = GITHUB_RAW_BASE .. path
  local ok,handle_or_err = pcall(component.internet.request, component, url)
  if not ok or not handle_or_err then return nil, tostring(handle_or_err) end
  local data = ""
  for chunk in handle_or_err do data = data .. chunk end
  if handle_or_err.close then pcall(handle_or_err.close, handle_or_err) end
  if data:match("^%s*<") then return nil, "got HTML (raw URL problem)" end
  return data, nil
end

-- fetch local fallback /disk/FixOS/<path>
local function fetch_local(path)
  local localPath = "/disk/FixOS/" .. path
  if fs_api.exists(localPath) then
    local f = io.open(localPath, "r")
    if not f then return nil, "cannot open local file" end
    local c = f:read("*a"); f:close()
    return c, nil
  end
  return nil, "no local file"
end

local function fetch_with_fallback(path)
  local data, err = fetch_remote(path)
  if data then return data end
  local d2, e2 = fetch_local(path)
  if d2 then return d2 end
  return nil, (err or "") .. "; " .. (e2 or "")
end

-- write file to root fs (via Lua io - this installer runs in OpenOS)
local function write_file(dest, content)
  local dir = dest:match("(.+)/[^/]+$")
  if dir and not fs_api.exists(dir) then fs_api.makeDirectory(dir) end
  local f, ferr = io.open(dest, "w")
  if not f then return false, ferr end
  f:write(content); f:close()
  return true
end

-- recursive delete for component proxy filesystem
local function proxy_remove_recursive(proxy, path)
  local list = proxy.list(path)
  for name,_ in pairs(list) do
    local sub = path .. (path:sub(-1) == "/" and "" or "/") .. name
    if proxy.isDirectory(sub) then
      proxy_remove_recursive(proxy, sub)
      pcall(proxy.remove, proxy, sub)
    else
      pcall(proxy.remove, proxy, sub)
    end
  end
end

local function format_target_proxy(proxy)
  printf("Formatting target filesystem (safe)...")
  local root = "/"
  local list = proxy.list(root)
  for name,_ in pairs(list) do
    local p = "/" .. name
    if proxy.isDirectory(p) then
      proxy_remove_recursive(proxy, p)
      pcall(proxy.remove, proxy, p)
    else
      pcall(proxy.remove, proxy, p)
    end
  end
  printf("Done.")
end

-- Build FixBIOS vPro2 (embedded) with resolution 100x50
local FIXBIOS_VPRO2 = [[
-- FixBIOS vPro2 (embedded) — resolution 100x50
local component = component
local computer = computer
local unicode = unicode

local function findProxy(kind)
  for a,t in component.list() do if t==kind then return component.proxy(a) end end
  return nil
end

local gpu = findProxy("gpu")
local screen = findProxy("screen")
local eeprom = findProxy("eeprom")

if gpu and screen then
  pcall(function()
    gpu.bind(screen.address)
    pcall(gpu.setResolution, gpu, 100, 50)
    pcall(gpu.setBackground, gpu, 0x000000)
    pcall(gpu.setForeground, gpu, 0x00FF00)
    pcall(gpu.fill, gpu, 1, 1, 100, 50, " ")
    pcall(gpu.set, gpu, 30, 6, "███████╗██╗██╗  ██╗ ██████╗ ███████╗")
    pcall(gpu.set, gpu, 30, 7, "██╔════╝██║██║ ██╔╝██╔═══██╗██╔════╝")
    pcall(gpu.set, gpu, 30, 8, "███████╗██║█████╔╝ ██║   ██║█████╗  ")
    pcall(gpu.set, gpu, 30, 9, "╚════██║██║██╔═██╗ ██║   ██║██╔══╝  ")
    pcall(gpu.set, gpu, 30,10, "███████║██║██║  ██╗╚██████╔╝██║     ")
    pcall(gpu.set, gpu, 30,11, "╚══════╝╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     ")
    pcall(gpu.set, gpu, 44,14, "FixBIOS vPro2 — Booting")
  end)
end

local function clearScreen()
  if gpu then pcall(gpu.fill, gpu, 1,1,100,50," ") end
end

local function showMessage(y, str, color)
  if not gpu then return end
  local ok, w = pcall(gpu.getResolution, gpu)
  if not ok or not w then return end
  local len = unicode and unicode.len(str) or #str
  local x = math.floor(w/2 - len/2)
  pcall(gpu.setForeground, gpu, color or 0x00FF00)
  pcall(gpu.set, gpu, x, y, str)
end

local function readAll(handle)
  local s = ""
  while true do
    local chunk = fs.read(handle, 65536)
    if not chunk or chunk == "" then break end
    s = s .. chunk
  end
  return s
end

local fs = findProxy("filesystem")
if not fs then
  showMessage(10, "No filesystem found. Insert disk & reboot", 0xFF0000)
  return
end

local bootPaths = {"/boot/init.lua", "/boot/kernel.lua", "/init.lua"}
for _, p in ipairs(bootPaths) do
  if fs.exists(p) then
    showMessage(10, "Found: "..p.." — loading...", 0x00FF00)
    local h = fs.open(p, "r")
    if h then
      local data = ""
      repeat
        local chunk = fs.read(h, 65536)
        data = data .. (chunk or "")
      until not chunk
      fs.close(h)
      local ok, chunkOrErr = load(data, "="..p)
      if not ok then
        showMessage(12, "Boot load error: "..tostring(chunkOrErr), 0xFF5555)
        return
      end
      pcall(chunkOrErr)
      return
    end
  end
end

showMessage(10, "No bootable FixOS found. Install & reboot.", 0xFF0000)
]]

-- main
clearScreen()
safeSetResolution(100, 50)
clearScreen()
drawCenteredLine(3, "FixOS Installer PRO", 0x00FF00)
drawCenteredLine(5, "Resolution set: 100x50 (if supported)", 0xAAAAAA)

-- ask BIOS variant
print()
term.write("Choose BIOS variant to install (lite/pro/debug). Type and Enter: ")
local choice = io.read()
choice = (choice or ""):lower()

-- find target filesystem proxy (use computer.getBootAddress() if valid, else first fs)
local targetAddr = computer.getBootAddress()
local targetProxy = nil
if targetAddr then
  local okp, p = pcall(component.proxy, component.list("filesystem")())
  -- ignore; we will search proxies below
end

-- pick first filesystem proxy
for addr in component.list("filesystem") do
  targetProxy = component.proxy(addr)
  break
end

if not targetProxy then
  printf("No filesystem device detected. Insert disk and retry.")
  return
end

-- confirm erase
print()
term.write("WARNING: Installer will ERASE root of the target disk. Type EXACT to confirm: ERASE AND INSTALL\n> ")
local confirm = io.read()
if confirm ~= "ERASE AND INSTALL" then
  printf("Aborted by user.")
  return
end

-- format target (via proxy)
format_target_proxy(targetProxy)

-- install files (fetch remote or local)
printf("Installing files...")
for _, rel in ipairs(FILES) do
  printf("-> %s", rel)
  local content, err = fetch_with_fallback(rel)
  if not content then
    printf("Failed to obtain %s: %s", rel, tostring(err))
    printf("Aborting install.")
    return
  end
  local okw, werr = write_file("/" .. rel, content)
  if not okw then
    printf("Write failed for /%s : %s", rel, tostring(werr))
    return
  end
end

-- write autorun
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

-- EEPROM backup & write chosen BIOS
if not eepromProxy then
  printf("No EEPROM found; skipping BIOS write. Install finished.")
  term.write("Reboot now? (y/n): ")
  local r = io.read()
  if r == "y" then computer.shutdown(true) end
  return
end

-- backup current
local okb, cur = pcall(function() return eepromProxy.get() end)
if okb and cur then
  local bf = io.open("/eeprom_backup.lua", "w")
  if bf then bf:write(cur); bf:close(); printf("EEPROM backup saved -> /eeprom_backup.lua") end
end

-- determine bios content to write
local biosContent = nil
local file_bios_local, errb = fetch_with_fallback("FixBIOS.lua")
if file_bios_local then biosContent = file_bios_local end

if not biosContent then
  -- pick variant based on user's choice; use embedded FIXBIOS_VPRO2 for pro/default
  if choice == "lite" then
    biosContent = "-- auto-generated BIOS lite\\n" .. "local component = component\\nfor a,t in component.list('filesystem') do local p=component.proxy(a) if p.exists('/boot/init.lua') then local h=p.open('/boot/init.lua','r') local s='' repeat local c = p.read(h, 65536) s=s..(c or '') until not c p.close(h) local f,err = load(s, '=init') if f then pcall(f) end return end end\\n"
  elseif choice == "debug" then
    biosContent = "-- debug BIOS\\nlocal component=require('component') print('Debug BIOS') for a,t in component.list('filesystem') do print(a,t) end"
  else
    biosContent = FIXBIOS_VPRO2
  end
end

-- sanity
if biosContent:match("^%s*<") then
  printf("ERROR: BIOS looks like HTML. Aborting BIOS write.")
  return
end

-- confirm BIOS write
print()
term.write("Type EXACTLY WRITE BIOS to write new EEPROM, or press Enter to skip: ")
local wb = io.read()
if wb ~= "WRITE BIOS" then
  printf("Skipped BIOS write. Install finished.")
  term.write("Reboot now? (y/n): ")
  local rr = io.read()
  if rr == "y" then computer.shutdown(true) end
  return
end

-- write & label
local okw, werr = pcall(function() eepromProxy.set(biosContent) end)
if not okw then
  printf("Failed to write EEPROM: %s", tostring(werr))
  return
end
pcall(eepromProxy.setLabel, "FixBIOS vPro2")
pcall(eepromProxy.setData, tostring(component.list("filesystem")())) -- best-effort

printf("EEPROM flashed. Install complete.")
term.write("Reboot now? (y/n): ")
local rr = io.read()
if rr == "y" then computer.shutdown(true) end
