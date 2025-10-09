-- installer.lua
-- FixOS PRO Installer (stable, safe)
-- by Fixlut & GPT (final)

-- safe require fallback (works inside OpenOS shell)
local ok, component = pcall(require, "component"); if not ok then component = _G.component end
local ok2, computer = pcall(require, "computer"); if not ok2 then computer = _G.computer end
local ok3, fs_api = pcall(require, "filesystem"); if not ok3 then fs_api = _G.filesystem end
local ok4, term = pcall(require, "term"); if not ok4 then term = _G.term end
local unicode = _G.unicode

-- config
local GITHUB_RAW_BASES = {
  "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/",
  "http://raw.githack.com/FixlutGames21/FixOS/main/"
}
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

local function printf(s, ...) term.write(string.format(s, ...) .. "\n") end
local function pause(t) if t then os.sleep(t) else os.sleep(0.05) end end

-- proxies
local function getFirstProxy(kind)
  for addr in component.list(kind) do
    return component.proxy(addr)
  end
  return nil
end

local eepromProxy = getFirstProxy("eeprom")
local gpuProxy    = getFirstProxy("gpu")
local screenAddr  = (component.list("screen")()) -- address or nil

-- safe resolution attempt (100x50)
local function safeSetResolution(w,h)
  if not gpuProxy or not screenAddr then return end
  pcall(function()
    gpuProxy.bind(screenAddr, true)
    local ok, curW, curH = pcall(gpuProxy.getResolution, gpuProxy)
    if ok and curW and curH then
      pcall(gpuProxy.setResolution, gpuProxy, w, h)
    end
  end)
end

local function centerPrint(y, text, color)
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

-- fetch remote with several bases, safe and returns STRING or nil+err
local function fetch_remote(path)
  if not (component and component.isAvailable and component.isAvailable("internet")) then
    return nil, "no internet"
  end
  for _, base in ipairs(GITHUB_RAW_BASES) do
    local url = base .. path
    local ok, handle_or_err = pcall(component.internet.request, component, url)
    if ok and handle_or_err then
      local data = ""
      for chunk in handle_or_err do
        data = data .. chunk
      end
      if handle_or_err.close then pcall(handle_or_err.close, handle_or_err) end
      if type(data) == "string" and not data:match("^%s*<") then
        return data
      end
    end
  end
  return nil, "remote failed"
end

-- local fallback from /disk/FixOS/
local function fetch_local(path)
  local localPath = "/disk/FixOS/" .. path
  if fs_api.exists(localPath) then
    local f = io.open(localPath, "r")
    if not f then return nil, "cannot open local" end
    local content = f:read("*a"); f:close()
    return content
  end
  return nil, "no local"
end

-- universal fetch, ensures result is string
local function fetch_with_fallback(path)
  local data, err = fetch_remote(path)
  if data then
    if type(data) ~= "string" then return nil, "remote returned not string" end
    return data
  end
  local d2, e2 = fetch_local(path)
  if d2 then
    if type(d2) ~= "string" then return nil, "local returned not string" end
    return d2
  end
  return nil, (err or "") .. "; " .. (e2 or "")
end

-- write file to root filesystem (OpenOS style)
local function write_file(dest, content)
  if type(content) ~= "string" then return false, "content is not string" end
  local dir = dest:match("(.+)/[^/]+$")
  if dir and not fs_api.exists(dir) then fs_api.makeDirectory(dir) end
  local f, ferr = io.open(dest, "w")
  if not f then return false, ferr end
  f:write(content); f:close()
  return true
end

-- remove recursive on proxy filesystem (proxy.list returns table)
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

local function format_target(proxy)
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
  printf("Format done.")
end

-- embedded FixBIOS (improved, safe)
local FIXBIOS = [[
-- FixBIOS (stable, safe)
local component = component
local computer = computer
local unicode = unicode

local function findProxy(kind)
  for addr, t in component.list() do
    if t == kind then return component.proxy(addr) end
  end
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
    pcall(gpu.fill, gpu, 1,1,100,50," ")
    pcall(gpu.set, gpu, 36, 6, "███████╗██╗██╗  ██╗ ██████╗ ███████╗")
    pcall(gpu.set, gpu, 36, 7, "██╔════╝██║██║ ██╔╝██╔═══██╗██╔════╝")
    pcall(gpu.set, gpu, 36, 8, "███████╗██║█████╔╝ ██║   ██║█████╗  ")
    pcall(gpu.set, gpu, 36, 9, "╚════██║██║██╔═██╗ ██║   ██║██╔══╝  ")
    pcall(gpu.set, gpu, 36,10, "███████║██║██║  ██╗╚██████╔╝██║     ")
    pcall(gpu.set, gpu, 36,11, "╚══════╝╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     ")
    pcall(gpu.set, gpu, 48,14, "FixBIOS — Stable")
  end)
end

local function show(y, txt, color)
  if not gpu then return end
  local ok,w = pcall(gpu.getResolution, gpu)
  if not ok or not w then return end
  local len = unicode and unicode.len(txt) or #txt
  local x = math.floor(w/2 - len/2)
  pcall(gpu.setForeground, gpu, color or 0x00FF00)
  pcall(gpu.set, gpu, x, y, txt)
end

local fs = findProxy("filesystem")
if not fs then
  show(12, "No filesystem found. Insert system disk & reboot.", 0xFF0000)
  return
end

local bootPaths = {"/boot/init.lua", "/boot/kernel.lua", "/init.lua"}
for _, p in ipairs(bootPaths) do
  if fs.exists(p) then
    show(12, "Found: "..p.." — loading...", 0x00FF00)
    local h = fs.open(p, "r")
    if not h then show(14, "Cannot open file: "..p, 0xFF5555); return end
    local data = ""
    repeat
      local chunk = fs.read(h, 65536)
      data = data .. (chunk or "")
    until not chunk
    fs.close(h)
    local ok, chunkOrErr = load(data, "="..p)
    if not ok then
      show(14, "Load error: "..tostring(chunkOrErr), 0xFF5555)
      return
    end
    local succ, err = pcall(chunkOrErr)
    if not succ then show(14, "Runtime error: "..tostring(err), 0xFF5555) end
    return
  end
end

show(12, "No bootable FixOS found on disk.", 0xFF0000)
]]

