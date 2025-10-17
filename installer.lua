-- installer.lua
-- FixOS 2000 Installer (GUI buttons, choose target disk, GitHub-only, auto-reboot)
-- Put as /home/installer.lua and run: dofile("/home/installer.lua")

local component = require("component")
local computer  = require("computer")
local filesystem = require("filesystem")
local term = require("term")
local unicode = _G.unicode

-- safer event pulling
local pull = computer.pullSignal

-- CONFIG
local BASE_RAW = "https://raw.githubusercontent.com/FixlutGames21/FixOS/main"
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

-- GRAPHICS PROXIES
local gpuAddr = component.list("gpu")()
local screenAddr = component.list("screen")()
local gpu = gpuAddr and component.proxy(gpuAddr) or nil
local internetAddr = component.list("internet")()
local internet = internetAddr and component.proxy(internetAddr) or nil
local tapeAddr = component.list("tape_drive")()
local tape = tapeAddr and component.proxy(tapeAddr) or nil
local eepromAddr = component.list("eeprom")()
local eeprom = eepromAddr and component.proxy(eepromAddr) or nil

-- UTILS
local function txtlen(s) if unicode and unicode.len then return unicode.len(s) else return #s end end
local function safeBind()
  if not gpu or not screenAddr then return false end
  pcall(gpu.bind, gpu, screenAddr, true)
  return true
end

local function resolution()
  if not gpu then return 80,25 end
  local ok,w,h = pcall(gpu.getResolution, gpu)
  if ok and w and h then return w,h end
  return 80,25
end

local function setResolution(w,h)
  if not gpu then return false end
  pcall(function() safeBind(); pcall(gpu.setResolution, gpu, w, h) end)
  return true
end

local function clearScreen(bg)
  if not gpu then
    term.clear(); term.setCursor(1,1); return
  end
  pcall(function()
    local w,h = resolution()
    gpu.setBackground(bg or 0x000080)
    gpu.fill(1,1,w,h," ")
  end)
end

local function drawText(x,y,color,text)
  if not gpu then
    term.setCursor(math.max(1,x), math.max(1,y)); io.write(text); return end
  end
  pcall(function()
    gpu.setForeground(color or 0xFFFFFF)
    gpu.set(x,y,tostring(text))
  end)
end

local function centerY(row, color, text)
  local w,_ = resolution()
  local x = math.floor(w/2 - txtlen(text)/2)
  drawText(x, row, color, text)
end

-- fetch from github robust (iterator or table)
local function fetch_from_github(path)
  if not internet then return nil, "no internet card" end
  local url = BASE_RAW .. "/" .. path
  local ok, handle = pcall(internet.request, internet, url)
  if not ok or not handle then return nil, ("request failed: %s"):format(tostring(handle)) end
  local data = ""
  if type(handle) == "table" then
    for _, chunk in pairs(handle) do if type(chunk) == "string" then data = data .. chunk end end
  else
    for chunk in handle do if chunk then data = data .. chunk end end
    if handle.close then pcall(handle.close, handle) end
  end
  if data == "" then return nil, "empty response" end
  if data:match("^%s*<") then return nil, "HTML/404 received" end
  return data
end

local function write_file(path, content)
  if type(content) ~= "string" then return false, "content not string" end
  local dir = path:match("(.+)/[^/]+$")
  if dir and not filesystem.exists(dir) then filesystem.makeDirectory(dir) end
  local f, err = io.open(path, "w")
  if not f then return false, err end
  f:write(content); f:close()
  return true
end

-- draw simple button & hit detection
local BUTTONS = {}
local function drawButton(id, x,y,w,h, bg, fg, label)
  if gpu then
    pcall(function()
      gpu.setBackground(bg); gpu.fill(x,y,w,h," ")
      local lx = x + math.floor((w - txtlen(label))/2)
      gpu.setForeground(fg)
      gpu.set(lx, y + math.floor(h/2), label)
    end)
  else
    -- text fallback: print approximate
    print(("[%s] %s"):format(id, label))
  end
  BUTTONS[id] = {x=x,y=y,w=w,h=h}
