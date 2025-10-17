-- FixOS 2000 Installer (Stable GUI version)
local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local term = require("term")
local event = require("event")

local gpu = component.list("gpu")() and component.proxy(component.list("gpu")()) or nil
local inetAddr = component.list("internet")() or nil
local internet = inetAddr and component.proxy(inetAddr) or nil

local BASE_URL = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main"
local FILES = {
  "system/gui/win2000ui.lua",
  "system/desktop.lua",
  "system/startmenu.lua",
  "system/settings.lua",
  "boot/init.lua",
  "bin/ls.lua",
  "bin/echo.lua",
  "bin/cls.lua",
  "bin/edit.lua",
  "bin/calc.lua"
}

-- === GRAPHICS INIT ===
if gpu then
  local scr = component.list("screen")()
  if scr then pcall(gpu.bind, scr, true) end
  pcall(gpu.setResolution, 80, 25)
end

local function cls(bg)
  if gpu then
    gpu.setBackground(bg or 0x000080)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1,1,80,25," ")
  end
end

local function center(y, text, color)
  if gpu then
    local x = math.floor(40 - (#text / 2))
    gpu.setForeground(color or 0xFFFFFF)
    gpu.set(x, y, text)
  end
end

-- === EULA SCREEN ===
local function eula()
  cls()
  center(3, "FixOS 2000 License Agreement", 0xFFFF00)
  center(5, "By installing FixOS, you agree to:")
  center(7, "- Respect retro tech and blue screens :)")
  center(8, "- Use it with style and common sense.")
  center(10, "Press [A] to Accept or [R] to Reject")
  center(12, " ")

  while true do
    local _, _, _, _, _, key = event.pull("key_down")
    -- A key
    if key == 30 then
      cls()
      center(10, "EULA accepted. Proceeding with installation...", 0x00FF00)
      os.sleep(1.5)
      return true
    end
    -- R key
    if key == 19 then
      cls()
      center(10, "Installation cancelled.", 0xFF0000)
      os.sleep(2)
      return false
    end
  end
end

-- === INTERNET DOWNLOAD ===
local function download(url)
  if not internet then return nil, "no internet" end
  local ok, handle = pcall(internet.request, url)
  if not ok or not handle then return nil, "connection failed" end
  local data = ""
  for chunk in handle do
    data = data .. (chunk or "")
  end
  if handle.close then pcall(handle.close, handle) end
  return data
end

-- === PROGRESS BAR ===
local function progress(i, total, msg)
  local percent = math.floor((i / total) * 100)
  gpu.setBackground(0x000080)
  gpu.fill(5, 10, 70, 1, " ")
  gpu.set(5, 10, msg)
  local barW = math.floor(percent / 2)
  gpu.setBackground(0x00FF00)
  gpu.fill(5, 12, barW, 1, " ")
  gpu.setBackground(0x000080)
  center(14, "Progress: " .. percent .. "%")
end

-- === MAIN INSTALLER ===
local function install()
  cls()
  center(3, "FixOS 2000 Setup", 0xFFFF00)
  center(5, "Installing system files...")

  local total = #FILES
  for i, path in ipairs(FILES) do
    progress(i, total, "Copying " .. path)
    local url = BASE_URL .. "/" .. path
    local data, err = download(url)
    if not data then
      data = "-- Missing or failed: " .. tostring(err)
    end
    local full = "/" .. path
    local dir = full:match("(.+)/[^/]+$")
    if dir and not fs.exists(dir) then fs.makeDirectory(dir) end
    local f = io.open(full, "w")
    f:write(data)
    f:close()
    os.sleep(0.25)
  end

  cls(0x000080)
  center(12, "Installation complete!", 0x00FF00)
  center(14, "Press any key to reboot FixOS 2000.")
  event.pull("key_down")
  computer.shutdown(true)
end

-- === DISABLE CONSOLE ECHO ===
term.clear()
term.setCursorBlink(false)
term.write = function() end
term.read = function() return "" end

-- === RUN INSTALLER ===
if eula() then install() end
