-- ==============================================
-- FixOS 3.1.0 - File Explorer (WIN10 STYLE)
-- ==============================================

local explorer = {}

function explorer.init(win)
  win.currentPath = "/"
  win.files = {}
  win.selectedFile = 1
  win.scrollY = 0
  win.fs = component.proxy(computer.getBootAddress())
  explorer.loadFiles(win)
end

function explorer.loadFiles(win)
  win.files = {}
  
  if win.currentPath ~= "/" then
    table.insert(win.files, {name = "..", isDir = true, size = 0})
  end
  
  local ok, listFunc = pcall(function() return win.fs.list(win.currentPath) end)
  if ok and listFunc then
    for file in listFunc do
      if file and file ~= "" and file ~= "." then
        local fullPath = win.currentPath
        if not fullPath:match("/$") then fullPath = fullPath .. "/" end
        fullPath = fullPath .. file
        
        local isDir = false
        local size = 0
        
        local ok2, isDirResult = pcall(win.fs.isDirectory, fullPath)
        if ok2 then isDir = isDirResult end
        
        if not isDir then
          local ok3, sizeResult = pcall(win.fs.size, fullPath)
          if ok3 then size = sizeResult end
        end
        
        table.insert(win.files, {name = file, isDir = isDir, size = size})
      end
    end
  end
  
  table.sort(win.files, function(a, b)
    if a.name == ".." then return true end
    if b.name == ".." then return false end
    if a.isDir ~= b.isDir then return a.isDir end
    return a.name < b.name
  end)
  
  win.selectedFile = 1
  win.scrollY = 0
end

function explorer.draw(win, gpu, x, y, w, h)
  gpu.setBackground(0xFFFFFF)
  gpu.fill(x, y, w, h, " ")
  
  -- Path bar (flat)
  gpu.setBackground(0xF0F0F0)
  gpu.fill(x, y, w, 1, " ")
  
  gpu.setForeground(0x0078D7)
  local pathText = "📁 " .. win.currentPath
  if #pathText > w - 2 then
    pathText = "..." .. pathText:sub(-(w - 5))
  end
  gpu.set(x + 1, y, pathText)
  
  -- Headers (flat)
  gpu.setBackground(0xE0E0E0)
  gpu.setForeground(0x666666)
  gpu.fill(x, y + 1, w, 1, " ")
  gpu.set(x + 1, y + 1, "Name")
  gpu.set(x + w - 12, y + 1, "Size")
  
  -- File list
  gpu.setBackground(0xFFFFFF)
  
  local visibleLines = h - 3
  local startIdx = win.scrollY + 1
  
  for i = 0, visibleLines - 1 do
    local fileIdx = startIdx + i
    local file = win.files[fileIdx]
    
    if file then
      local lineY = y + 2 + i
      local isSelected = (fileIdx == win.selectedFile)
      
      if isSelected then
        gpu.setBackground(0x0078D7)
        gpu.setForeground(0xFFFFFF)
        gpu.fill(x, lineY, w, 1, " ")
      else
        gpu.setBackground(0xFFFFFF)
        gpu.setForeground(0x000000)
      end
      
      local icon = file.isDir and "📁" or "📄"
      if file.name == ".." then icon = "⬆" end
      
      gpu.set(x + 1, lineY, icon)
      
      local name = file.name
      if file.isDir and file.name ~= ".." then name = name .. "/" end
      
      if #name > w - 15 then
        name = name:sub(1, w - 18) .. "..."
      end
      
      gpu.set(x + 3, lineY, name)
      
      if not file.isDir and file.name ~= ".." then
        local sizeText = ""
        if file.size < 1024 then
          sizeText = file.size .. "B"
        elseif file.size < 1024 * 1024 then
          sizeText = string.format("%.1fK", file.size / 1024)
        else
          sizeText = string.format("%.1fM", file.size / (1024 * 1024))
        end
        
        gpu.set(x + w - #sizeText - 1, lineY, sizeText)
      end
    end
  end
  
  -- Status bar (flat)
  gpu.setBackground(0xF0F0F0)
  gpu.setForeground(0x666666)
  gpu.fill(x, y + h - 1, w, 1, " ")
  
  local statusText = string.format("%d items", #win.files)
  gpu.set(x + 1, y + h - 1, statusText)
end

function explorer.click(win, clickX, clickY, button)
  local contentY = win.y + 2 + 2
  
  if clickY >= contentY and clickY < win.y + win.h - 1 then
    local relY = clickY - contentY
    local fileIdx = win.scrollY + relY + 1
    
    if win.files[fileIdx] then
      if win.selectedFile == fileIdx and button == 0 then
        explorer.openFile(win, fileIdx)
        return true
      else
        win.selectedFile = fileIdx
        return true
      end
    end
  end
  
  return false
end

function explorer.openFile(win, fileIdx)
  local file = win.files[fileIdx]
  if not file then return end
  
  if file.name == ".." then
    local path = win.currentPath
    if path ~= "/" then
      path = path:match("(.+)/[^/]*$") or "/"
      win.currentPath = path
      explorer.loadFiles(win)
    end
    
  elseif file.isDir then
    local newPath = win.currentPath
    if not newPath:match("/$") then newPath = newPath .. "/" end
    newPath = newPath .. file.name
    
    win.currentPath = newPath
    explorer.loadFiles(win)
  end
end

function explorer.key(win, char, code)
  if code == 28 then
    explorer.openFile(win, win.selectedFile)
    return true
    
  elseif code == 200 then
    if win.selectedFile > 1 then
      win.selectedFile = win.selectedFile - 1
      if win.selectedFile <= win.scrollY then
        win.scrollY = math.max(0, win.selectedFile - 1)
      end
      return true
    end
    
  elseif code == 208 then
    if win.selectedFile < #win.files then
      win.selectedFile = win.selectedFile + 1
      local visibleLines = win.h - 6
      if win.selectedFile > win.scrollY + visibleLines then
        win.scrollY = win.selectedFile - visibleLines
      end
      return true
    end
  end
  
  return false
end

function explorer.scroll(win, direction)
  if direction > 0 then
    if win.selectedFile > 1 then
      win.selectedFile = win.selectedFile - 1
      if win.selectedFile <= win.scrollY then
        win.scrollY = math.max(0, win.scrollY - 1)
      end
    end
  else
    if win.selectedFile < #win.files then
      win.selectedFile = win.selectedFile + 1
      local visibleLines = win.h - 6
      if win.selectedFile > win.scrollY + visibleLines then
        win.scrollY = win.scrollY + 1
      end
    end
  end
  return true
end

return explorer
