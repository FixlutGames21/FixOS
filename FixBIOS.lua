-- FixBIOS vPro (EEPROM firmware)
-- Автори: Fixlut & GPT
-- Версія: 1.0 Pro Stable

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
    gpu.setBackground(0x000000)
    gpu.setForeground(0x00FF00)
    local w, h = gpu.getResolution()
    gpu.fill(1, 1, w, h, " ")
    gpu.set(2, 2, "FixBIOS vPro Bootloader")
    gpu.set(2, 3, "© Fixlut Studios 2025")
    gpu.set(2, 5, "Performing POST...")
  end)
end

local function log(msg)
  if gpu then gpu.set(2, 7, tostring(msg)) end
end

local fs = findProxy("filesystem")
if not fs then
  log("No filesystem found. Insert disk and reboot.")
  return
end

local function loadFile(path)
  local handle = fs.open(path, "r")
  if not handle then return nil end
  local data = ""
  repeat
    local chunk = fs.read(handle, math.huge)
    if chunk then data = data .. chunk end
  until not chunk
  fs.close(handle)
  return data
end

local function runFile(path)
  log("Loading: " .. path)
  local data = loadFile(path)
  if not data then log("Missing: " .. path) return false end
  local ok, chunk = load(data, "=" .. path)
  if not ok then log("Error: " .. tostring(chunk)) return false end
  local succ, err = pcall(chunk)
  if not succ then
    log("Runtime error: " .. tostring(err))
    os.sleep(2)
    return false
  end
  return true
end

-- Boot sequence
local bootPaths = {
  "/boot/init.lua",
  "/init.lua",
  "/boot/fallback.lua",
  "/boot/recovery.lua"
}

local booted = false
for _, path in ipairs(bootPaths) do
  if fs.exists(path) then
    if runFile(path) then
      booted = true
      break
    end
  end
end

if not booted then
  log("FixOS not found. Opening BIOS shell...")
  local function biosShell()
    if gpu then gpu.set(2, 9, "BIOS Shell> ") end
    local kb = findProxy("keyboard")
    if not kb then log("No keyboard connected!") return end
    local buf = ""
    while true do
      local ev, addr, ch, code, p4, p5 = computer.pullSignal()
      if ev == "key_down" and ch == 13 then
        if buf == "reboot" then computer.shutdown(true) end
        runFile(buf)
        buf = ""
        gpu.set(2, 9, "BIOS Shell> ")
      elseif ev == "key_down" and ch > 31 and ch < 127 then
        buf = buf .. string.char(ch)
        gpu.set(15 + #buf, 9, string.char(ch))
      end
    end
  end
  biosShell()
end
