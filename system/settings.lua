local component = require("component")
local event = require("event")
local computer = require("computer")

local gpu = component.gpu
local w, h = gpu.getResolution()

-- Кольори
local COLORS = {
  windowBg = 0xC0C0C0,
  titleBar = 0x000080,
  white = 0xFFFFFF,
  black = 0x000000,
  btnFace = 0xC0C0C0,
  btnHighlight = 0xFFFFFF,
  btnShadow = 0x808080
}

-- Малювання 3D кнопки
local function draw3DButton(x, y, w, h, text, pressed)
  if pressed then
    gpu.setBackground(COLORS.btnShadow)
  else
    gpu.setBackground(COLORS.btnFace)
  end
  gpu.fill(x, y, w, h, " ")
  
  -- Рамка
  gpu.setForeground(pressed and COLORS.btnShadow or COLORS.btnHighlight)
  for i = 0, w - 1 do
    gpu.set(x + i, y, "▀")
  end
  for i = 0, h - 1 do
    gpu.set(x, y + i, "▌")
  end
  
  gpu.setForeground(pressed and COLORS.btnHighlight or COLORS.btnShadow)
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

-- Малювання вікна
local function drawWindow()
  -- Тінь
  gpu.setBackground(COLORS.black)
  gpu.fill(2, 2, w - 2, h - 2, " ")
  
  -- Основне вікно
  gpu.setBackground(COLORS.windowBg)
  gpu.fill(1, 1, w - 2, h - 2, " ")
  
  -- Заголовок
  gpu.setBackground(COLORS.titleBar)
  gpu.setForeground(COLORS.white)
  gpu.fill(1, 1, w - 2, 1, " ")
  gpu.set(2, 1, "FixOS 2000 Settings")
  
  -- Кнопки закриття (X)
  gpu.set(w - 3, 1, "[X]")
  
  -- Вміст
  gpu.setBackground(COLORS.windowBg)
  gpu.setForeground(COLORS.black)
  
  gpu.set(3, 3, "System Information:")
  gpu.set(3, 5, "OS: FixOS 2000")
  gpu.set(3, 6, "Version: 1.0 Classic Edition")
  gpu.set(3, 7, "Author: FixlutGames21")
  
  local totalMem = computer.totalMemory()
  local freeMem = computer.freeMemory()
  gpu.set(3, 9, "Memory: " .. math.floor(freeMem/1024) .. "KB / " .. math.floor(totalMem/1024) .. "KB")
  
  local energy = computer.energy()
  local maxEnergy = computer.maxEnergy()
  gpu.set(3, 10, "Energy: " .. math.floor(energy) .. " / " .. math.floor(maxEnergy))
  
  -- Адреси компонентів
  gpu.set(3, 12, "Components:")
  local y = 13
  for name in component.list() do
    if y < h - 5 then
      gpu.set(4, y, "- " .. name)
      y = y + 1
    end
  end
  
  -- Кнопка OK
  draw3DButton(math.floor(w/2) - 5, h - 4, 10, 2, "OK", false)
end

drawWindow()

-- Обробка подій
while true do
  local eventData = {event.pull()}
  local eventType = eventData[1]
  
  if eventType == "touch" then
    local _, _, x, y = table.unpack(eventData)
    
    -- Перевірка кнопки X
    if y == 1 and x >= w - 3 and x <= w - 1 then
      break
    end
    
    -- Перевірка кнопки OK
    if x >= math.floor(w/2) - 5 and x <= math.floor(w/2) + 5 and
       y >= h - 4 and y <= h - 2 then
      draw3DButton(math.floor(w/2) - 5, h - 4, 10, 2, "OK", true)
      os.sleep(0.1)
      break
    end
  elseif eventType == "key_down" then
    local _, _, _, code = table.unpack(eventData)
    if code == 28 or code == 1 then -- Enter або Esc
      break
    end
  end
end