-- start installer UI
clearScreen()
safeSetResolution(100,50)
clearScreen()
centerPrint(3, "FixOS PRO Installer", 0x00FF00)
centerPrint(5, "Resolution: 100x50 (if supported)", 0xAAAAAA)
print()
term.write("Choose BIOS variant (lite / pro / debug), then Enter: ")
local variant = (io.read() or "pro"):lower()

-- pick target filesystem proxy (first found)
local targetProxy = nil
local targetAddr = computer.getBootAddress()
-- try boot address first
if targetAddr then
  for addr in component.list("filesystem") do
    if addr == targetAddr then targetProxy = component.proxy(addr); break end
  end
end
-- else first filesystem
if not targetProxy then
  for addr in component.list("filesystem") do
    targetProxy = component.proxy(addr)
    break
  end
end
if not targetProxy then printf("No filesystem found. Insert disk and retry."); return end

-- confirm destructive action
print()
term.write("WARNING: This will ERASE root of target disk. Type EXACT: ERASE AND INSTALL\n> ")
local confirm = io.read()
if confirm ~= "ERASE AND INSTALL" then printf("Aborted."); return end

-- format target
format_target(targetProxy)

-- download/install files
printf("Installing files...")
for _, rel in ipairs(FILES) do
  printf("-> %s", rel)
  local content, ferr = fetch_with_fallback(rel)
  if not content then
    printf("Failed to obtain %s : %s", rel, tostring(ferr))
    printf("Aborting.")
    return
  end
  local okw, werr = write_file("/" .. rel, content)
  if not okw then
    printf("Failed to write /%s : %s", rel, tostring(werr))
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

-- EEPROM backup + write
if not eepromProxy then
  printf("No EEPROM found; skipping BIOS write. Install finished.")
  term.write("Reboot now? (y/n): ")
  if (io.read() or ""):lower():sub(1,1) == "y" then computer.shutdown(true) end
  return
end

-- backup
local okb, cur = pcall(function() return eepromProxy.get() end)
if okb and cur and cur ~= "" then
  local bf = io.open("/eeprom_backup.lua","w")
  if bf then bf:write(cur); bf:close(); printf("EEPROM backup saved -> /eeprom_backup.lua") end
end

-- build chosen BIOS content
local biosContent = nil
local localBIOS, berr = fetch_with_fallback("FixBIOS.lua")
if localBIOS and type(localBIOS) == "string" then biosContent = localBIOS end

if not biosContent then
  if variant == "lite" then
    biosContent = "-- FixBIOS LITE\\n" .. "local component = component\\nfor a,t in component.list('filesystem') do local p=component.proxy(a) if p.exists('/boot/init.lua') then local h = p.open('/boot/init.lua','r'); local s=''; repeat local c=p.read(h,65536) s=s..(c or '') until not c; p.close(h); local f=load(s,'=init'); if f then pcall(f) end; return end end"
  elseif variant == "debug" then
    biosContent = "-- FixBIOS DEBUG\\nlocal component=require('component') print('FS:'); for a,t in component.list('filesystem') do print(a,t) end"
  else
    biosContent = FIXBIOS
  end
end

if type(biosContent) ~= "string" then printf("Bad BIOS content type"); return end
if biosContent:match("^%s*<") then printf("BIOS looks like HTML. Aborting."); return end

print()
term.write("Type EXACTLY: WRITE BIOS  to write new EEPROM, or press Enter to skip: ")
local wb = io.read()
if wb ~= "WRITE BIOS" then printf("Skipped BIOS write. Install finished."); term.write("Reboot now? (y/n): "); if (io.read() or ""):lower():sub(1,1) == "y" then computer.shutdown(true) end; return end

local succ, serr = pcall(function() eepromProxy.set(biosContent) end)
if not succ then printf("EEPROM write failed: %s", tostring(serr)); return end
pcall(eepromProxy.setLabel, "FixBIOS Stable")
-- try to set boot address to target filesystem (best-effort)
pcall(function() eepromProxy.setData(component.list("filesystem")() or "") end)

printf("EEPROM flashed. Install complete.")
term.write("Reboot now? (y/n): ")
local rr = io.read()
if rr and rr:lower():sub(1,1) == "y" then computer.shutdown(true) end
