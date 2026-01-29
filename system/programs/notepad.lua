local notepad = {}

function notepad.init(win)
  win.lines = {""}
  win.cursorLine = 1
  win.cursorCol = 1
  win.scrollY = 0
  win.filename = "untitled.txt"
end

function notepad.draw(win, gpu, x, y, w, h)
  -- Фон
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  gpu.fill(x, y, w, h, " ")
  
  -- Статус бар
  gpu.setBackground(0xC0C0C0)
  gpu.fill(x, y + h - 1, w, 1, " ")
  gpu.set(x + 1, y + h - 1, "File: " .. win.filename)
  gpu.set(x + w - 15, y + h - 1, string.format("Ln %d, Col %d", win.cursorLine, win.cursorCol))
  
  -- Текст
  gpu.setBackground(0xFFFFFF)
  local visibleLines = h - 2
  for i = 1, visibleLines do
    local lineIdx = win.scrollY + i
    if win.lines[lineIdx] then
      local line = win.lines[lineIdx]
      if #line > w then line = line:sub(1, w) end
      gpu.set(x, y + i - 1, line)
    end
  end
  
  -- Курсор
  if win.cursorLine >= win.scrollY + 1 and win.cursorLine <= win.scrollY + visibleLines then
    local cy = y + (win.cursorLine - win.scrollY) - 1
    gpu.setForeground(0x000000)
    gpu.set(x + math.min(win.cursorCol - 1, w - 1), cy, "_")
  end
end

function notepad.key(win, char, code)
  if code == 28 then -- Enter
    local currentLine = win.lines[win.cursorLine]
    local leftPart = currentLine:sub(1, win.cursorCol - 1)
    local rightPart = currentLine:sub(win.cursorCol)
    
    win.lines[win.cursorLine] = leftPart
    table.insert(win.lines, win.cursorLine + 1, rightPart)
    win.cursorLine = win.cursorLine + 1
    win.cursorCol = 1
    return true
    
  elseif code == 14 then -- Backspace
    if win.cursorCol > 1 then
      local line = win.lines[win.cursorLine]
      win.lines[win.cursorLine] = line:sub(1, win.cursorCol - 2) .. line:sub(win.cursorCol)
      win.cursorCol = win.cursorCol - 1
      return true
    elseif win.cursorLine > 1 then
      local currentLine = win.lines[win.cursorLine]
      table.remove(win.lines, win.cursorLine)
      win.cursorLine = win.cursorLine - 1
      win.cursorCol = #win.lines[win.cursorLine] + 1
      win.lines[win.cursorLine] = win.lines[win.cursorLine] .. currentLine
      return true
    end
    
  elseif char and char >= 32 and char < 127 then
    local line = win.lines[win.cursorLine]
    win.lines[win.cursorLine] = line:sub(1, win.cursorCol - 1) .. 
                                 string.char(char) .. 
                                 line:sub(win.cursorCol)
    win.cursorCol = win.cursorCol + 1
    return true
  end
  
  return false
end