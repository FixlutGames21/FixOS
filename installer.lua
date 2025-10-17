-- FixOS 2000 Installer
local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local term = require("term")

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

if gpu then
  local scr = component.list("screen")()
  if scr then pcall(gpu.bind, scr, true) end
  pcall(gpu.setResolution, 80, 25)
end

local function cls(bg)
  pcall(gpu.setBackground, bg or 0x000080)
  pcall(gpu.fill, 1,1,80,25," ")
end

local function center(y, text, color)
  local x = math.floor(40 - #text/2)
  pcall(gpu.setForeground, color or 0xFFFFFF)
  pcall(gpu.set, x, y, text)
end

local function eula()
  cls()
  center(3, "FixOS 2000 License Agreement", 0xFFFF00)
  center(5, "By installing FixOS, you agree to:")
  center(7, "- Respect retro tech")
  center(8, "- Not blame Fixlut if GPU smokes")
  center(9, "- Enjoy the vibes responsibly")
  center(11, "Press [A] to Accept or [R] to Reject")

  while true do
    local _, _, _, _, _, key = term.pull("key_down")
    if key == 30 then return true end -- A
    if key == 19 then
      cls()
      center(10, "Installation cancelled. Bye.")
      os.sleep(2)
      return false
    end
  end
end

local function download(url)
  if not internet then return nil, "no internet" end
  local ok, handle = pcall(internet.request, url)
  if not ok or not handle then return nil, "fail" end
  local data = ""
  for chunk in handle do data = data .. (chunk or "") end
  if handle.close then pcall(handle.close, handle) end
  return data
end

local function progress(i, total, msg)
  local percent = math.floor((i/total)*100)
  pcall(gpu.setBackground, 0x000080)
  pcall(gpu.fill, 5, 10, 70, 1, " ")
  pcall(gpu.set, 5, 10, msg)
  local barW = math.floor(percent / 2)
  pcall(gpu.setBackground, 0x00FF00)
  pcall(gpu.fill, 5, 12, barW, 1, " ")
  pcall(gpu.setBackground, 0x000080)
  center(14, "Progress: " .. percent .. "%")
end

local function install()
  cls()
  center(3, "FixOS 2000 Setup")
  center(5, "Installing...")

  local total = #FILES
  local done = 0
  for _, path in ipairs(FILES) do
    done = done + 1
    progress(done, total, "Copying " .. path)
    local url = BASE_URL .. "/" .. path
    local data, err = download(url)
    if not data then
      data = "-- Missing file: " .. tostring(err)
    end
    local full = "/" .. path
    local dir = full:match("(.+)/[^/]+$")
    if dir and not fs.exists(dir) then fs.makeDirectory(dir) end
    local f = io.open(full, "w")
    f:write(data)
    f:close()
    os.sleep(0.3)
  end

  center(17, "Installation complete!")
  center(19, "Press any key to reboot...")
  term.read()
  computer.shutdown(true)
end

if eula() then install() end
