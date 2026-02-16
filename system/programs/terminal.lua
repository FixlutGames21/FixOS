-- ==============================================
-- FixOS 3.1.0 - Terminal (WINDOWS 10 STYLE)
-- ==============================================

local terminal = {}

function terminal.init(win)
  win.lines = {
    "FixOS Terminal v3.1.0",
    "Type 'help' for commands",
    ""
  }
  win.currentLine = ""
  win.cursorPos = 1
  win.scrollY = 0
  win.maxLines = 100
  win.prompt = "C:\\> "
  win.history = {}
  win.historyIndex = 0
  
  table.insert(win.lines, win.prompt)
end

local function executeCommand(win, cmd)
  cmd = cmd:match("^%s*(.-)%s*$")
  
  if cmd == "" then
    return
  end
  
  table.insert(win.history, cmd)
  win.historyIndex = 0
  
  if cmd == "help" then
    table.insert(win.lines, "Available commands:")
    table.insert(win.lines, "  help     - Show this help")
    table.insert(win.lines, "  clear    - Clear screen")
    table.insert(win.lines, "  echo     - Print text")
    table.insert(win.lines, "  uptime   - Show uptime")
    table.insert(win.lines, "  mem      - Memory info")
    table.insert(win.lines, "  beep     - Make sound")
    table.insert(win.lines, "  ls       - List files")
    table.insert(win.lines, "  pwd      - Current directory")
    table.insert(win.lines, "  ver      - Show version")
    table.insert(win.lines, "  time     - Show time")
    
  elseif cmd == "clear" or cmd == "cls" then
    win.lines = {}
    
  elseif cmd:match("^echo%s+") then
    local text = cmd:sub(6)
    table.insert(win.lines, text)
    
  elseif cmd == "uptime" then
    local uptime = math.floor(computer.uptime())
    local hours = math.floor(uptime / 3600)
    local minutes = math.floor((uptime % 3600) / 60)
    local seconds = uptime % 60
    table.insert(win.lines, string.format("Uptime: %02d:%02d:%02d", hours, minutes, seconds))
    
  elseif cmd == "mem" then
    local total = computer.totalMemory()
    local free = computer.freeMemory()
    local used = total - free
    local pct = math.floor((used / total) * 100)
    table.insert(win.lines, string.format("Memory: %d KB / %d KB (%d%% used)", 
      math.floor(used / 1024), math.floor(total / 1024), pct))
    
  elseif cmd == "beep" then
    computer.beep(1000, 0.2)
    table.insert(win.lines, "BEEP!")
    
  elseif cmd == "ls" or cmd == "dir" then
    local fs = component.proxy(computer.getBootAddress())
    table.insert(win.lines, "Directory of C:\\")
    table.insert(win.lines, "")
    
    local count = 0
    for file in fs.list("/") do
      local isDir = fs.isDirectory("/" .. file)
      local prefix = isDir and "<DIR>    " or "         "
      table.insert(win.lines, prefix .. file)
      count = count + 1
      if count > 15 then
        table.insert(win.lines, "... and more")
        break
      end
    end
    
  elseif cmd == "pwd" then
    table.insert(win.lines, "C:\\")
    
  elseif cmd == "ver" or cmd == "version" then
    table.insert(win.lines, "FixOS version 3.1.0 - Windows 10 Edition")
    
  elseif cmd == "time" then
    table.insert(win.lines, "Current time: " .. os.date("%H:%M:%S"))
    
  else
    table.insert(win.lines, "'" .. cmd .. "' is not recognized as a command.")
    table.insert(win.lines, "Type 'help' for available commands.")
  end
  
  while #win.lines > win.maxLines do
    table.remove(win.lines, 1)
  end
end

function terminal.draw(win, gpu, x, y, w, h)
  -- Dark theme (like Windows Terminal)
  gpu.setBackground(0x0C0C0C)
  gpu.setForeground(0xCCCCCC)
  gpu.fill(x, y, w, h, " ")
  
  local visibleLines = h
  local startLine = math.max(1, #win.lines - visibleLines + 1 - win.scrollY)
  
  for i = 0, visibleLines - 1 do
    local lineIdx = startLine + i
    if win.lines[lineIdx] then
      local line = win.lines[lineIdx]
      
      if #line > w then
        line = line:sub(1, w)
      end
      
      -- Color prompt differently
      if line:match("^C:\\>") then
        gpu.setForeground(0x0078D7)
      else
        gpu.setForeground(0xCCCCCC)
      end
      
      gpu.set(x, y + i, line)
    end
  end
  
  -- Current input
  if #win.lines > 0 and startLine + visibleLines - 1 == #win.lines then
    local inputY = y + visibleLines - 1
    gpu.setForeground(0x0078D7)
    gpu.set(x, inputY, win.prompt)
    
    gpu.setForeground(0xCCCCCC)
    gpu.set(x + #win.prompt, inputY, win.currentLine)
    
    -- Cursor (blinking block)
    local cursorX = x + #win.prompt + win.cursorPos - 1
    if cursorX < x + w then
      gpu.setBackground(0xCCCCCC)
      gpu.setForeground(0x0C0C0C)
      local curChar = win.currentLine:sub(win.cursorPos, win.cursorPos)
      gpu.set(cursorX, inputY, curChar ~= "" and curChar or " ")
    end
  end
end

function terminal.key(win, char, code)
  if code == 28 then
    table.insert(win.lines, #win.lines, win.prompt .. win.currentLine)
    
    executeCommand(win, win.currentLine)
    
    win.currentLine = ""
    win.cursorPos = 1
    
    table.insert(win.lines, win.prompt)
    
    win.scrollY = 0
    
    return true
    
  elseif code == 14 then
    if win.cursorPos > 1 then
      win.currentLine = win.currentLine:sub(1, win.cursorPos - 2) .. 
                        win.currentLine:sub(win.cursorPos)
      win.cursorPos = win.cursorPos - 1
      return true
    end
    
  elseif code == 211 then
    if win.cursorPos <= #win.currentLine then
      win.currentLine = win.currentLine:sub(1, win.cursorPos - 1) .. 
                        win.currentLine:sub(win.cursorPos + 1)
      return true
    end
    
  elseif code == 203 then
    if win.cursorPos > 1 then
      win.cursorPos = win.cursorPos - 1
      return true
    end
    
  elseif code == 205 then
    if win.cursorPos <= #win.currentLine then
      win.cursorPos = win.cursorPos + 1
      return true
    end
    
  elseif code == 199 then
    win.cursorPos = 1
    return true
    
  elseif code == 207 then
    win.cursorPos = #win.currentLine + 1
    return true
    
  elseif code == 200 then
    if #win.history > 0 then
      win.historyIndex = math.min(win.historyIndex + 1, #win.history)
      win.currentLine = win.history[#win.history - win.historyIndex + 1] or ""
      win.cursorPos = #win.currentLine + 1
      return true
    end
    
  elseif code == 208 then
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
