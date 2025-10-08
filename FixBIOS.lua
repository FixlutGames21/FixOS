-- FixBIOS.lua (this string gets written to EEPROM by installer)
local component = component
local computer = computer

local function safeList(kind)
  for addr, t in component.list() do
    if t == kind then return addr end
  end
  return nil
end

-- GPU & screen
local gpuAddr = safeList("gpu")
local screenAddr = safeList("screen")
local gpu = nil
if gpuAddr and screenAddr then
  gpu = component.proxy(gpuAddr)
  gpu.bind(screenAddr)
  -- try a safe smaller res
  local ok, w,h = pcall(function() return gpu.getResolution() end)
  if ok and w and h and w >= 50 and h >= 16 then
    gpu.setResolution(50,16)
  end
  gpu.setBackground(0x000000)
  gpu.setForeground(0x00FF00)
  gpu.fill(1,1,50,16," ")
end

local function println(s)
  if gpu then
    local y = (println._line or 1)
    gpu.set(2, y, tostring(s))
    println._line = y + 1
  end
end

-- Splash ASCII
if gpu then
  gpu.fill(1,1,50,16," ")
  gpu.set(6,3,"███████╗██╗██╗  ██╗ ██████╗ ███████╗")
  gpu.set(6,4,"██╔════╝██║██║ ██╔╝██╔═══██╗██╔════╝")
  gpu.set(6,5,"███████╗██║█████╔╝ ██║   ██║█████╗  ")
  gpu.set(6,6,"╚════██║██║██╔═██╗ ██║   ██║██╔══╝  ")
  gpu.set(6,7,"███████║██║██║  ██╗╚██████╔╝██║     ")
  gpu.set(6,8,"╚══════╝╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     ")
  gpu.set(18,10,"FixOS BIOS")
  gpu.set(16,12,"Starting system...")
  os.sleep(1.4)
  gpu.fill(1,1,50,16," ")
end

-- POST
println("FixBIOS POST")
local function post(name, ok) println(string.format("[%s] %s", ok and " OK " or "FAIL", name)) end
post("Filesystem", safeList("filesystem") ~= nil)
post("EEPROM", safeList("eeprom") ~= nil)
post("GPU", gpu ~= nil)
os.sleep(0.6)

if not safeList("filesystem") then
  println("No filesystem. Insert system disk and reboot.")
  return
end

local fsAddr = safeList("filesystem")
local fs = component.proxy(fsAddr)

local bootPaths = {"/boot/fixos.lua", "/init.lua", "/os/init.lua"}
for _, p in ipairs(bootPaths) do
  if fs.exists(p) then
    println("Booting: "..p)
    local handle = fs.open(p, "r")
    local data = ""
    repeat
      local chunk = fs.read(handle, math.huge)
      data = data .. (chunk or "")
    until not chunk
    fs.close(handle)
    local chunk, err = load(data, "="..p)
    if not chunk then
      println("Boot load error: "..tostring(err))
      return
    end
    println("Running FixOS")
    chunk()
    return
  end
end

println("FixOS not found on disk.")
println("Please install FixOS and reboot.")
