-- installer.lua
-- FixOS Installer — Stable Menu Edition
-- Author: Fixlut & GPT-5 Thinking mini
-- Note: не поспішай; цей скрипт нічого не робить без твоїх підтверджень

-- safe require / globals fallback
local ok, component = pcall(require, "component"); if not ok then component = _G.component end
local ok2, computer = pcall(require, "computer"); if not ok2 then computer = _G.computer end
local ok3, fs = pcall(require, "filesystem"); if not ok3 then fs = _G.filesystem end
local ok4, term = pcall(require, "term"); if not ok4 then term = _G.term end
local unicode = _G.unicode

-- config
local GITHUB_BASES = {
  "https://raw.githubusercontent.com/FixlutGames21/FixOS/main/",
  "https://raw.githubusercontent.com/FixlutGames21/FixOS/master/"
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
local CONFIG_PATH = "/etc/fixos.conf" -- simple personalization store

-- ui helpers: try resolution 100x50 but fail safely
local function getFirstProxy(kind)
  for addr in component.list(kind) do return component.proxy(addr) end
  return nil
end
local gpu = getFirstProxy("gpu")
local screenAddr = component.list("screen")()

local function safeSetResolution(w,h)
  if not gpu or not screenAddr then return end
  pcall(function()
    gpu.bind(screenAddr, true)
    local ok, cw, ch = pcall(gpu.getResolution, gpu)
    if ok and cw and ch then pcall(gpu.setResolution, gpu, w, h) end
  end)
end

local function clearScreen()
  if not gpu then return end
  local ok, w, h = pcall(gpu.getResolution, gpu)
  if ok and w and h then
    pcall(gpu.setBackground, gpu, 0x000000)
    pcall(gpu.fill, gpu, 1, 1, w, h, " ")
  end
end

local function centerPrint(y, text, color)
  if not gpu then
    term.write(text.."\n"); return
  end
  local ok, w = pcall(gpu.getResolution, gpu)
  if not ok or not w then return end
  local len = unicode and unicode.len(text) or #text
  local x = math.floor(w/2 - len/2)
  if color then pcall(gpu.setForeground, gpu, color) end
  pcall(gpu.set, gpu, x, y, text)
end

-- robust remote fetch: handles iterator OR table returns, checks HTML
local function fetch_remote(path)
  if not (component and component.isAvailable and component.isAvailable("internet")) then
    return nil, "no internet card"
  end
  for _, base in ipairs(GITHUB_BASES) do
    local url = base .. path
    local ok, handle_or_err = pcall(component.internet.request, component.internet, url)
    if ok and handle_or_err then
      local data = ""
      if type(handle_or_err) == "table" then
        for _, chunk in pairs(handle_or_err) do if type(chunk) == "string" then data = data .. chunk end end
      else
        for chunk in handle_or_err do data = data .. (chunk or "") end
        if handle_or_err.close then pcall(handle_or_err.close, handle_or_err) end
      end
      if type(data) == "string" and not data:match("^%s*<") then
        return data, nil
      end
    end
  end
  return nil, "failed to fetch from all bases"
end

local function fetch_local(path)
  local localPath = "/disk/FixOS/" .. path
  if fs.exists(localPath) then
    local f = io.open(localPath, "r")
    if not f then return nil, "cannot open local" end
    local content = f:read("*a"); f:close(); return content, nil
  end
  return nil, "no local fallback"
end

local function fetch_with_fallback(path)
  local d, e = fetch_remote(path)
  if d then return d end
  local d2, e2 = fetch_local(path)
  if d2 then return d2 end
  return nil, (e or "") .. "; " .. (e2 or "")
end

local function write_file(path, content)
  if type(content) ~= "string" then return false, "content must be string" end
  local dir = path:match("(.+)/[^/]+$")
  if dir and not fs.exists(dir) then fs.makeDirectory(dir) end
  local f, ferr = io.open(path, "w")
  if not f then return false, ferr end
  f:write(content); f:close()
  return true
end

-- EEPROM safe write (backup + helper)
local function safe_write_eeprom(eepromProxy, content, label)
  if not eepromProxy then return false, "no eeprom" end
  -- backup
  local ok, cur = pcall(function() return eepromProxy.get() end)
  if ok and cur and cur ~= "" then
    local bf = io.open("/eeprom_backup.lua", "w")
    if bf then bf:write(cur); bf:close() end
  end
  if type(content) ~= "string" then return false, "bad bios content" end
  if content:match("^%s*<") then return false, "bios looks like HTML" end
  local succ, serr = pcall(function() eepromProxy.set(content) end)
  if not succ then return false, serr end
  pcall(eepromProxy.setLabel, label or "FixBIOS")
  -- create restore helper
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

-- read/write personalization config
local function load_config()
  if not fs.exists(CONFIG_PATH) then return { theme = "green", label = "FixOS" } end
  local f = io.open(CONFIG_PATH,"r")
  if not f then return { theme = "green", label = "FixOS" } end
  local s = f:read("*a"); f:close()
  local ok, t = pcall(function() return load("return " .. s)() end)
  if ok and type(t)=="table" then return t end
  return { theme = "green", label = "FixOS" }
end
local function save_config(conf)
  local s = "return " .. tostring(conf and conf._dump and conf._dump or nil)
  -- safer: write Lua table manually
  local out = "return {\n"
  out = out .. ("  theme = %q,\n"):format(conf.theme or "green")
  out = out .. ("  label = %q,\n"):format(conf.label or "FixOS")
  out = out .. "}\n"
  local f = io.open(CONFIG_PATH,"w")
  if not f then return false end
  f:write(out); f:close()
  return true
end

-- helper to display menu and read choice
local function menu_loop()
  safeSetResolution(100,50)
  clearScreen()
  centerPrint(3, "FixOS Installer — Menu", 0x00FF00)
  centerPrint(6, "1) Пуск", 0xAAAAAA)
  centerPrint(8, "2) Налаштування", 0xAAAAAA)
  centerPrint(10, "3) Вихід (без змін)", 0xAAAAAA)
  term.write("\nВведи номер та натисни Enter: ")
  local choice = (io.read() or ""):gsub("%s+","")
  return choice
end

-- START action: install or boot
local function action_start()
  clearScreen()
  centerPrint(3, "Start — Вибір дії", 0x00FF00)
  centerPrint(6, "1) Спробувати бутнути (якщо встановлено)", 0xAAAAAA)
  centerPrint(8, "2) Інсталювати FixOS на цей диск (форматує)", 0xAAAAAA)
  centerPrint(10, "3) Повернутись", 0xAAAAAA)
  term.write("\nВибір: "); local c = io.read() or ""
  if c == "1" then
    clearScreen(); centerPrint(6, "Спроба завантажити локально...", 0x00FF00)
    os.sleep(0.6)
    -- attempt local boot by running /boot/init.lua if exists
    if fs.exists("/boot/init.lua") then
      local ok, err = pcall(dofile, "/boot/init.lua")
      if not ok then
        clearScreen(); centerPrint(8, "Boot error: "..tostring(err), 0xFF5555)
        term.write("\nНатисни Enter щоб повернутись..."); io.read()
      end
    else
      clearScreen(); centerPrint(8, "FixOS не знайдено на диску.", 0xFF0000)
      term.write("\nНатисни Enter щоб повернутись..."); io.read()
    end
    return
  elseif c == "2" then
    -- install flow
    clearScreen(); centerPrint(4, "INSTALL: Підтверди ERASE AND INSTALL", 0xFFAA00)
    term.write("\nЩоб продовжити — введи EXACTLY: ERASE AND INSTALL\n> ")
    local conf = io.read()
    if conf ~= "ERASE AND INSTALL" then centerPrint(10,"Відмінено.",0xAAAAAA); term.write("\nEnter..."); io.read(); return end

    -- pick target filesystem proxy: first boot address, else first fs
    local target = nil
    local bootAddr = computer.getBootAddress()
    if bootAddr then
      for addr in component.list("filesystem") do if addr == bootAddr then target = component.proxy(addr); break end end
    end
    if not target then for addr in component.list("filesystem") do target = component.proxy(addr); break end end
    if not target then centerPrint(10, "No filesystem device found. Insert disk.",0xFF0000); term.write("\nEnter..."); io.read(); return end

    -- format target via proxy
    local function proxy_remove_recursive(proxy, path)
      local list = proxy.list(path)
      for name,_ in pairs(list) do
        local sub = path .. (path:sub(-1)=='/' and "" or "/") .. name
        if proxy.isDirectory(sub) then proxy_remove_recursive(proxy, sub); pcall(proxy.remove, proxy, sub)
        else pcall(proxy.remove, proxy, sub) end
      end
    end
    centerPrint(12, "Форматування диска...", 0xAAAAAA)
    local rootList = target.list("/")
    for name,_ in pairs(rootList) do
      local p = "/" .. name
      if target.isDirectory(p) then proxy_remove_recursive(target, p); pcall(target.remove, p)
      else pcall(target.remove, p) end
    end

    -- install files (fetch or local)
    centerPrint(14, "Завантаження файлів...", 0x00FF00)
    for i, rel in ipairs(FILES) do
      centerPrint(16, ("-> %s"):format(rel), 0xAAAAAA)
      local content, ferr = fetch_with_fallback(rel)
      if not content then
        centerPrint(18, ("Не вдалося отримати %s : %s"):format(rel, tostring(ferr)), 0xFF5555)
        term.write("\nEnter..."); io.read(); return
      end
      local okw, werr = write_file("/" .. rel, content)
      if not okw then centerPrint(18, ("Помилка запису /%s : %s"):format(rel, tostring(werr)), 0xFF5555); term.write("\nEnter..."); io.read(); return end
      os.sleep(0.05)
    end

    -- autorun
    write_file("/autorun.lua", [[
term.clear()
local s = loadfile("/boot/shell.lua") or loadfile("/boot/init.lua")
if s then pcall(s) end
]])
    centerPrint(20, "Файли встановлені.", 0x00FF00)

    -- write BIOS to EEPROM if present
    local eepromProxy = getFirstProxy("eeprom")
    if eepromProxy then
      centerPrint(22, "EEPROM знайдено. Писати BIOS? (type WRITE BIOS)", 0xAAAAAA)
      term.write("\n> "); local wb = io.read()
      if wb == "WRITE BIOS" then
        -- fetch BIOS or use embedded
        local biosContent, berr = fetch_with_fallback("FixBIOS.lua")
        if not biosContent then biosContent = nil end
        if not biosContent then biosContent = fetch_local and (function() local f=io.open("/FixBIOS.lua","r") if f then local s=f:read("*a"); f:close(); return s end return nil end)() end
        if not biosContent then biosContent = [[-- embedded minimal BIOS
local component = component
local computer = computer
for addr in component.list("filesystem") do local p = component.proxy(addr) if p.exists("/boot/init.lua") then local h = p.open("/boot/init.lua","r") local s = "" repeat local c = p.read(h,65536) s=s..(c or "") until not c p.close(h) local f = load(s,"=init") if f then pcall(f) end return end end
]] end
        local okb, berr = safe_write_eeprom(eepromProxy, biosContent, "FixBIOS")
        if not okb then centerPrint(24, "EEPROM write failed: "..tostring(berr), 0xFF0000); term.write("\nEnter..."); io.read(); return end
        centerPrint(24, "EEPROM прошито.", 0x00FF00)
      else
        centerPrint(22, "Пропущено запис EEPROM.", 0xAAAAAA)
      end
    else
      centerPrint(22, "EEPROM не знайдено; пропускаємо.", 0xFF5555)
    end

    term.write("\nПерезавантажити зараз? (y/n): ")
    if (io.read() or ""):lower():sub(1,1) == "y" then computer.shutdown(true) end
    return
  else
    return -- back
  end
end

-- SETTINGS: personalization and updates
local function action_settings()
  while true do
    clearScreen()
    centerPrint(3, "Налаштування", 0x00FF00)
    centerPrint(6, "1) Персоналізація (тема, мітка BIOS)", 0xAAAAAA)
    centerPrint(8, "2) Оновлення (перевірити / завантажити з GitHub)", 0xAAAAAA)
    centerPrint(10, "3) Повернутись", 0xAAAAAA)
    term.write("\nВибір: "); local c = io.read() or ""
    if c == "1" then
      local conf = load_config()
      clearScreen(); centerPrint(4, "Персоналізація", 0x00FF00)
      centerPrint(6, ("Поточна тема: %s"):format(conf.theme or "green"), 0xAAAAAA)
      centerPrint(8, ("Поточна мітка BIOS: %s"):format(conf.label or "FixOS"), 0xAAAAAA)
      term.write("\nНова тема (green/blue/red) або Enter щоб пропустити: ")
      local nt = (io.read() or ""):gsub("%s+","")
      if nt ~= "" then conf.theme = nt end
      term.write("Нова мітка BIOS або Enter щоб пропустити: ")
      local nl = (io.read() or ""):gsub("^%s+",""):gsub("%s+$","")
      if nl ~= "" then conf.label = nl end
      save_config(conf)
      centerPrint(14, "Збережено.", 0x00FF00); term.write("\nEnter..."); io.read()
    elseif c == "2" then
      clearScreen(); centerPrint(4, "Оновлення", 0x00FF00)
      centerPrint(6, "Перевірка доступності GitHub...", 0xAAAAAA)
      local ok, err = fetch_remote("boot/init.lua")
      if ok then
        centerPrint(8, "Оновлення доступне. Завантажити та встановити? (y/n)", 0xAAAAAA)
        term.write("\n> "); local yn = io.read() or ""
        if yn:lower():sub(1,1) == "y" then
          -- download all FILES and overwrite
          for _, rel in ipairs(FILES) do
            centerPrint(10, ("Оновлення: %s"):format(rel), 0xAAAAAA)
            local content, ferr = fetch_with_fallback(rel)
            if not content then centerPrint(12, ("Не вдалося оновити %s: %s"):format(rel, tostring(ferr)), 0xFF5555); term.write("\nEnter..."); io.read(); break end
            write_file("/"..rel, content)
            os.sleep(0.05)
          end
          centerPrint(16, "Оновлення завершено.", 0x00FF00); term.write("\nEnter..."); io.read()
        end
      else
        centerPrint(8, "Оновлень не знайдено або немає інтернету: "..tostring(err), 0xFF5555)
        term.write("\nEnter..."); io.read()
      end
    else
      return
    end
  end
end

-- main loop
while true do
  local choice = menu_loop()
  if choice == "1" then action_start()
  elseif choice == "2" then action_settings()
  elseif choice == "3" then clearScreen(); centerPrint(6, "Вихід. Нічого не змінено.", 0xAAAAAA); break
  else clearScreen(); centerPrint(12, "Невірний вибір.", 0xFF5555); os.sleep(0.6) end
end

-- goodbye
centerPrint(22, "Done. Keep it classic. — Fixlut", 0x00FF00)
