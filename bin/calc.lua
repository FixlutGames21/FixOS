local component = require("component")
local event = require("event")

local gpu = component.gpu
local w, h = gpu.getResolution()

local COLORS = {
  windowBg = 0xC0C0C0,
  titleBar = 0x000080,
  white = 0xFFFFFF,
  black = 0x000000,
  display = 0xFFFFFF,
  btnFace = 0xC0C0C0,
  btnHighlight = 0xFFFFFF,
  btnShadow = 0x808080
}

local display = "0"
local lastNum = 0
local operation = nil
local newNumber = true

-- Малювання 3D кнопки
local function draw3DButton(x, y, w, h, text)
  gpu.setBackground(COLORS.btnFace)
  gpu.fill(x, y, w, h, " ")
  
  -- Світла рамка зверху та зліва
  gpu.setForeground(COLORS.btnHighlight)
  for i = 0, w - 1 do
    gpu.set(x + i, y, "▀")
  end
  for i = 0, h - 1 do
    gpu.set(x, y + i, "▌")
  end
  
  -- Темна рамка знизу та справа
  gpu.setForeground(COLORS.btnShadow)
  for i = 0, w - 1 do
    gpu.set(x + i, y + h - 1, "▄")
  end
  for i = 0, h - 1 do
    gpu.set(x + w - 1, y + i, "▐")
  end
  
  -- Текст
  gpu.setBackground(COLORS.btnFace)
  gpu.setForeground(COLORS.black)
  local textX = x + math.floor((w - #text) / 2)
  local textY = y + math.floor(h / 2)
  gpu.set(textX, textY, text)
end

-- Малювання калькулятора
local function drawCalc()
  -- Тінь
  gpu.setBackground(COLORS.black)
  gpu.fill(2, 2, 35, 19, " ")
  
  -- Основне вікно
  gpu.setBackground(COLORS.windowBg)
  gpu.fill(1, 1, 35, 19, " ")
  
  -- Заголовок
  gpu.setBackground(COLORS.titleBar)
  gpu.setForeground(COLORS.white)
  gpu.fill(1, 1, 35, 1, " ")
  gpu.set(2, 1, "Calculator")
  gpu.set(33, 1, "[X]")
  
  -- Дисплей
  gpu.setBackground(COLORS.display)
  gpu.setForeground(COLORS.black)
  gpu.fill(2, 3, 32, 2, " ")
  
  -- Рамка дисплею
  gpu.setForeground(COLORS.btnShadow)
  for i = 2, 33 do
    gpu.set(i, 3, "▄")
  end
  gpu.set(2, 3, "┌")
  gpu.set(2, 4, "│")
  
  gpu.setForeground(COLORS.btnHighlight)
  for i = 2, 33 do
    gpu.set(i, 4, "▀")
  end
  gpu.set(33, 3, "┐")
  gpu.set(33, 4, "│")
  
  -- Текст на дисплеї
  gpu.setBackground(COLORS.display)
  gpu.setForeground(COLORS.black)
  local dispText = tostring(display)
  if #dispText > 28 then dispText = dispText:sub(1, 28) end
  gpu.set(32 - #dispText, 4, dispText)
  
  -- Кнопки
  local buttons = {
    {x=2, y=6, w=6, h=2, t="7", v="7"},
    {x=9, y=6, w=6, h=2, t="8", v="8"},
    {x=16, y=6, w=6, h=2, t="9", v="9"},
    {x=23, y=6, w=6, h=2, t="/", v="/"},
    {x=30, y=6, w=5, h=2, t="C", v="C"},
    
    {x=2, y=9, w=6, h=2, t="4", v="4"},
    {x=9, y=9, w=6, h=2, t="5", v="5"},
    {x=16, y=9, w=6, h=2, t="6", v="6"},
    {x=23, y=9, w=6, h=2, t="*", v="*"},
    {x=30, y=9, w=5, h=2, t="CE", v="CE"},
    
    {x=2, y=12, w=6, h=2, t="1", v="1"},
    {x=9, y=12, w=6, h=2, t="2", v="2"},
    {x=16, y=12, w=6, h=2, t="3", v="3"},
    {x=23, y=12, w=6, h=2, t="-", v="-"},
    {x=30, y=12, w=5, h=4, t="=", v="="},
    
    {x=2, y=15, w=6, h=2, t="0", v="0"},
    {x=9, y=15, w=6, h=2, t=".", v="."},
    {x=16, y=15, w=6, h=2, t="+/-", v="+-"},
    {x=23, y=15, w=6, h=2, t="+", v="+"}
  }
  
  for _, btn in ipairs(buttons) do
    draw3DButton(btn.x, btn.y, btn.w, btn.h, btn.t)
  end
  
  return buttons
end

local buttons = drawCalc()

-- Обчислення
local function calculate()
  if operation and lastNum then
    local current = tonumber(display) or 0
    if operation == "+" then
      display = tostring(lastNum + current)
    elseif operation == "-" then
      display = tostring(lastNum - current)
    elseif operation == "*" then
      display = tostring(lastNum * current)
    elseif operation == "/" then
      if current ~= 0 then
        display = tostring(lastNum / current)
      else
        display = "Error"
      end
    end
    
    -- Форматування результату
    local num = tonumber(display)
    if num then
      -- Округлення до 8 знаків після коми
      display = string.format("%.8f", num)
      display = display:gsub("%.?0+$", "") -- Видаляємо зайві нулі
      if display == "" then display = "0" end
    end
    
    lastNum = tonumber(display) or 0
    operation = nil
  end
  newNumber = true
end

-- Обробка натискань
local function handleButton(value)
  if value == "C" then
    display = "0"
    lastNum = 0
    operation = nil
    newNumber = true
  elseif value == "CE" then
    display = "0"
    newNumber = true
  elseif value == "=" then
    calculate()
  elseif value == "+-" then
    local num = tonumber(display)
    if num then
      display = tostring(-num)
    end
  elseif value == "+" or value == "-" or value == "*" or value == "/" then
    if operation then calculate() end
    lastNum = tonumber(display) or 0
    operation = value
    newNumber = true
  elseif (value >= "0" and value <= "9") or value == "." then
    if newNumber then
      if value == "." then
        display = "0."
      else
        display = value
      end
      newNumber = false
    else
      if value == "." and display:find("%.") then return end
      if display == "0" and value ~= "." then
        display = value
      else
        display = display .. value
      end
    end
  end
  
  drawCalc()
end

-- Головний цикл
while true do
  local eventData = {event.pull()}
  local eventType = eventData[1]
  
  if eventType == "touch" then
    local _, _, x, y = table.unpack(eventData)
    
    -- Кнопка закриття
    if y == 1 and x >= 33 then
      break
    end
    
    -- Перевірка кнопок
    for _, btn in ipairs(buttons) do
      if x >= btn.x and x < btn.x + btn.w and
         y >= btn.y and y < btn.y + btn.h then
        handleButton(btn.v)
        break
      end
    end
    
  elseif eventType == "key_down" then
    local _, _, char, code = table.unpack(eventData)
    
    if code == 1 then -- Esc
      break
    elseif code == 28 then -- Enter
      handleButton("=")
    elseif code == 14 then -- Backspace
      if #display > 1 then
        display = display:sub(1, -2)
        drawCalc()
      else
        display = "0"
        drawCalc()
      end
    else
      -- Клавіатурний ввод
      if char >= 48 and char <= 57 then -- 0-9
        handleButton(string.char(char))
      elseif char == 46 then -- .
        handleButton(".")
      elseif char == 43 then -- +
        handleButton("+")
      elseif char == 45 then -- -
        handleButton("-")
      elseif char == 42 then -- *
        handleButton("*")
      elseif char == 47 then -- /
        handleButton("/")
      elseif char == 99 or char == 67 then -- c або C
        handleButton("C")
      end
    end
  end
end
