-- ==============================================
-- FixOS 2.0 - Calculator Program
-- system/programs/calculator.lua
-- ==============================================

local calc = {}

function calc.init(win)
  win.display = "0"
  win.lastNum = 0
  win.operation = nil
  win.newNumber = true
  
  win.buttons = {
    {x=2, y=4, w=6, h=2, t="7", v="7"},
    {x=9, y=4, w=6, h=2, t="8", v="8"},
    {x=16, y=4, w=6, h=2, t="9", v="9"},
    {x=23, y=4, w=6, h=2, t="/", v="/"},
    {x=30, y=4, w=6, h=2, t="C", v="C"},
    
    {x=2, y=7, w=6, h=2, t="4", v="4"},
    {x=9, y=7, w=6, h=2, t="5", v="5"},
    {x=16, y=7, w=6, h=2, t="6", v="6"},
    {x=23, y=7, w=6, h=2, t="*", v="*"},
    
    {x=2, y=10, w=6, h=2, t="1", v="1"},
    {x=9, y=10, w=6, h=2, t="2", v="2"},
    {x=16, y=10, w=6, h=2, t="3", v="3"},
    {x=23, y=10, w=6, h=2, t="-", v="-"},
    
    {x=2, y=13, w=6, h=2, t="0", v="0"},
    {x=9, y=13, w=6, h=2, t=".", v="."},
    {x=16, y=13, w=6, h=2, t="+/-", v="+-"},
    {x=23, y=13, w=6, h=2, t="+", v="+"},
    {x=30, y=7, w=6, h=9, t="=", v="="}
  }
end

function calc.draw(win, gpu, x, y, w, h)
  -- Дисплей
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  gpu.fill(x + 1, y, w - 2, 2, " ")
  
  -- Рамка дисплею
  gpu.setForeground(0x808080)
  for i = 0, w - 3 do
    gpu.set(x + 1 + i, y, "▄")
    gpu.set(x + 1 + i, y + 1, "▀")
  end
  
  local dispText = tostring(win.display)
  if #dispText > w - 4 then dispText = dispText:sub(1, w - 4) end
  gpu.setForeground(0x000000)
  gpu.set(x + w - 2 - #dispText, y + 1, dispText)
  
  -- Кнопки
  gpu.setBackground(0xC0C0C0)
  for _, btn in ipairs(win.buttons) do
    gpu.fill(x + btn.x, y + btn.y, btn.w, btn.h, " ")
    
    -- 3D ефект
    gpu.setForeground(0xFFFFFF)
    for i = 0, btn.w - 1 do gpu.set(x + btn.x + i, y + btn.y, "▀") end
    for i = 0, btn.h - 1 do gpu.set(x + btn.x, y + btn.y + i, "▌") end
    
    gpu.setForeground(0x808080)
    for i = 0, btn.w - 1 do gpu.set(x + btn.x + i, y + btn.y + btn.h - 1, "▄") end
    for i = 0, btn.h - 1 do gpu.set(x + btn.x + btn.w - 1, y + btn.y + i, "▐") end
    
    gpu.setForeground(0x000000)
    local tx = x + btn.x + math.floor((btn.w - #btn.t) / 2)
    local ty = y + btn.y + math.floor(btn.h / 2)
    gpu.set(tx, ty, btn.t)
  end
end

function calc.click(win, x, y, button)
  for _, btn in ipairs(win.buttons) do
    if x >= btn.x and x < btn.x + btn.w and
       y >= btn.y and y < btn.y + btn.h then
      calc.handleButton(win, btn.v)
      return true
    end
  end
  return false
end

function calc.handleButton(win, value)
  if value == "C" then
    win.display = "0"
    win.lastNum = 0
    win.operation = nil
    win.newNumber = true
  elseif value == "=" then
    calc.calculate(win)
  elseif value == "+-" then
    local num = tonumber(win.display)
    if num then win.display = tostring(-num) end
  elseif value == "+" or value == "-" or value == "*" or value == "/" then
    if win.operation then calc.calculate(win) end
    win.lastNum = tonumber(win.display) or 0
    win.operation = value
    win.newNumber = true
  elseif (value >= "0" and value <= "9") or value == "." then
    if win.newNumber then
      win.display = (value == ".") and "0." or value
      win.newNumber = false
    else
      if value == "." and win.display:find("%.") then return end
      win.display = (win.display == "0" and value ~= ".") and value or (win.display .. value)
    end
  end
end

function calc.calculate(win)
  if win.operation and win.lastNum then
    local current = tonumber(win.display) or 0
    local result
    if win.operation == "+" then result = win.lastNum + current
    elseif win.operation == "-" then result = win.lastNum - current
    elseif win.operation == "*" then result = win.lastNum * current
    elseif win.operation == "/" then
      result = (current ~= 0) and (win.lastNum / current) or nil
    end
    
    if result then
      win.display = string.format("%.8f", result):gsub("%.?0+$", "")
      if win.display == "" then win.display = "0" end
    else
      win.display = "Error"
    end
    
    win.lastNum = tonumber(win.display) or 0
    win.operation = nil
  end
  win.newNumber = true
end

return calc