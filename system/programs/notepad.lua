-- ==============================================
-- FixOS 2.0 - Notepad (ВИПРАВЛЕНО)
-- system/programs/notepad.lua
-- ==============================================

local notepad = {}

-- Ініціалізація блокнота
function notepad.init(win)
  win.lines = {""}
  win.cursorLine = 1
  win.cursorCol = 1
  win.scrollY = 0
  win.filename = "untitled.txt"
  win.modified = false
end

-- Малювання блокнота
function notepad.draw(win, gpu, x, y, w, h)
  -- Білий фон для тексту
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  gpu.fill(x, y, w, h, " ")
  
  -- Статус бар внизу
  gpu.setBackground(0xC0C0C0)
  gpu.setForeground(0x000000)
  gpu.fill(x, y + h - 1, w, 1, " ")
  
  -- Ім'я файлу
  local filename = win.filename
  if #filename > w - 20 then
    filename = "..." .. filename:sub(-(w - 23))
  end
  gpu.set(x + 1, y + h - 1, "File: " .. filename)
  
  -- Позиція курсора
  local statusText = string.format("Ln %d Col %d", win.cursorLine, win.cursorCol)
  if #statusText <= 15 then
    gpu.set(x + w - 15, y + h - 1, statusText)
  end
  
  -- Індикатор змін
  if win.modified then
    gpu.set(x + w - 17, y + h - 1, "*")
  end
  
  -- Область тексту
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  
  local visibleLines = h - 2
  
  for i = 1, visibleLines do
    local lineIdx = win.scrollY + i
    
    if win.lines[lineIdx] then
      local line = win.lines[lineIdx]
      
      -- Обрізаємо рядок під ширину
      if #line > w then
        line = line:sub(1, w)
      end
      
      gpu.set(x, y + i - 1, line)
    end
  end
  
  -- Малюємо курсор
  local cursorScreenY = win.cursorLine - win.scrollY
  
  if cursorScreenY >= 1 and cursorScreenY <= visibleLines then
    local cy = y + cursorScreenY - 1
    local cx = x + math.min(win.cursorCol - 1, w - 1)
    
    gpu.setForeground(0x000000)
    gpu.setBackground(0xFFFFFF)
    gpu.set(cx, cy, "_")
  end
end

-- Обробка натискання клавіші
function notepad.key(win, char, code)
  local changed = false
  
  if code == 28 then 
    -- Enter - новий рядок
    local currentLine = win.lines[win.cursorLine]
    local leftPart = currentLine:sub(1, win.cursorCol - 1)
    local rightPart = currentLine:sub(win.cursorCol)
    
    win.lines[win.cursorLine] = leftPart
    table.insert(win.lines, win.cursorLine + 1, rightPart)
    
    win.cursorLine = win.cursorLine + 1
    win.cursorCol = 1
    
    changed = true
    
  elseif code == 14 then 
    -- Backspace
    if win.cursorCol > 1 then
      -- Видаляємо символ
      local line = win.lines[win.cursorLine]
      win.lines[win.cursorLine] = line:sub(1, win.cursorCol - 2) .. line:sub(win.cursorCol)
      win.cursorCol = win.cursorCol - 1
      changed = true
      
    elseif win.cursorLine > 1 then
      -- Об'єднуємо з попереднім рядком
      local currentLine = win.lines[win.cursorLine]
      table.remove(win.lines, win.cursorLine)
      
      win.cursorLine = win.cursorLine - 1
      win.cursorCol = #win.lines[win.cursorLine] + 1
      
      win.lines[win.cursorLine] = win.lines[win.cursorLine] .. currentLine
      changed = true
    end
    
  elseif code == 211 then
    -- Delete
    local line = win.lines[win.cursorLine]
    
    if win.cursorCol <= #line then
      -- Видаляємо символ справа
      win.lines[win.cursorLine] = line:sub(1, win.cursorCol - 1) .. line:sub(win.cursorCol + 1)
      changed = true
      
    elseif win.cursorLine < #win.lines then
      -- Об'єднуємо з наступним рядком
      win.lines[win.cursorLine] = line .. win.lines[win.cursorLine + 1]
      table.remove(win.lines, win.cursorLine + 1)
      changed = true
    end
    
  elseif code == 203 then
    -- Стрілка вліво
    if win.cursorCol > 1 then
      win.cursorCol = win.cursorCol - 1
      return true
    elseif win.cursorLine > 1 then
      win.cursorLine = win.cursorLine - 1
      win.cursorCol = #win.lines[win.cursorLine] + 1
      return true
    end
    
  elseif code == 205 then
    -- Стрілка вправо
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
    -- Стрілка вгору
    if win.cursorLine > 1 then
      win.cursorLine = win.cursorLine - 1
      
      -- Переміщаємо курсор в кінець рядка якщо він виходить за межі
      local line = win.lines[win.cursorLine]
      if win.cursorCol > #line + 1 then
        win.cursorCol = #line + 1
      end
      
      return true
    end
    
  elseif code == 208 then
    -- Стрілка вниз
    if win.cursorLine < #win.lines then
      win.cursorLine = win.cursorLine + 1
      
      -- Переміщаємо курсор в кінець рядка якщо він виходить за межі
      local line = win.lines[win.cursorLine]
      if win.cursorCol > #line + 1 then
        win.cursorCol = #line + 1
      end
      
      return true
    end
    
  elseif code == 199 then
    -- Home
    win.cursorCol = 1
    return true
    
  elseif code == 207 then
    -- End
    win.cursorCol = #win.lines[win.cursorLine] + 1
    return true
    
  elseif char and char >= 32 and char <= 255 then
    -- Друкований символ (ВИПРАВЛЕНО: розширено діапазон)
    local line = win.lines[win.cursorLine]
    
    win.lines[win.cursorLine] = line:sub(1, win.cursorCol - 1) .. 
                                 string.char(char) .. 
                                 line:sub(win.cursorCol)
    
    win.cursorCol = win.cursorCol + 1
    changed = true
  end
  
  -- Оновлюємо прапорець змін
  if changed then
    win.modified = true
  end
  
  -- Автоскролінг
  local visibleLines = 18 -- Приблизно
  
  if win.cursorLine < win.scrollY + 1 then
    win.scrollY = win.cursorLine - 1
  elseif win.cursorLine > win.scrollY + visibleLines then
    win.scrollY = win.cursorLine - visibleLines
  end
  
  return changed or code == 203 or code == 205 or code == 200 or code == 208 or code == 199 or code == 207
end

return notepad