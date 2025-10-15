-- FixBIOS.lua — Stable vFinal (for EEPROM)
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
    pcall(gpu.fill, gpu, 1,1,100,50," ")
    pcall(gpu.set, gpu, 36,6,"███████╗██╗██╗  ██╗ ██████╗ ███████╗")
    pcall(gpu.set, gpu, 36,7,"██╔════╝██║██║ ██╔╝██╔═══██╗██╔════╝")
    pcall(gpu.set, gpu, 36,8,"███████╗██║█████╔╝ ██║   ██║█████╗  ")
    pcall(gpu.set, gpu, 36,9,"╚════██║██║██╔═██╗ ██║   ██║██╔══╝  ")
    pcall(gpu.set, gpu, 36,10,"███████║██║██║  ██╗╚██████╔╝██║     ")
    pcall(gpu.set, gpu, 36,11,"╚══════╝╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     ")
    pcall(gpu.set, gpu, 48,14, "FixBIOS Stable — Booting")
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

local fsproxy = findProxy("filesystem")
if not fsproxy then
  show(12, "No filesystem found. Insert disk & reboot.", 0xFF0000)
  return
end

local bootPaths = {"/boot/init.lua", "/boot/kernel.lua", "/init.lua"}
for _, p in ipairs(bootPaths) do
  if fsproxy.exists(p) then
    show(12, "Found: "..p.." — loading...", 0x00FF00)
    local h = fsproxy.open(p,"r")
    if not h then show(14, "Cannot open file: "..p, 0xFF5555); return end
    local data = ""
    repeat local chunk = fsproxy.read(h, 65536) data = data .. (chunk or "") until not chunk
    fsproxy.close(h)
    local ok, chunkOrErr = load(data, "="..p)
    if not ok then show(14, "Load error: "..tostring(chunkOrErr), 0xFF5555); return end
    local succ, err = pcall(chunkOrErr)
    if not succ then show(14, "Runtime error: "..tostring(err), 0xFF5555) end
    return
  end
end

-- If not found, try network boot of installer:
local inet = component.list("internet")() and component.proxy(component.list("internet")())
if inet then
  show(12, "No local OS — trying to load installer from GitHub...", 0x00FF00)
  local url = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/installer.lua"
  local ok, handle = pcall(inet.request, inet, url)
  if ok and handle then
    local data = ""
    if type(handle) == "table" then
      for _, chunk in pairs(handle) do if type(chunk)=="string" then data = data .. chunk end end
    else
      for chunk in handle do data = data .. (chunk or "") end
      if handle.close then pcall(handle.close, handle) end
    end
    if type(data) == "string" and not data:match("^%s*<") then
      local f = io.open("/installer.lua","w")
      if f then f:write(data); f:close(); show(14,"Installer saved -> /installer.lua",0x00FF00); os.sleep(0.6); dofile("/installer.lua"); return end
    else
      show(14, "Network returned invalid data.", 0xFF5555)
    end
  else
    show(14, "Network request failed.", 0xFF5555)
  end
end

show(12, "No bootable FixOS found on disk.", 0xFF0000)
