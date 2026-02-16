-- ==============================================
-- FixOS 3.1.0 - Calculator (WINDOWS 10 STYLE)
-- ==============================================

local calc = {}

function calc.init(win)
  win.display = "0"
  win.lastNum = 0
  win.operation = nil
  win.newNumber = true
  win.buttons = {}
  
  -- Windows 10 calculator layout
  local btnData = {
    -- Row 1
    {"C", 2, 3, 8, 3, 0xE81123},
    {"±", 11, 3, 8, 3, 0x2D2D30},
    {"%", 20, 3, 8, 3, 0x2D2D30},
    {"÷", 29, 3, 8, 3, 0x0078D7},
    
    -- Row 2
    {"7", 2, 7, 8, 3, 0x3E3E42},
    {"8", 11, 7, 8, 3, 0x3E3E42},
    {"9", 20, 7, 8, 3, 0x3E3E42},
    {"×", 29, 7, 8, 3, 0x0078D7},
    
    -- Row 3
    {"4", 2, 11, 8, 3, 0x3E3E42},
    {"5", 11, 11, 8, 3, 0x3E3E42},
    {"6", 20, 11, 8, 3, 0x3E3E42},
    {"-", 29, 11, 8, 3, 0x0078D7},
    
    -- Row 4
    {"1", 2, 15, 8, 3, 0x3E3E42},
    {"2", 11, 15, 8, 3, 0x3E3E42},
    {"3", 20, 15, 8, 3, 0x3E3E42},
    {"+", 29, 15, 8, 3, 0x0078D7},
    
    -- Row 5
    {"0", 2, 19, 17, 3, 0x3E3E42},
    {".", 20, 19, 8, 3, 0x3E3E42},
    {"=", 29, 19, 8, 3, 0x10893E}
  }
  
  for _, btn in ipairs(btnData) do
    table.insert(win.buttons, {
      label = btn[1],
      x = btn[2],
      y = btn[3],
      w = btn[4],
      h = btn[5],
      color = btn[6]
    })
  end
end

function calc.draw(win, gpu, x, y, w, h)
  -- Background
  gpu.setBackground(0x1E1E1E)
  gpu.fill(x, y, w, h, " ")
  
  -- Display (flat)
  gpu.setBackground(0x2D2D30)
  gpu.fill(x + 1, y, w - 2, 2, " ")
  
  gpu.setForeground(0xFFFFFF)
  local dispText = tostring(win.display)
  if #dispText > w - 4 then
    dispText = dispText:sub(1, w - 4)
  end
  local textX = x + w - 3 - #dispText
  gpu.set(textX, y + 1, dispText)
  
  -- Buttons (flat tiles)
  for _, btn in ipairs(win.buttons) do
    gpu.setBackground(btn.color)
    gpu.fill(x + btn.x, y + btn.y, btn.w, btn.h, " ")
    
    gpu.setForeground(0xFFFFFF)
    local labelX = x + btn.x + math.floor((btn.w - #btn.label) / 2)
    local labelY = y + btn.y + math.floor(btn.h / 2)
    gpu.set(labelX, labelY, btn.label)
  end
end

function calc.click(win, clickX, clickY, button)
  local relX = clickX - win.x - 1
  local relY = clickY - win.y - 2
  
  for _, btn in ipairs(win.buttons) do
    if relX >= btn.x and relX < btn.x + btn.w and
       relY >= btn.y and relY < btn.y + btn.h then
      calc.handleButton(win, btn.label)
      return true
    end
  end
  
  return false
end

function calc.handleButton(win, label)
  if label == "C" then
    win.display = "0"
    win.lastNum = 0
    win.operation = nil
    win.newNumber = true
    
  elseif label == "=" then
    calc.calculate(win)
    
  elseif label == "±" then
    local num = tonumber(win.display)
    if num then
      win.display = tostring(-num)
    end
    
  elseif label == "+" or label == "-" or label == "×" or label == "÷" then
    if win.operation then
      calc.calculate(win)
    end
    
    win.lastNum = tonumber(win.display) or 0
    win.operation = label
    win.newNumber = true
    
  elseif (label >= "0" and label <= "9") or label == "." then
    if win.newNumber then
      win.display = (label == ".") and "0." or label
      win.newNumber = false
    else
      if label == "." and win.display:find("%.") then
        return
      end
      
      if win.display == "0" and label ~= "." then
        win.display = label
      else
        win.display = win.display .. label
      end
    end
  end
end

function calc.calculate(win)
  if not win.operation then return end
  
  local current = tonumber(win.display) or 0
  local result = nil
  
  if win.operation == "+" then
    result = win.lastNum + current
  elseif win.operation == "-" then
    result = win.lastNum - current
  elseif win.operation == "×" then
    result = win.lastNum * current
  elseif win.operation == "÷" then
    if current ~= 0 then
      result = win.lastNum / current
    else
      win.display = "Error"
      win.operation = nil
      win.newNumber = true
      return
    end
  end
  
  if result then
    win.display = string.format("%.8f", result):gsub("%.?0+$", "")
    if win.display == "" or win.display == "-" then
      win.display = "0"
    end
  end
  
  win.lastNum = tonumber(win.display) or 0
  win.operation = nil
  win.newNumber = true
end

return calc
