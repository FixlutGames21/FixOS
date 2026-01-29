-- ==============================================
-- FixOS 2.0 - system/desktop.lua
-- Модульний робочий стіл (ПОКРАЩЕНО)
-- ==============================================

local component = require("component")
local computer = require("computer")
local event = require("event")
local unicode = require("unicode")

if not component.isAvailable("gpu") then
  error("ERROR: No GPU available!")
end

local gpu = component.gpu
local w, h = gpu.maxResolution()
gpu.setResolution(math.min(80, w), math.min(25, h))
w, h = gpu.getResolution()

-- COLORS
local COLORS = {
  desktop = 0x008080,
  taskbar = 0xC0C0C0,
  taskbarDark = 0x808080,
  startBtn = 0x00AA00,
  startBtnText = 0xFFFFFF,
  iconBg = 0x008080,
  iconText = 0xFFFFFF,
  iconSelected = 0x000080,
  windowTitle = 0x000080,
  windowBg = 0xC0C0C0,
  white = 0xFFFFFF,
  black = 0x000000,
  btnHighlight = 0xFFFFFF,
  btnShadow = 0x808080,
  error = 0xFF0000
}

-- ICONS
local ICONS = {
  {x = 2, y = 2, w = 12, h = 4, label = "My Computer", icon = "[PC]", program = "mycomputer"},
  {x = 2, y = 7, w = 12, h = 4, label = "Calculator", icon = "[=]", program = "calculator"},
  {x = 2, y = 12, w = 12, h = 4, label = "Notepad", icon = "[N]", program = "notepad"},
  {x = 2, y = 17, w = 12, h = 4, label = "Settings", icon = "[*]", program = "settings"}
}

local selectedIcon = nil
local startMenuOpen = false
local activeWindows = {}
local focusedWindow = nil
local dragWindow = nil
local dragOffsetX, dragOffsetY = 0, 0
local clockTimer = 0

-- Завантаження програм
local programs = {}

local function loadProgram(name)
  if programs[name] then return programs[name] end
  
  local path = "/system/programs/" .. name .. ".lua"
  
  -- Перевірка існування файлу
  local fs = require("filesystem")
  if not fs.exists(path) then
    return nil, "Program file not found: " .. path
  end
  
  local ok, module = pcall(dofile, path)
  
  if ok and module then
    programs[name] = module
    return module
  else
    return nil, "Failed to load program: " .. tostring(module)
  end
end

-- GUI Functions
local function draw3DFrame(x, y, w, h, raised)
  if raised then
    gpu.setForeground(COLORS.btnHighlight)
    for i = 0, w - 1 do gpu.set(x + i, y, "─") end
    for i = 0, h - 1 do gpu.set(x, y + i, "│") end
    
    gpu.setForeground(COLORS.btnShadow)
    for i = 0, w - 1 do gpu.set(x + i, y + h - 1, "─") end
    for i = 0, h - 1 do gpu.set(x + w - 1, y + i, "│") end
  else
    gpu.setForeground(COLORS.btnShadow)
    for i = 0, w - 1 do gpu.set(x + i, y, "─") end
    for i = 0, h - 1 do gpu.set(x, y + i, "│") end
    
    gpu.setForeground(COLORS.btnHighlight)
    for i = 0, w - 1 do gpu.set(x + i, y + h - 1, "─") end
    for i = 0, h - 1 do gpu.set(x + w - 1, y + i, "│") end
  end
end

local function drawIcon(icon, selected)
  local bg = selected and COLORS.iconSelected or COLORS.iconBg
  local fg = COLORS.iconText
  
  if selected then
    gpu.setBackground(bg)
    gpu.fill(icon.x, icon.y, icon.w, icon.h, " ")
  end
  
  gpu.setForeground(fg)
  local iconX = icon.x + math.floor(icon.w / 2) - math.floor(unicode.len(icon.icon) / 2)
  gpu.set(iconX, icon.y + 1, icon.icon)
  
  local textX = icon.x + math.floor((icon.w - unicode.len(icon.label)) / 2)
  gpu.set(textX, icon.y + 3, icon.label)
  
  gpu.setBackground(COLORS.desktop)
end

