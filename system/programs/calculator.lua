-- ==============================================
-- FixOS 2.0 - Calculator (ВИПРАВЛЕНО)
-- system/programs/calculator.lua
-- ==============================================

local calc = {}

-- Ініціалізація калькулятора
function calc.init(win)
  win.display = "0"
  win.lastNum = 0
  win.operation = nil
  win.newNumber = true
  
  -- Визначаємо кнопки
  win.buttons = {
    -- Ряд 1
    {x=2, y=4, w=6, h=2, t="7", v="7"},
    {x=9, y=4, w=6, h=2, t="8", v="8"},
    {x=16, y=4, w=6, h=2, t="9", v="9"},
    {x=23, y=4, w=6, h=2, t="/", v="/"},
    {x=30, y=4, w=6, h=2, t="C", v="C"},
    
    -- Ряд 2
    {x=2, y=7, w=6, h=2, t="4", v="4"},
    {x=9, y=7, w=6, h=2, t="5", v="5"},
    {x=16, y=7, w=6, h=2, t="6", v="6"},
    {x=23, y=7, w=6, h=2, t="*", v="*"},
    
    -- Ряд 3
    {x=2, y=10, w=6, h=2, t="1", v="1"},
    {x=9, y=10, w=6, h=2, t="2", v="2"},
    {x=16, y=10, w=6, h=2, t="3", v="3"},
    {x=23, y=10, w=6, h=2, t="-", v="-"},
    
    -- Ряд 4
    {x=2, y=13, w=6, h=2, t="0", v="0"},
    {x=9, y=13, w=6, h=2, t=".", v="."},
    {x=16, y=13, w=6, h=2, t="+/-", v="+-"},
    {x=23, y=13, w=6, h=2, t="+", v="+"},
    
    -- Кнопка =
    {x=30, y=7, w=6, h=9, t="=", v="="}
  }
end

-- Малювання калькулятора
function calc.draw(win, gpu, x, y, w, h)
  -- Дисплей
  gpu.setBackground(0xFFFFFF)
  gpu.setForeground(0x000000)
  gpu.fill(x + 1, y, w - 2, 2, " ")
  
  -- Рамка дисплею (3D ефект)
  gpu.setForeground(0x808080)
  for i = 0, w - 3 do
    gpu.set(x + 1 + i, y, "▄")
    gpu.set(x + 1 + i, y + 1, "▀")
  end
  
  -- Текст на дисплеї
  local dispText = tostring(win.display)
  if #dispText > w - 4 then 
    dispText = dispText:sub(1, w - 4) 
  end
  
  gpu.setForeground(0x000000)
  gpu.setBackground(0xFFFFFF)
  -- Вирівнюємо текст праворуч
  local textX = x + w - 2 - #dispText
  gpu.set(textX, y + 1, dispText)
  
  -- Малюємо кнопки
  gpu.setBackground(0xC0C0C0)
  
  for _, btn in ipairs(win.buttons) do
    -- Фон кнопки
    gpu.fill(x + btn.x, y + btn.y, btn.w, btn.h, " ")
    
    -- 3D ефект (підняті краї)
    gpu.setForeground(0xFFFFFF)
    for i = 0, btn.w - 1 do 
      gpu.set(x + btn.x + i, y + btn.y, "▀") 
    end
    for i = 0, btn.h - 1 do 
      gpu.set(x + btn.x, y + btn.y + i, "▌") 
    end
    
    gpu.setForeground(0x808080)
    for i = 0, btn.w - 1 do 
      gpu.set(x + btn.x + i, y + btn.y + btn.h - 1, "▄") 
    end
    for i = 0, btn.h - 1 do 
      gpu.set(x + btn.x + btn.w - 1, y + btn.y + i, "▐") 
    end
    
    -- Текст кнопки (центруємо)
    gpu.setForeground(0x000000)
    local tx = x + btn.x + math.floor((btn.w - #btn.t) / 2)
    local ty = y + btn.y + math.floor(btn.h / 2)
    gpu.set(tx, ty, btn.t)
  end
end

-- Обробка кліку
function calc.click(win, x, y, button)
  -- Перевіряємо, чи клікнули по кнопці
  for _, btn in ipairs(win.buttons) do
    if x >= btn.x and x < btn.x + btn.w and
       y >= btn.y and y < btn.y + btn.h then
      -- Обробляємо натискання кнопки
      calc.handleButton(win, btn.v)
      return true -- Потрібне перемалювання
    end
  end
  
  return false
end

-- Обробка натискання кнопки
function calc.handleButton(win, value)
  if value == "C" then
    -- Скидання
    win.display = "0"
    win.lastNum = 0
    win.operation = nil
    win.newNumber = true
    
  elseif value == "=" then
    -- Обчислення результату
    calc.calculate(win)
    
  elseif value == "+-" then
    -- Зміна знаку
    local num = tonumber(win.display)
    if num then 
      win.display = tostring(-num) 
    end
    
  elseif value == "+" or value == "-" or value == "*" or value == "/" then
    -- Операція
    if win.operation then
      calc.calculate(win)
    end
    
    win.lastNum = tonumber(win.display) or 0
    win.operation = value
    win.newNumber = true
    
  elseif (value >= "0" and value <= "9") or value == "." then
    -- Цифра або точка
    if win.newNumber then
      win.display = (value == ".") and "0." or value
      win.newNumber = false
    else
      -- Не дозволяємо більше однієї крапки
      if value == "." and win.display:find("%.") then 
        return 
      end
      
      -- Додаємо цифру
      if win.display == "0" and value ~= "." then
        win.display = value
      else
        win.display = win.display .. value
      end
    end
  end
end

-- Обчислення результату
function calc.calculate(win)
  if not win.operation then return end
  
  local current = tonumber(win.display) or 0
  local result = nil
  
  if win.operation == "+" then
    result = win.lastNum + current
  elseif win.operation == "-" then
    result = win.lastNum - current
  elseif win.operation == "*" then
    result = win.lastNum * current
  elseif win.operation == "/" then
    if current ~= 0 then
      result = win.lastNum / current
    else
      win.display = "Error: Div/0"
      win.operation = nil
      win.newNumber = true
      return
    end
  end
  
  if result then
    -- Форматуємо результат (прибираємо зайві нулі)
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