-- FixBIOS vPro2 (stable for FixOS)
-- by Fixlut & GPT
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
local eeprom = findProxy("eeprom")

local function drawTextCentered(y, color, text)
  if not gpu then return end
  local w, h = gpu.getResolution()
  local x = math.floor(w/2 - #text/2)
  gpu.setForeground(color)
  gpu.set(x, y, text)
end

local function clearScreen()
  if gpu then
    local w, h = gpu.getResolution()
    gpu.setBackground(0x000000)
    gpu.fill(1, 1, w, h, " ")
  end
end

local function showStatus(msg, color)
  clearScreen()
  drawTextCentered(2, 0x00FF00, "FixBIOS vPro2")
  drawTextCentered(4, color or 0xAAAAAA, msg)
end

local function tryBoot(proxy)
  if not proxy then return false end
  local bootPaths = {"/boot/init.lua", "/boot/kernel.lua", "/boot/shell.lua", "/init.lua"}
  for _, path in ipairs(bootPaths) do
    if proxy.exists(path) then
      showStatus("Booting " .. path .. "...", 0x00FF00)
      local handle = proxy.open(path, "r")
      if not handle then return false end
      local data = ""
      repeat
        local chunk = proxy.read(handle, math.huge)
        data = data .. (chunk or "")
      until not chunk
      proxy.close(handle)
      local ok, err = load(data, "="..path)
      if not ok then
        showStatus("Error loading " .. path .. ":\n" .. tostring(err), 0xFF5555)
        return false
      end
      local ok2, err2 = pcall(ok)
      if not ok2 then
        showStatus("Runtime error: " .. tostring(err2), 0xFF5555)
        return false
      end
      return true
    end
  end
  return false
end

local function bootSystem()
  local addr = eeprom and eeprom.getData() or nil
  local bootProxy = addr and component.proxy(addr)
  if bootProxy and tryBoot(bootProxy) then return end

  -- fallback: try all
  for address in component.list("filesystem") do
    local proxy = component.proxy(address)
    if tryBoot(proxy) then
      if eeprom then eeprom.setData(address) end
      return
    end
  end

  showStatus("No bootable FixOS found.\nInsert disk & reboot.", 0xFF0000)
end

-- init GPU
if gpu and screen then
  pcall(function()
    gpu.bind(screen.address)
    gpu.setResolution(50, 16)
  end)
end

showStatus("FixBIOS initializing...", 0xAAAAAA)
bootSystem()