local function drawTaskbar()
  gpu.setBackground(COLORS.taskbar)
  gpu.fill(1, h, w, 1, " ")
  
  gpu.setForeground(COLORS.btnHighlight)
  for i = 1, w do gpu.set(i, h, "▀") end
  
  -- Start button
  gpu.setBackground(COLORS.startBtn)
  gpu.setForeground(COLORS.startBtnText)
  gpu.fill(2, h, 9, 1, " ")
  gpu.set(3, h, "⊞ Start")
  
  gpu.setBackground(COLORS.taskbar)
  gpu.setForeground(COLORS.btnShadow)
  gpu.set(12, h, "│")
  
  -- Window buttons
  local btnX = 14
  for i, win in ipairs(activeWindows) do
    if btnX + 15 < w - 7 then
      local isFocused = (focusedWindow == i)
      gpu.setBackground(isFocused and COLORS.taskbarDark or COLORS.taskbar)
      gpu.setForeground(COLORS.black)
      gpu.fill(btnX, h, 15, 1, " ")
      local title = win.title or "Window"
      if unicode.len(title) > 12 then title = unicode.sub(title, 1, 12) .. "..." end
      gpu.set(btnX + 1, h, title)
      btnX = btnX + 16
    end
  end
  
  -- Clock
  gpu.setBackground(COLORS.taskbar)
  gpu.setForeground(COLORS.black)
  local time = os.date("%H:%M")
  gpu.set(w - 6, h, time)
end

local function drawDesktop()
  gpu.setBackground(COLORS.desktop)
  gpu.fill(1, 1, w, h - 1, " ")
  
  for i, icon in ipairs(ICONS) do
    drawIcon(icon, selectedIcon == i)
  end
  
  drawTaskbar()
  startMenuOpen = false
end

local function drawWindow(win)
  local wx, wy, ww, wh = win.x, win.y, win.w, win.h
  
  -- Shadow
  gpu.setBackground(COLORS.black)
  gpu.fill(wx + 1, wy + 1, ww, wh, " ")
  
  -- Window background
  gpu.setBackground(COLORS.windowBg)
  gpu.fill(wx, wy, ww, wh, " ")
  
  -- Title bar
  local isFocused = (activeWindows[focusedWindow] == win)
  gpu.setBackground(isFocused and COLORS.windowTitle or COLORS.btnShadow)
  gpu.setForeground(COLORS.white)
  gpu.fill(wx, wy, ww, 1, " ")
  
  local title = win.title or "Window"
  if unicode.len(title) > ww - 6 then
    title = unicode.sub(title, 1, ww - 9) .. "..."
  end
  gpu.set(wx + 1, wy, title)
  
  -- Window controls
  gpu.set(wx + ww - 4, wy, "[_]")
  gpu.set(wx + ww - 2, wy, "[X]")
  
  -- Content area
  gpu.setBackground(COLORS.windowBg)
  draw3DFrame(wx, wy + 1, ww, wh - 1, true)
  
  -- Draw program content with error handling
  if win.draw then
    local ok, err = pcall(win.draw, win, gpu, wx + 1, wy + 2, ww - 2, wh - 3)
    if not ok then
      gpu.setBackground(COLORS.windowBg)
      gpu.setForeground(COLORS.error)
      gpu.set(wx + 2, wy + 3, "Error drawing window:")
      gpu.set(wx + 2, wy + 4, tostring(err):sub(1, ww - 4))
    end
  end
end

local function redrawAll()
  drawDesktop()
  for i, win in ipairs(activeWindows) do
    drawWindow(win)
  end
  if startMenuOpen then
    drawStartMenu()
  end
end

function drawStartMenu()
  local menuW = 28
  local menuH = 14
  local menuX = 2
  local menuY = h - menuH - 1
  
  -- Shadow
  gpu.setBackground(COLORS.black)
  gpu.fill(menuX + 1, menuY + 1, menuW, menuH, " ")
  
  -- Menu background
  gpu.setBackground(COLORS.windowBg)
  gpu.fill(menuX, menuY, menuW, menuH, " ")
  
  -- Title
  gpu.setBackground(COLORS.windowTitle)
  gpu.setForeground(COLORS.white)
  gpu.fill(menuX, menuY, menuW, 2, " ")
  gpu.set(menuX + 1, menuY + 1, " FixOS 2.0")
  
  -- Menu items
  gpu.setBackground(COLORS.windowBg)
  gpu.setForeground(COLORS.black)
  
  local items = {
    {y = 3, text = " ► Programs", action = "programs"},
    {y = 4, text = " ► Documents", action = "docs"},
    {y = 5, text = " ► Settings", action = "settings"},
    {y = 7, text = " ► Search", action = "search"},
    {y = 8, text = " ► Help", action = "help"},
    {y = 9, text = " ► Run...", action = "run"},
    {y = 11, text = " ⊗ Shut Down", action = "shutdown"}
  }
  
  for _, item in ipairs(items) do
    gpu.set(menuX + 2, menuY + item.y, item.text)
  end
  
  -- Separators
  gpu.setForeground(COLORS.btnShadow)
  for i = 0, menuW - 1 do
    gpu.set(menuX + i, menuY + 6, "─")
    gpu.set(menuX + i, menuY + 10, "─")
  end
  
  startMenuOpen = true
  return items, menuX, menuY
