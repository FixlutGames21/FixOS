-- ==============================================
-- FixOS 3.0 - Terminal
-- system/programs/terminal.lua
-- ==============================================

local terminal = {}

function terminal.init(win)
  win.lines = {"FixOS 3.0 Terminal", "Type 'help' for commands", ""}
  win.currentLine = ""
  win.cursorPos = 1
  win.scrollY = 0
  win.maxLines = 100
  win.prompt = "fixos> "
  win.history = {}
  win.historyIndex = 0
  
  -- Додаємо prompt
  table.insert(win.lines, win.prompt)
end

-- Виконання команд
local function executeCommand(win, cmd)
  cmd = cmd:match("^%s*(.-)%s*$") -- Trim
  
  if cmd == "" then
    return
  end
  
  -- Зберігаємо в історію
  table.insert(win.history, cmd)
  win.historyIndex = 0
  
  -- Команди
  if cmd == "help" then
    table.insert(win.lines, "Available commands:")
    table.insert(win.lines, "  help       - Show this help")
    table.insert(win.lines, "  clear      - Clear screen")
    table.insert(win.lines, "  echo TEXT  - Print text")
    table.insert(win.lines, "  uptime     - Show system uptime")
    table.insert(win.lines, "  mem        - Show memory info")
    table.insert(win.lines, "  beep       - Make a beep sound")
    table.insert(win.lines, "  ls         - List files")
    table.insert(win.lines, "  pwd        - Print working directory")
    table.insert(win.lines, "  ver        - Show FixOS version")
    
  elseif cmd == "clear" then
    win.lines = {}
    
  elseif cmd:match("^echo%s+") then
    local text = cmd:sub(6)
    table.insert(win.lines, text)
    
  elseif cmd == "uptime" then
    local uptime = math.floor(computer.uptime())
    local hours = math.floor(uptime / 3600)
    local minutes = math.floor((uptime % 3600) / 60)
    local seconds = uptime % 60
    table.insert(win.lines, string.format("Uptime: %dh %dm %ds", hours, minutes, seconds))
    
  elseif cmd == "mem" then
    local total = computer.totalMemory()
    local free = computer.freeMemory()
    local used = total - free
    local pct = math.floor((used / total) * 100)
    table.insert(win.lines, string.format("Memory: %d KB / %d KB (%d%%)", 
      math.floor(used / 1024), math.floor(total / 1024), pct))
    
  elseif cmd == "beep" then
    computer.beep(1000, 0.2)
    table.insert(win.lines, "*BEEP*")
    
  elseif cmd == "ls" then
    local fs = component.proxy(computer.getBootAddress())
    table.insert(win.lines, "Files in /:")
    
    local count = 0
    for file in fs.list("/") do
      table.insert(win.lines, "  " .. file)
      count = count + 1
      if count > 20 then
        table.insert(win.lines, "  ...")
        break
      end
    end
    
  elseif cmd == "pwd" then
    table.insert(win.lines, "/")
    
  elseif cmd == "ver" or cmd == "version" then
    local fs = component.proxy(computer.getBootAddress())
    local version = "3.0.0"
    if fs.exists("/version.txt") then
      local h = fs.open("/version.txt", "r")
      if h then
        local v = fs.read(h, math.huge)
        fs.close(h)
        if v then version = v:match("[%d%.]+") or version end
      end
    end
    table.insert(win.lines, "FixOS version " .. version)
    
  else
    table.insert(win.lines, "Unknown command: " .. cmd)
    table.insert(win.lines, "Type 'help' for available commands")
  end
  
  -- Обмеження кількості рядків
  while #win.lines > win.maxLines do
    table.remove(win.lines, 1)
  end
end

function terminal.draw(win, gpu, x, y, w, h)
  -- Чорний фон
  gpu.setBackground(0x000000)
  gpu.setForeground(0x00FF00)
  gpu.fill(x, y, w, h, " ")
  
  local visibleLines = h
  local startLine = math.max(1, #win.lines - visibleLines + 1 - win.scrollY)
  
  for i = 0, visibleLines - 1 do
    local lineIdx = startLine + i
    if win.lines[lineIdx] then
      local line = win.lines[lineIdx]
      
      -- Обрізаємо довгі рядки
      if #line > w then
        line = line:sub(1, w)
      end
      
      gpu.set(x, y + i, line)
    end
  end
  
  -- Поточний ввід (останній рядок)
  if #win.lines > 0 and startLine + visibleLines - 1 == #win.lines then
    local inputY = y + visibleLines - 1
    gpu.set(x, inputY, win.prompt .. win.currentLine)
    
    -- Курсор
    local cursorX = x + #win.prompt + win.cursorPos - 1
    if cursorX < x + w then
      gpu.set(cursorX, inputY, "█")
    end
  end
end

function terminal.key(win, char, code)
  if code == 28 then -- Enter
    -- Додаємо команду до історії виводу
    table.insert(win.lines, #win.lines, win.prompt .. win.currentLine)
    
    -- Виконуємо команду
    executeCommand(win, win.currentLine)
    
    -- Очищаємо поточний рядок
    win.currentLine = ""
    win.cursorPos = 1
    
    -- Додаємо новий prompt
    table.insert(win.lines, win.prompt)
    
    -- Автоскрол вниз
    win.scrollY = 0
    
    return true
    
  elseif code == 14 then -- Backspace
    if win.cursorPos > 1 then
      win.currentLine = win.currentLine:sub(1, win.cursorPos - 2) .. 
                        win.currentLine:sub(win.cursorPos)
      win.cursorPos = win.cursorPos - 1
      return true
    end
    
  elseif code == 211 then -- Delete
    if win.cursorPos <= #win.currentLine then
      win.currentLine = win.currentLine:sub(1, win.cursorPos - 1) .. 
                        win.currentLine:sub(win.cursorPos + 1)
      return true
    end
    
  elseif code == 203 then -- Left arrow
    if win.cursorPos > 1 then
      win.cursorPos = win.cursorPos - 1
      return true
    end
    
  elseif code == 205 then -- Right arrow
    if win.cursorPos <= #win.currentLine then
      win.cursorPos = win.cursorPos + 1
      return true
    end
    
  elseif code == 199 then -- Home
    win.cursorPos = 1
    return true
    
  elseif code == 207 then -- End
    win.cursorPos = #win.currentLine + 1
    return true
    
  elseif code == 200 then -- Up arrow - історія
    if #win.history > 0 then
      win.historyIndex = math.min(win.historyIndex + 1, #win.history)
      win.currentLine = win.history[#win.history - win.historyIndex + 1] or ""
      win.cursorPos = #win.currentLine + 1
      return true
    end
    
  elseif code == 208 then -- Down arrow - історія
    if win.historyIndex > 0 then
      win.historyIndex = math.max(win.historyIndex - 1, 0)
      if win.historyIndex == 0 then
        win.currentLine = ""
      else
        win.currentLine = win.history[#win.history - win.historyIndex + 1] or ""
      end
      win.cursorPos = #win.currentLine + 1
      return true
    end
    
  elseif char and char >= 32 and char <= 255 then
    -- Друкований символ
    win.currentLine = win.currentLine:sub(1, win.cursorPos - 1) .. 
                      string.char(char) .. 
                      win.currentLine:sub(win.cursorPos)
    win.cursorPos = win.cursorPos + 1
    return true
  end
  
  return false
end

function terminal.scroll(win, direction)
  if direction > 0 then
    win.scrollY = math.max(0, win.scrollY - 3)
  else
    win.scrollY = math.min(#win.lines, win.scrollY + 3)
  end
  return true
end

return terminal
