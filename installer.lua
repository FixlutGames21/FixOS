--[[ 
  FixBIOS v5 (Stable)
  Created by Fixlut & GPT
  🧠 Bootloader for FixOS
]]

local component = component
local computer = computer

-- 🧩 Safe component list
local function find(type)
  for addr, name in component.list() do
    if name == type then return component.proxy(addr) end
  end
end

local gpu = find("gpu")
local screen = find("screen")
local fs = find("filesystem")

-- 🖥️ GPU Setup
if gpu and screen then
  pcall(function()
    gpu.bind(screen)
    gpu.setResolution(50, 16)
    gpu.setBackground(0x000000)
    gpu.setForeground(0x00FF00)
    gpu.fill(1, 1, 50, 16, " ")
    gpu.set(15, 3, "FixOS BIOS v5 Booting...")
  end)
end

local function printLine(y, text)
  if gpu then gpu.set(2, y, text) end
end

-- 💡 POST
local function post()
  local line = 5
  printLine(line, "Running POST checks...")
  os.sleep(0.2)
  local ok = true

  if fs then
    printLine(line + 1, "[ OK ] Filesystem detected")
  else
    printLine(line + 1, "[FAIL] No filesystem detected")
    ok = false
  end

  if gpu then
    printLine(line + 2, "[ OK ] GPU connected")
  else
    printLine(line + 2, "[WARN] No GPU found")
  end

  printLine(line + 3, "----------------------------------")
  os.sleep(0.6)
  return ok
end

-- 🚀 Boot sequence
local function boot()
  if not fs then
    printLine(10, "Insert disk with FixOS and reboot.")
    return
  end

  local paths = {
    "/boot/init.lua",
    "/init.lua",
    "/os/init.lua"
  }

  for _, path in ipairs(paths) do
    if fs.exists(path) then
      printLine(10, "Booting: " .. path)
      local f = fs.open(path, "r")
      local data = ""
      repeat
        local chunk = fs.read(f, math.huge)
        data = data .. (chunk or "")
      until not chunk
      fs.close(f)
      local ok, result = load(data, "=" .. path)
      if not ok then
        printLine(12, "Boot error:")
        printLine(13, tostring(result))
        return
      end
      printLine(12, "Launching FixOS...")
      os.sleep(0.5)
      pcall(result)
      return
    end
  end

  printLine(10, "⚠️ No bootable FixOS found!")
end

-- ⚙️ Main
if post() then
  boot()
else
  printLine(10, "BIOS halted. Insert system disk.")
end
