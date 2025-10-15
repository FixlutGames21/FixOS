-- installer_graphical_github_only.lua
-- FixOS Graphical Installer (GitHub-only downloads, stable)
-- Author: Fixlut & GPT-5 Thinking mini
-- Place as /home/installer.lua and run: dofile("/home/installer.lua")

-- SAFE REQUIRES
local ok, component = pcall(require, "component"); if not ok then component = _G.component end
local ok2, computer = pcall(require, "computer"); if not ok2 then computer = _G.computer end
local ok3, filesystem = pcall(require, "filesystem"); if not ok3 then filesystem = _G.filesystem end
local ok4, term = pcall(require, "term"); if not ok4 then term = _G.term end
local unicode = _G.unicode

-- CONFIG
local GITHUB_BASE = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/"
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
local RES_W, RES_H = 100, 50

-- COLORS
local BG = 0x0F0F10
local FG = 0xE6E6E6
local ACCENT = 0x00C080
local WARN = 0xFF5555
local LOG_COLOR = 0xAAAAAA

-- HELPERS: proxies
local function getFirstProxy(kind)
  for addr in component.list(kind) do return component.proxy(addr) end
  return nil
end

local gpu = getFirstProxy("gpu")
local screenAddr = component.list("screen")() -- may be nil
local eepromProxy = getFirstProxy("eeprom")
local internetProxy = getFirstProxy("internet") -- proxy or nil

-- SAFE RESOLUTION SET
local function trySetResolution(w,h)
  if not gpu or not screenAddr then return false end
  pcall(function()
    gpu.bind(screenAddr, true)
    local ok, cw, ch = pcall(gpu.getResolution, gpu)
    if ok and cw and ch then pcall(gpu.setResolution, gpu, w, h) end
  end)
  return true
end

-- DRAW HELPERS
local function clearScreen()
  if not gpu then return end
  pcall(function()
    local ok, w, h = pcall(gpu.getResolution, gpu)
    if ok and w and h then
      gpu.setBackground(BG)
      gpu.fill(1,1,w,h," ")
    end
  end)
end

local function textWidth(s)
  if unicode and unicode.len then return unicode.len(s) end
  return #s
end

local function drawText(x,y,color,text)
  if not gpu then return end
  pcall(function()
    gpu.setForeground(color or FG)
    gpu.set(x,y,tostring(text))
  end)
end

local function drawCentered(y, color, text)
  if not gpu then
    term.write(text .. "\n"); return
  end
  pcall(function()
    local ok, w = pcall(gpu.getResolution, gpu)
    if not ok or not w then return end
    local len = textWidth(text)
    local x = math.floor(w/2 - len/2)
    drawText(x,y,color,text)
  end)
end

local function drawBox(x,y,w,h, bg, fg, title)
  if not gpu then return end
  pcall(function()
    gpu.setBackground(bg or BG)
    gpu.fill(x,y,w,h," ")
    if title then
      gpu.setForeground(fg or FG)
      local tx = x + 2
      gpu.set(tx, y, " " .. title .. " ")
    end
  end)
end

-- PROGRESS BAR
local function drawProgress(pct)
  local ok, w = pcall(gpu.getResolution, gpu)
  if not ok or not w then return end
  local barw = math.min(60, w - 30)
  local x = math.floor(w/2 - barw/2)
  local y = math.floor(RES_H/2 + 8)
  local filled = math.floor(barw * math.max(0, math.min(1,pct)))
  pcall(function()
    gpu.setBackground(0x222222); gpu.fill(x, y, barw, 1, " ")
    if filled > 0 then gpu.setBackground(ACCENT); gpu.fill(x, y, filled, 1, " ") end
    gpu.setBackground(BG)
    gpu.setForeground(FG)
    local label = ("%.0f%%"):format(pct*100)
    local lx = math.floor(w/2 - textWidth(label)/2)
    gpu.set(lx, y, label)
  end)
end

-- LOG area
local LOG_LINES = {}
local function logPush(line)
  table.insert(LOG_LINES, line)
  if #LOG_LINES > 12 then table.remove(LOG_LINES,1) end
