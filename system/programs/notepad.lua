-- ==============================================
-- FixOS 3.0 - Notepad
-- system/programs/notepad.lua
-- ==============================================

local notepad = {}

function notepad.init(win)
  win.lines = {""}
  win.cursorLine = 1
  win.cursorCol = 1
  win.scrollY = 0
  win.filename = "untitled.txt"
  win.modified = false
end

function notepad.draw(win, gpu, x, y, w, h)
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  gpu.fill(x, y, w, h, " ")
  
  gpu.setBackground(0xC0C0C0)
  gpu.fill(x, y + h - 1, w, 1, " ")
  
  local filename = win.filename
  if #filename > w - 20 then
    filename = "..." .. filename:sub(-(w - 23))
  end
  gpu.set(x + 1, y + h - 1, "File: " .. filename)
  
  local statusText = string.format("Ln %d Col %d", win.cursorLine, win.cursorCol)
  if #statusText <= 15 then
    gpu.set(x + w - 15, y + h - 1, statusText)
  end
  
  if win.modified then
    gpu.set(x + w - 17, y + h - 1, "*")
  end
  
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  
  local visibleLines = h - 2
  
  for i = 1, visibleLines do
    local lineIdx = win.scrollY + i
    
    if win.lines[lineIdx] then
      local line = win.lines[lineIdx]
      
      if #line > w then
        line = line:sub(1, w)
      end
      
      gpu.set(x, y + i - 1, line)
    end
  end
  
  local cursorScreenY = win.cursorLine - win.scrollY
  
  if cursorScreenY >= 1 and cursorScreenY <= visibleLines then
    local cy = y + cursorScreenY - 1
    local cx = x + math.min(win.cursorCol - 1, w - 1)
    
    gpu.setForeground(0x000000)
    gpu.setBackground(0xFFFFFF)
    gpu.set(cx, cy, "_")
  end
end

function notepad.key(win, char, code)
  local changed = false
  
  if code == 28 then 
    local currentLine = win.lines[win.cursorLine]
    local leftPart = currentLine:sub(1, win.cursorCol - 1)
    local rightPart = currentLine:sub(win.cursorCol)
    
    win.lines[win.cursorLine] = leftPart
    table.insert(win.lines, win.cursorLine + 1, rightPart)
    
    win.cursorLine = win.cursorLine + 1
    win.cursorCol = 1
    
    changed = true
    
  elseif code == 14 then 
    if win.cursorCol > 1 then
      local line = win.lines[win.cursorLine]
      win.lines[win.cursorLine] = line:sub(1, win.cursorCol - 2) .. line:sub(win.cursorCol)
      win.cursorCol = win.cursorCol - 1
      changed = true
      
    elseif win.cursorLine > 1 then
      local currentLine = win.lines[win.cursorLine]
      table.remove(win.lines, win.cursorLine)
      
      win.cursorLine = win.cursorLine - 1
      win.cursorCol = #win.lines[win.cursorLine] + 1
      
      win.lines[win.cursorLine] = win.lines[win.cursorLine] .. currentLine
      changed = true
    end
    
  elseif code == 211 then
    local line = win.lines[win.cursorLine]
    
    if win.cursorCol <= #line then
      win.lines[win.cursorLine] = line:sub(1, win.cursorCol - 1) .. line:sub(win.cursorCol + 1)
      changed = true
      
    elseif win.cursorLine < #win.lines then
      win.lines[win.cursorLine] = line .. win.lines[win.cursorLine + 1]
      table.remove(win.lines, win.cursorLine + 1)
      changed = true
    end
    
  elseif code == 203 then
    if win.cursorCol > 1 then
      win.cursorCol = win.cursorCol - 1
      return true
    elseif win.cursorLine > 1 then
      win.cursorLine = win.cursorLine - 1
      win.cursorCol = #win.lines[win.cursorLine] + 1
      return true
    end
    
  elseif code == 205 then
    local line = win.lines[win.cursorLine]
    
    if win.cursorCol <= #line then
      win.cursorCol = win.cursorCol + 1
      return true
    elseif win.cursorLine < #win.lines then
      win.cursorLine = win.cursorLine + 1
      win.cursorCol = 1
      return true
    end
    
  elseif code == 200 then
    if win.cursorLine > 1 then
      win.cursorLine = win.cursorLine - 1
      
      local line = win.lines[win.cursorLine]
      if win.cursorCol > #line + 1 then
        win.cursorCol = #line + 1
      end
      
      return true
    end
    
  elseif code == 208 then
    if win.cursorLine < #win.lines then
      win.cursorLine = win.cursorLine + 1
      
      local line = win.lines[win.cursorLine]
      if win.cursorCol > #line + 1 then
        win.cursorCol = #line + 1
      end
      
      return true
    end
    
  elseif code == 199 then
    win.cursorCol = 1
    return true
    
  elseif code == 207 then
    win.cursorCol = #win.lines[win.cursorLine] + 1
    return true
    
  elseif char and char >= 32 and char <= 255 then
    local line = win.lines[win.cursorLine]
    
    win.lines[win.cursorLine] = line:sub(1, win.cursorCol - 1) .. 
                                 string.char(char) .. 
                                 line:sub(win.cursorCol)
    
    win.cursorCol = win.cursorCol + 1
    changed = true
  end
  
  if changed then
    win.modified = true
  end
  
  local visibleLines = 18
  
  if win.cursorLine < win.scrollY + 1 then
    win.scrollY = win.cursorLine - 1
  elseif win.cursorLine > win.scrollY + visibleLines then
    win.scrollY = win.cursorLine - visibleLines
  end
  
  return changed or code == 203 or code == 205 or code == 200 or code == 208 or code == 199 or code == 207
end

return notepad