end

-- Window Management
local function createWindow(title, width, height, programName)
  local program, err = loadProgram(programName)
  if not program then
    -- Show error window
    local errorWin = {
      title = "Error",
      x = math.floor((w - 40) / 2),
      y = math.floor((h - 10) / 2),
      w = 40,
      h = 10,
      error = err or "Unknown error"
    }
    
    function errorWin:draw(gpu, x, y, w, h)
      gpu.setBackground(COLORS.windowBg)
      gpu.setForeground(COLORS.error)
      gpu.set(x + 2, y + 2, "Failed to load program:")
      gpu.setForeground(COLORS.black)
      local errMsg = self.error:sub(1, w - 4)
      gpu.set(x + 2, y + 4, errMsg)
    end
    
    table.insert(activeWindows, errorWin)
    focusedWindow = #activeWindows
    return errorWin
  end
  
  local winX = math.floor((w - width) / 2) + #activeWindows * 2
  local winY = math.floor((h - height) / 2) + #activeWindows * 2
  
  if winY + height > h - 1 then winY = 3 end
  if winX + width > w then winX = 3 end
  
  local win = {
    title = title,
    x = winX,
    y = winY,
    w = width,
    h = height,
    program = program
  }
  
  if program and program.init then
    local ok, err = pcall(program.init, win)
    if not ok then
      win.error = "Init error: " .. tostring(err)
    end
  end
  
  function win:draw(gpu, x, y, w, h)
    if self.error then
      gpu.setBackground(COLORS.windowBg)
      gpu.setForeground(COLORS.error)
      gpu.set(x + 2, y + 2, "Error:")
      gpu.setForeground(COLORS.black)
      gpu.set(x + 2, y + 3, self.error:sub(1, w - 4))
    elseif self.program and self.program.draw then
      self.program.draw(self, gpu, x, y, w, h)
    end
  end
  
  function win:click(x, y, button)
    if self.program and self.program.click then
      local ok, result = pcall(self.program.click, self, x, y, button)
      if ok then
        return result
      end
    end
    return false
  end
  
  function win:key(char, code)
    if self.program and self.program.key then
      local ok, result = pcall(self.program.key, self, char, code)
      if ok then
        return result
      end
    end
    return false
  end
  
  table.insert(activeWindows, win)
  focusedWindow = #activeWindows
  return win
end

local function closeWindow(index)
  if activeWindows[index] then
    table.remove(activeWindows, index)
    if focusedWindow == index then
      focusedWindow = #activeWindows
    elseif focusedWindow > index then
      focusedWindow = focusedWindow - 1
    end
  end
end

local function focusWindow(index)
  if index and activeWindows[index] then
    local win = table.remove(activeWindows, index)
    table.insert(activeWindows, win)
    focusedWindow = #activeWindows
  end
end

-- Event Handlers
local function checkIconClick(x, y)
  for i, icon in ipairs(ICONS) do
    if x >= icon.x and x < icon.x + icon.w and
       y >= icon.y and y < icon.y + icon.h and y < h - 1 then
      return i
    end
  end
  return nil
end

local function checkStartButton(x, y)
  return y == h and x >= 2 and x <= 10
end

local function checkWindowClick(x, y)
  for i = #activeWindows, 1, -1 do
    local win = activeWindows[i]
    if x >= win.x and x < win.x + win.w and
       y >= win.y and y < win.y + win.h then
      return i, win
    end
  end
  return nil, nil
end

local function checkStartMenuClick(x, y)
  if not startMenuOpen then return nil end
  local items, menuX, menuY = drawStartMenu()
  startMenuOpen = false
  startMenuOpen = true
  
  for _, item in ipairs(items) do
    if y == menuY + item.y and x >= menuX and x < menuX + 28 then
      return item.action
    end
  end
  return nil
end

local function checkTaskbarWindowClick(x, y)
  if y ~= h then return nil end
  local btnX = 14
  for i, win in ipairs(activeWindows) do
    if x >= btnX and x < btnX + 15 then
      return i
    end
    btnX = btnX + 16
  end
  return nil
end