end
local function drawLog()
  local ok, w, h = pcall(gpu.getResolution, gpu)
  if not ok or not w or not h then return end
  local lx = 4; local ly = h - 14; local lw = w - 8; local lh = 12
  pcall(function()
    gpu.setBackground(0x101010); gpu.fill(lx, ly, lw, lh, " ")
    gpu.setForeground(LOG_COLOR)
    for i = 1, #LOG_LINES do
      local line = LOG_LINES[i]
      gpu.set(lx+1, ly + i - 1, tostring(line))
    end
  end)
end

-- BUTTONS
local BUTTONS = {}
local function addButton(id, x,y,w,h, label, cb)
  BUTTONS[id] = {x=x,y=y,w=w,h=h,label=label,cb=cb}
  pcall(function()
    gpu.setBackground(0x202020); gpu.fill(x,y,w,h," ")
    gpu.setForeground(FG)
    local lx = x + math.floor((w - textWidth(label))/2)
    gpu.set(lx, y + math.floor(h/2), label)
  end)
end
local function redrawButtons()
  for id, b in pairs(BUTTONS) do
    pcall(function()
      gpu.setBackground(0x202020); gpu.fill(b.x,b.y,b.w,b.h," ")
      gpu.setForeground(FG)
      local lx = b.x + math.floor((b.w - textWidth(b.label))/2)
      gpu.set(lx, b.y + math.floor(b.h/2), b.label)
    end)
  end
end
local function hitTest(x,y)
  for id,b in pairs(BUTTONS) do
    if x >= b.x and x <= b.x + b.w -1 and y >= b.y and y <= b.y + b.h -1 then
      return id,b
    end
  end
  return nil,nil
end

-- WRITE FILE safely
local function write_file(dest, content)
  if type(content) ~= "string" then return false, "content not string" end
  local dir = dest:match("(.+)/[^/]+$")
  if dir and not filesystem.exists(dir) then filesystem.makeDirectory(dir) end
  local f, ferr = io.open(dest, "w")
  if not f then return false, ferr end
  f:write(content); f:close()
  return true
end

-- SAFE EEPROM WRITE (backup + helper)
local function safe_write_eeprom(eepromProxy, content, label)
  if not eepromProxy then return false, "no eeprom" end
  local ok, cur = pcall(function() return eepromProxy.get() end)
  if ok and cur and cur ~= "" then
    local bf = io.open("/eeprom_backup.lua","w")
    if bf then bf:write(cur); bf:close() end
  end
  if type(content) ~= "string" then return false, "bad bios content" end
  if content:match("^%s*<") then return false, "bios looks like HTML" end
  local succ, serr = pcall(function() eepromProxy.set(content) end)
  if not succ then return false, serr end
  pcall(eepromProxy.setLabel, label or "FixBIOS")
  local rf = io.open("/eeprom_restore.lua","w")
  rf:write([[
local component = require("component")
local eaddr = component.list("eeprom")()
if not eaddr then print("no eeprom"); return end
local e = component.proxy(eaddr)
local f = io.open("/eeprom_backup.lua","r")
if not f then print("no backup"); return end
local d = f:read("*a"); f:close()
pcall(e.set, d); print("EEPROM restored")
]])
  rf:close()
  return true
end

-- GITHUB-ONLY FETCH
local function fetch_from_github(path)
  if not internetProxy then return nil, "no internet card" end
  local url = GITHUB_BASE .. path
  logPush("GET " .. url)
  -- request: use proxy.request with bound proxy
  local ok_req, handle_or_err = pcall(internetProxy.request, internetProxy, url)
  if not ok_req or not handle_or_err then
    return nil, "request failed: " .. tostring(handle_or_err)
  end
  local data = ""
  -- handle can be iterator or table
  if type(handle_or_err) == "table" then
    for _, chunk in pairs(handle_or_err) do
      if type(chunk) == "string" then data = data .. chunk end
    end
  else
    for chunk in handle_or_err do
      if chunk then data = data .. chunk end
    end
    if handle_or_err.close then pcall(handle_or_err.close, handle_or_err) end
  end
  if data == "" then return nil, "empty response" end
  if data:match("^%s*<") then return nil, "html response (404 or github page)" end
  return data, nil
end