end

local function hitButton(x,y)
  for id, b in pairs(BUTTONS) do
    if x >= b.x and x <= b.x + b.w - 1 and y >= b.y and y <= b.y + b.h - 1 then
      return id
    end
  end
  return nil
end

-- DRAW base window (Win2000-ish)
local function draw_header(title)
  local w,_ = resolution()
  local titleBg = 0x000080
  local titleFg = 0xFFFFFF
  pcall(function()
    gpu.setBackground(titleBg)
    gpu.fill(1,1,w,3," ")
    gpu.setForeground(titleFg)
    gpu.set(2,2, " Microsoft (R) FixOS Setup - " .. tostring(title))
    -- restore bg
    gpu.setBackground(0x000000)
  end)
end

-- EULA GUI (buttons Accept / Reject)
local function eula_gui()
  clearScreen(0x000080)
  draw_header("License Agreement")
  centerY(6, 0xFFFFFF, "End User License Agreement - FixOS 2000 Edition")
  centerY(8, 0xFFFFFF, "By installing this software you agree to enjoy retro vibes responsibly.")
  centerY(10, 0xFFFFFF, "Click Accept to continue or Reject to cancel installation.")
  -- Buttons
  BUTTONS = {}
  drawButton("accept", 24, 14, 14, 3, 0x00AA00, 0xFFFFFF, "Accept")
  drawButton("reject", 46, 14, 14, 3, 0xAA0000, 0xFFFFFF, "Reject")
  drawButton("help", 36, 18, 8, 2, 0xCCCCCC, 0x000000, "View EULA")

  while true do
    local ev = { pull(0.5) } -- safe timeout for responsiveness
    local evname = ev[1]
    if evname == "touch" or evname == "mouse_click" then
      local x,y = ev[3], ev[4]
      local id = hitButton(x,y)
      if id == "accept" then
        clearScreen(0x000080)
        centerY(12, 0x00FF00, "EULA accepted. Preparing installer...")
        os.sleep(1.0)
        return true
      elseif id == "reject" then
        clearScreen(0x000080)
        centerY(12, 0xFF4444, "Installation cancelled by user.")
        os.sleep(1.2)
        return false
      elseif id == "help" then
        -- show more EULA text (paged)
        clearScreen(0x000080); draw_header("License - Full")
        local y = 5
        local lines = {
          "FixOS 2000 License - Short:",
          "1) Don't blame the author for melty GPUs.",
          "2) Use for learning, tinkering, retro fun.",
          "3) Respect creators and their code.",
        }
        for i=1,#lines do
          centerY(y+i, 0xE0E0E0, lines[i])
        end
        centerY(20, 0xFFFFFF, "Click anywhere to return.")
        -- wait click or key
        while true do
          local e = { pull(0.5) }
          if e[1] == "touch" or e[1] == "mouse_click" or e[1] == "key_down" then break end
        end
        -- redraw EULA
        clearScreen(0x000080)
        draw_header("License Agreement")
        centerY(6, 0xFFFFFF, "End User License Agreement - FixOS 2000 Edition")
        centerY(8, 0xFFFFFF, "By installing this software you agree to enjoy retro vibes responsibly.")
        centerY(10, 0xFFFFFF, "Click Accept to continue or Reject to cancel installation.")
        drawButton("accept", 24, 14, 14, 3, 0x00AA00, 0xFFFFFF, "Accept")
        drawButton("reject", 46, 14, 14, 3, 0xAA0000, 0xFFFFFF, "Reject")
        drawButton("help", 36, 18, 8, 2, 0xCCCCCC, 0x000000, "View EULA")
      end
    elseif evname == "key_down" then
      local key = ev[6] or ev[4]
      -- fallback: Enter = accept, Esc = reject
      if key == 28 then return true end
      if key == 1 then return false end
    end
  end
end