local function executeIconAction(program)
  local windowSizes = {
    calculator = {40, 22},
    notepad = {60, 20},
    settings = {50, 18},
    mycomputer = {55, 16}
  }
  
  local size = windowSizes[program] or {50, 20}
  local title = program:sub(1, 1):upper() .. program:sub(2)
  
  createWindow(title, size[1], size[2], program)
  redrawAll()
end

local function executeMenuAction(action)
  if action == "shutdown" then
    gpu.setBackground(COLORS.black)
    gpu.setForeground(COLORS.white)
    gpu.fill(1, 1, w, h, " ")
    gpu.set(math.floor(w/2) - 10, math.floor(h/2), "Shutting down...")
    os.sleep(1)
    computer.shutdown()
  elseif action == "settings" then
    executeIconAction("settings")
  elseif action == "programs" then
    executeIconAction("calculator")
  end
  startMenuOpen = false
  redrawAll()
end

local function updateClock()
  if computer.uptime() - clockTimer > 30 then
    clockTimer = computer.uptime()
    gpu.setBackground(COLORS.taskbar)
    gpu.setForeground(COLORS.black)
    local time = os.date("%H:%M")
    gpu.set(w - 6, h, time)
  end
end

-- Main Loop
local function main()
  drawDesktop()
  
  while true do
    local eventData = {event.pull(0.5)}
    local eventType = eventData[1]
    
    updateClock()
    
    if eventType == "touch" or eventType == "drag" then
      local _, _, x, y, button = table.unpack(eventData)
      
      if eventType == "touch" then
        if startMenuOpen then
          local action = checkStartMenuClick(x, y)
          if action then
            executeMenuAction(action)
          else
            startMenuOpen = false
            redrawAll()
          end
        elseif checkStartButton(x, y) then
          startMenuOpen = not startMenuOpen
          redrawAll()
        else
          local winIndex, win = checkWindowClick(x, y)
          
          if winIndex then
            focusWindow(winIndex)
            
            -- Close button
            if y == win.y and x >= win.x + win.w - 2 and x <= win.x + win.w - 1 then
              closeWindow(#activeWindows)
              redrawAll()
            -- Title bar (drag)
            elseif y == win.y and x >= win.x and x < win.x + win.w - 6 then
              dragWindow = win
              dragOffsetX = x - win.x
              dragOffsetY = y - win.y
            -- Content area
            else
              local relX = x - win.x - 1
              local relY = y - win.y - 2
              if win.click then
                local needRedraw = win:click(relX, relY, button)
                if needRedraw then redrawAll() end
              end
            end
            
            redrawAll()
          else
            local taskWin = checkTaskbarWindowClick(x, y)
            if taskWin then
              focusWindow(taskWin)
              redrawAll()
            else
              local iconIndex = checkIconClick(x, y)
              if iconIndex then
                if selectedIcon == iconIndex then
                  executeIconAction(ICONS[iconIndex].program)
                  selectedIcon = nil
                else
                  selectedIcon = iconIndex
                  redrawAll()
                end
              else
                selectedIcon = nil
                redrawAll()
              end
            end
          end
        end
      elseif eventType == "drag" and dragWindow then
        dragWindow.x = x - dragOffsetX
        dragWindow.y = y - dragOffsetY
        
        -- Keep window on screen
        if dragWindow.x < 0 then dragWindow.x = 0 end
        if dragWindow.y < 1 then dragWindow.y = 1 end
        if dragWindow.x + dragWindow.w > w then dragWindow.x = w - dragWindow.w end
        if dragWindow.y + dragWindow.h > h - 1 then dragWindow.y = h - 1 - dragWindow.h end
        
        redrawAll()
      end
    elseif eventType == "drop" then
      dragWindow = nil
    elseif eventType == "key_down" then
      local _, _, char, code = table.unpack(eventData)
      
      if code == 31 then -- S key - Start menu
        startMenuOpen = not startMenuOpen
        redrawAll()
      elseif code == 45 then -- X key - Shutdown
        executeMenuAction("shutdown")
      elseif focusedWindow and activeWindows[focusedWindow] then
        local win = activeWindows[focusedWindow]
        if win.key then
          local needRedraw = win:key(char, code)
          if needRedraw then redrawAll() end
        end
      end
    end
  end
end

-- Запуск з обробкою помилок
local ok, err = pcall(main)
if not ok then
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFF0000)
  gpu.fill(1, 1, w, h, " ")
  gpu.set(2, 2, "Desktop Error:")
  gpu.set(2, 3, tostring(err))
  gpu.set(2, 5, "Press any key to shutdown")
  event.pull("key_down")
  computer.shutdown()
end