-- INSTALL FLOW (GitHub-only)
local function install_flow(onProgress)
  logPush("Start GitHub-only install")
  local total = #FILES
  for i, rel in ipairs(FILES) do
    logPush("Downloading: " .. rel)
    local content, err = fetch_from_github(rel)
    if not content then
      logPush("Failed to download " .. rel .. " -> " .. tostring(err))
      return false, ("Failed to download %s: %s"):format(rel, tostring(err))
    end
    local dest = "/" .. rel
    local ok, werr = write_file(dest, content)
    if not ok then
      logPush("Failed to write " .. dest .. " -> " .. tostring(werr))
      return false, ("Failed to write %s: %s"):format(dest, tostring(werr))
    end
    if onProgress then onProgress(i/total) end
    os.sleep(0.06)
  end
  logPush("Install_flow finished successfully.")
  return true, nil
end

-- UI CALLBACKS
local installInProgress = false

local function onInstallClick()
  if installInProgress then return end
  installInProgress = true
  logPush("User clicked Install")
  drawCentered(RES_H/2 + 2, WARN, "Type EXACT: ERASE AND INSTALL in console to proceed")
  term.write("\n> ")
  local conf = io.read()
  if conf ~= "ERASE AND INSTALL" then
    logPush("User canceled ERASE AND INSTALL")
    installInProgress = false
    return
  end

  -- choose target fs proxy
  local target = nil
  local bootAddr = computer.getBootAddress()
  if bootAddr then
    for addr in component.list("filesystem") do if addr == bootAddr then target = component.proxy(addr); break end end
  end
  if not target then
    for addr in component.list("filesystem") do target = component.proxy(addr); break end
  end
  if not target then
    logPush("No filesystem proxy available")
    drawCentered(RES_H/2 + 4, WARN, "No filesystem device found. Insert disk.")
    installInProgress = false
    return
  end

  -- format target
  logPush("Formatting target filesystem")
  do
    local function proxy_remove_recursive(proxy, path)
      local list = proxy.list(path)
      for name,_ in pairs(list) do
        local sub = path .. (path:sub(-1) == "/" and "" or "/") .. name
        if proxy.isDirectory(sub) then proxy_remove_recursive(proxy, sub); pcall(proxy.remove, proxy, sub)
        else pcall(proxy.remove, proxy, sub) end
      end
    end
    local rootList = target.list("/")
    for name,_ in pairs(rootList) do
      local p = "/" .. name
      if target.isDirectory(p) then proxy_remove_recursive(target, p); pcall(target.remove, p)
      else pcall(target.remove, p) end
    end
  end

  -- download & write from GitHub
  local ok, err = install_flow(function(pct) drawProgress(pct); drawLog() end)
  if not ok then
    logPush("Installation failed: " .. tostring(err))
    drawCentered(RES_H/2 + 4, WARN, "Install failed: " .. tostring(err))
    installInProgress = false
    return
  end

  -- write autorun
  write_file("/autorun.lua", [[
term.clear()
local s = loadfile("/boot/shell.lua") or loadfile("/boot/init.lua")
if s then pcall(s) end
]])
  logPush("Autorun written.")

  -- EEPROM write option
  if eepromProxy then
    term.write("\nType EXACT: WRITE BIOS to write FixBIOS to EEPROM (or Enter to skip): ")
    local wb = io.read()
    if wb == "WRITE BIOS" then
      local bios, berr = fetch_from_github("FixBIOS.lua")
      if not bios then
        logPush("Failed to fetch FixBIOS.lua: " .. tostring(berr))
        drawCentered(RES_H/2 + 6, WARN, "Failed to fetch FixBIOS.lua: " .. tostring(berr))
      else
        local okw, werr = safe_write_eeprom(eepromProxy, bios, "FixBIOS")
        if okw then logPush("EEPROM flashed.") drawCentered(RES_H/2 + 6, ACCENT, "EEPROM flashed.") else logPush("EEPROM write failed: "..tostring(werr)) drawCentered(RES_H/2 + 6, WARN, "EEPROM write failed: "..tostring(werr)) end
      end
    else
      logPush("User skipped EEPROM write")
    end
  else
    logPush("No EEPROM present; skipped BIOS write")
  end

  drawCentered(RES_H/2 + 8, ACCENT, "Install complete. Reboot? (y/n) in console")
  term.write("\n> ")
  if (io.read() or ""):lower():sub(1,1) == "y" then computer.shutdown(true) end

  installInProgress = false
end