-- list candidate filesystems for installation
local function list_filesystems()
  local list = {}
  for addr in component.list("filesystem") do
    local ok, proxy = pcall(component.proxy, addr)
    if ok and proxy then
      local info = { address = addr }
      local ok2, label = pcall(proxy.getLabel, proxy)
      if ok2 and label and label ~= "" then info.label = label else info.label = addr end
      local ok3, readOnly = pcall(proxy.isReadOnly, proxy)
      info.readOnly = not not readOnly
      local ok4, total = pcall(proxy.spaceTotal, proxy)
      info.spaceTotal = ok4 and total or 0
      table.insert(list, info)
    end
  end
  -- sort: prefer larger disks (heuristic)
  table.sort(list, function(a,b) return (a.spaceTotal or 0) > (b.spaceTotal or 0) end)
  return list
end

local function humanSize(n)
  if not n or n <= 0 then return "??" end
  if n > 1024*1024 then return string.format("%.1fGB", n/1024/1024) end
  if n > 1024 then return string.format("%.1fMB", n/1024) end
  return tostring(n) .. "B"
end

-- disk selection UI
local function choose_disk_gui()
  clearScreen(0x000080)
  draw_header("Choose Installation Disk")
  centerY(5, 0xFFFFFF, "Select a target disk for installation")
  local list = list_filesystems()
  if #list == 0 then
    centerY(8, 0xFFAAAA, "No filesystem devices found. Attach a drive and retry.")
    centerY(10, 0xFFFFFF, "Click anywhere to exit.")
    pull() -- wait
    return nil
  end
  -- draw entries as buttons
  BUTTONS = {}
  local startY = 8
  for i,info in ipairs(list) do
    local label = string.format("%d) %s %s", i, info.label, info.readOnly and "(RO)" or "")
    drawButton("disk"..i, 10, startY + (i-1)*3, 60, 2, info.readOnly and 0x777777 or 0xDDDDDD, 0x000000, label)
  end
  centerY(startY + #list*3 + 1, 0xFFFFFF, "Click the disk to install to. Esc to cancel.")
  while true do
    local ev = { pull(0.5) }
    if ev[1] == "touch" or ev[1] == "mouse_click" then
      local x,y = ev[3], ev[4]
      local id = hitButton(x,y)
      if id and id:match("^disk(%d+)$") then
        local idx = tonumber(id:match("%d+"))
        local sel = list[idx]
        if sel and sel.readOnly then
          centerY( startY + #list*3 + 3, 0xFF4444, "Selected disk is read-only. Choose another." )
          os.sleep(1.2)
        else
          return sel.address
        end
      end
    elseif ev[1] == "key_down" then
      local k = ev[6] or ev[4]
      if k == 1 then return nil end -- Esc
      if k == 28 then
        -- Enter: pick first writable if exists
        for _,iinfo in ipairs(list) do if not iinfo.readOnly then return iinfo.address end end
      end
    end
  end
end

-- Format/clear disk (via proxy) - careful destructive
local function format_target(addr)
  local ok, proxy = pcall(component.proxy, addr)
  if not ok or not proxy then return false, "proxy miss" end
  -- remove everything under /
  local function rm_recursive(p, path)
    for name,_ in pairs(p.list(path)) do
      local sub = path .. (path:sub(-1)=="/" and "" or "/") .. name
      if p.isDirectory(sub) then
        rm_recursive(p, sub)
        pcall(p.remove, sub)
      else
        pcall(p.remove, sub)
      end
    end
  end
  -- delete contents of root
  local ok2, rootList = pcall(proxy.list, "/")
  if not ok2 then return false, "cannot list root" end
  for name,_ in pairs(rootList) do
    local p = "/" .. name
    if proxy.isDirectory(p) then
      rm_recursive(proxy, p)
      pcall(proxy.remove, p)
    else
      pcall(proxy.remove, p)
    end
  end
  -- ensure /boot exists
  pcall(proxy.makeDirectory, "/boot")
  return true
end

-- install_flow: download files and write into target proxy if possible; otherwise write to path "/"
local function install_to_target(addr)
  local useProxy = false
  local proxy
  if addr then
    local ok, p = pcall(component.proxy, addr)
    if ok and p then proxy = p; useProxy = true end
  end

  local total = #FILES
  for i, rel in ipairs(FILES) do
    centerY(9, 0xFFFFFF, ("Downloading %d/%d: %s"):format(i, total, rel))
    local data, err = fetch_from_github(rel)
    if not data then
      centerY(11, 0xFFAAAA, "Failed to download: " .. tostring(err))
      return false, ("download failed: %s"):format(tostring(err))
    end
    if useProxy then
      -- write via proxy.open/write/close if available
      local ok, handle = pcall(proxy.open, proxy, "/" .. rel, "w")
      if not ok or not handle then
        -- try fallback: write to temporary file then proxy.open raw write isn't available -> fall back to writing to local fs
        local fallbackPath = "/tmp_fixos_" .. tostring(os.time()) .. "_" .. i
        local f = io.open(fallbackPath, "w")
        if not f then return false, "cannot create temp file" end
        f:write(data); f:close()
        -- attempt to copy using proxy (if proxy provides write from file, usually not)
        -- simplest: if cannot open proxy handle, signal failure
        return false, "proxy.open failed for writing"
      else
        local okw, r = pcall(proxy.write, proxy, handle, data)
        pcall(proxy.close, proxy, handle)
        if not okw then return false, ("proxy.write failed: %s"):format(tostring(r)) end
      end
    else
      -- write to local FS
      local full = "/" .. rel
      local okw, werr = write_file(full, data)
      if not okw then return false, ("local write failed: %s"):format(tostring(werr)) end
    end
    -- update progress bar
    local pct = i / total
    local barW = math.floor(pct * 60)
    if gpu then
      pcall(gpu.setBackground, 0xFFFFFF)
      pcall(gpu.fill, 10, 13, barW, 1, " ")
      pcall(gpu.setBackground, 0x000080)
      centerY(15, 0xFFFFFF, ("%.0f%%"):format(pct * 100))
    else
      print(("Progress: %.0f%%"):format(pct*100))
    end
    os.sleep(0.15)
  end
  return true
end

-- helper: write this installer to tape (if tape present) - convenience
local function write_installer_to_tape(installerPath)
  if not tape then return false, "no tape drive" end
  local f = io.open(installerPath, "rb")
  if not f then return false, "installer file not found" end
  local data = f:read("*a"); f:close()
  -- try to write entire content; tape.write may not exist, use proxy.open if available
  local ok, handle = pcall(tape.open, tape, "/installer.lua", "w")
  if ok and handle then
    local okw, err = pcall(tape.write, tape, handle, data)
    pcall(tape.close, tape, handle)
    if not okw then return false, tostring(err) end
    return true
  else
    -- fallback: if tape has write method directly (rare)
    if pcall(tape.write) then
      local succ, serr = pcall(tape.write, data)
      if succ then return true else return false, tostring(serr) end
    end
    return false, "cannot open tape for write"
  end
end

-- main flow
local function main()
  safeBind()
  setResolution(100, 36)
  clearScreen(0x000080)
  draw_header("Welcome")

  centerY(5, 0xFFFFFF, "Welcome to FixOS 2000 Installer")
  centerY(7, 0xFFFFFF, "Classic Setup UI - click buttons with mouse or use keyboard fallback")

  -- initial buttons
  BUTTONS = {}
  drawButton("start_install", 28, 18, 18, 3, 0xCCCCCC, 0x000000, "Install")
  drawButton("write_tape", 48, 18, 18, 3, 0x8888FF, 0x000000, "Write to Tape")
  drawButton("quit", 38, 22, 12, 3, 0xAA0000, 0xFFFFFF, "Cancel")

  while true do
    local ev = { pull(0.5) }
    if ev[1] == "touch" or ev[1] == "mouse_click" then
      local x,y = ev[3], ev[4]
      local id = hitButton(x,y)
      if id == "start_install" then
        -- run EULA
        local ok = eula_gui()
        if not ok then return end
        -- choose disk
        local target = choose_disk_gui()
        if not target then
          clearScreen(0x000080); centerY(12, 0xFFFFFF, "No target selected. Returning.") os.sleep(1); main() return end
        end
        -- format target (confirm)
        clearScreen(0x000080)
        draw_header("Prepare Disk")
        centerY(8, 0xFFFFFF, "Formatting target will erase all data on it.")
        drawButton("confirm_erase", 30, 14, 14, 3, 0xAA0000, 0xFFFFFF, "Erase & Continue")
        drawButton("abort_erase", 46, 14, 14, 3, 0xCCCCCC, 0x000000, "Cancel")
        while true do
          local e = { pull(0.5) }
          if e[1] == "touch" or e[1] == "mouse_click" then
            local xx, yy = e[3], e[4]; local bid = hitButton(xx,yy)
            if bid == "confirm_erase" then
              -- format
              local okf, ferr = format_target(target)
              if not okf then
                clearScreen(0x000080); centerY(12, 0xFF4444, "Format failed: "..tostring(ferr)); os.sleep(2); return end
              end
              -- install
              clearScreen(0x000080)
              draw_header("Installing")
              centerY(8, 0xFFFFFF, "Copying files to target...")
              local oki, ierr = install_to_target(target)
              if not oki then
                clearScreen(0x000080); centerY(10, 0xFF4444, "Install failed: "..tostring(ierr)); os.sleep(2); return end
              end
              clearScreen(0x000080); centerY(12, 0x00FF00, "Installation successful! Rebooting..."); os.sleep(1.2)
              computer.shutdown(true)
              return
            elseif bid == "abort_erase" then
              clearScreen(0x000080); centerY(12, 0xFFFFFF, "Aborted. Returning to start."); os.sleep(1.0); main(); return
            end
          elseif e[1] == "key_down" then
            local k = e[6] or e[4]
            if k == 1 then clearScreen(0x000080); centerY(12, 0xFFFFFF, "Aborted."); os.sleep(1); main(); return end
          end
        end

      elseif id == "write_tape" then
        -- write installer to tape (if tape present)
        clearScreen(0x000080); draw_header("Write to Tape")
        centerY(8, 0xFFFFFF, "Attempting to write installer to tape...")
        local ok, err = write_installer_to_tape("/home/installer.lua")
        if ok then centerY(12, 0x00FF00, "Installer written to tape.") else centerY(12, 0xFF4444, "Write failed: "..tostring(err)) end
        os.sleep(1.6)
        main(); return

      elseif id == "quit" then
        clearScreen(0x000080); centerY(12, 0xFFFFFF, "Installer cancelled."); os.sleep(1); return
      end
    elseif ev[1] == "key_down" then
      local k = ev[6] or ev[4]
      if k == 28 then
        -- Enter => emulate click Install
        -- recursive call to handle
        local ok = eula_gui()
        if not ok then return end
        local target = choose_disk_gui()
        if not target then clearScreen(0x000080); centerY(12, 0xFFFFFF, "No target selected."); os.sleep(1); return end
        local okf = format_target(target)
        if not okf then clearScreen(0x000080); centerY(12, 0xFF4444, "Format failed"); os.sleep(1); return end
        local oki = install_to_target(target)
        if not oki then clearScreen(0x000080); centerY(12, 0xFF4444, "Install failed"); os.sleep(1); return end
        clearScreen(0x000080); centerY(12, 0x00FF00, "Installed. Rebooting..."); os.sleep(1); computer.shutdown(true); return
      elseif k == 1 then
        clearScreen(0x000080); centerY(12, 0xFFFFFF, "Cancelled."); os.sleep(1); return
      end
    end
  end
end

-- RUN
pcall(function()
  main()
end)