-- SETTINGS (small)
local function onSettingsClick()
  clearScreen()
  drawCentered(6, ACCENT, "Settings")
  drawCentered(10, FG, "1) Personalization (theme/label)")
  drawCentered(12, FG, "2) Check for updates on GitHub")
  drawCentered(14, FG, "3) Back")
  term.write("\nChoice: ")
  local c = io.read() or ""
  if c == "1" then
    clearScreen(); drawCentered(6, ACCENT, "Personalization")
    drawCentered(10, FG, "Theme (green/blue/red) or Enter to skip: ")
    term.write("> "); local theme = (io.read() or ""):gsub("%s+","")
    drawCentered(14, FG, "Label for BIOS (Enter to skip): "); term.write("> "); local label = (io.read() or ""):gsub("^%s+",""):gsub("%s+$","")
    local out = "return {\n  theme = " .. ("%q"):format(theme ~= "" and theme or "green") .. ",\n  label = " .. ("%q"):format(label ~= "" and label or "FixOS") .. ",\n}\n"
    write_file("/etc/fixos.conf", out)
    logPush("Personalization updated")
    drawCentered(20, ACCENT, "Saved. Press Enter..."); io.read()
  elseif c == "2" then
    clearScreen(); drawCentered(6, ACCENT, "Checking for updates...")
    local data, err = fetch_from_github("boot/init.lua")
    if data then
      drawCentered(10, ACCENT, "Update available on GitHub.")
      drawCentered(12, FG, "Download and install? (y/n)"); term.write("> "); local yn = io.read() or ""
      if yn:lower():sub(1,1) == "y" then
        local ok2, err2 = install_flow(function(pct) drawProgress(pct); drawLog() end)
        if ok2 then logPush("Update completed"); drawCentered(16, ACCENT, "Update done. Press Enter..."); io.read() end
      end
    else
      drawCentered(10, WARN, "No update or no internet: " .. tostring(err))
      drawCentered(12, FG, "Press Enter..."); io.read()
    end
  else
    return
  end
end

-- BUILD UI
local function buildUI()
  trySetResolution(RES_W, RES_H)
  clearScreen()
  drawBox(4,2, RES_W-8, 8, 0x101010, FG, " FixOS Installer ")
  drawCentered(4, ACCENT, "FixOS — Graphical Installer (GitHub-only)")
  drawCentered(5, FG, "Stable · Safe · 100x50 (if supported)")
  drawBox(6,12, RES_W-20, 18, 0x141414, FG, " Actions ")
  local panelX = 8; local panelY = 14
  addButton("start", panelX + 2, panelY+2, 20, 3, "Пуск / Boot", function() end)
  addButton("install", panelX + 24, panelY+2, 28, 3, "Install FixOS", onInstallClick)
  addButton("settings", panelX + 54, panelY+2, 20, 3, "Налаштування", onSettingsClick)
  drawProgress(0)
  drawLog()
  redrawButtons()
  drawCentered(RES_H-4, LOG_COLOR, "Logs below — follow console prompts for confirmations")
end

-- MAIN EVENT LOOP
local function mainLoop()
  buildUI()
  drawLog()
  while true do
    drawLog()
    local ev = { computer.pullSignal(0.5) } -- safe usage with timeout
    if ev[1] == "touch" or ev[1] == "mouseup" then
      local x = ev[3]; local y = ev[4]
      local id,b = hitTest(x,y)
      if id and b and b.cb then
        pcall(function()
          gpu.setBackground(0x404040); gpu.fill(b.x,b.y,b.w,b.h," ")
          gpu.setForeground(0xFFFFFF)
          gpu.set(b.x + math.floor((b.w - textWidth(b.label))/2), b.y + math.floor(b.h/2), b.label)
          os.sleep(0.12)
          redrawButtons(); drawLog()
        end)
        pcall(function() b.cb() end)
        buildUI()
      end
    elseif ev[1] == "key_down" then
      local key = ev[4]
      if key == 28 then
        local b = BUTTONS["install"]
        if b and b.cb then pcall(b.cb) end
      elseif key == 57 then
        local b = BUTTONS["settings"]
        if b and b.cb then pcall(b.cb) end
      end
    end
    if installInProgress then drawProgress(0.5) end
  end
end

-- START
clearScreen()
buildUI()
drawCentered(RES_H-8, FG, "Enter = Install, Space = Settings. Use mouse/touch.")
drawLog()
mainLoop()
