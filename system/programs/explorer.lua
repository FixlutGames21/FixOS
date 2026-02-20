-- ==========================================================
-- FixOS 3.2.4 - system/programs/explorer.lua
-- NEW:
--   - Double-click files to open in Notepad
--   - "Open in Notepad" button for selected files
--   - Support for .txt, .lua, .cfg, .md files
-- ==========================================================

local explorer = {}

function explorer.init(win)
    win.cwd          = "/"
    win.files        = {}
    win.selectedFile = nil
    win.selectedIdx  = nil
    win.scrollY      = 0
    win.lastClickIdx = nil
    win.lastClickTime = 0
    win.elements     = {}
    win._ui          = nil
    explorer.refresh(win)
end

function explorer.refresh(win)
    local fs = component.proxy(computer.getBootAddress())
    win.files = {}
    
    -- Add parent directory if not at root
    if win.cwd ~= "/" then
        table.insert(win.files, {name="..", isDir=true, size=0, path=win.cwd:match("^(.*)/[^/]+$") or "/"})
    end
    
    -- List files
    local ok, list = pcall(function() return fs.list(win.cwd) end)
    if ok and list then
        local entries = {}
        if type(list) == "function" then
            for item in list do entries[#entries+1] = item end
        else
            for _, item in ipairs(list) do entries[#entries+1] = item end
        end
        
        table.sort(entries)
        
        for _, name in ipairs(entries) do
            local path = win.cwd .. (win.cwd:match("/$") and "" or "/") .. name
            local isDir = pcall(function() return fs.isDirectory(path) end) and fs.isDirectory(path)
            local size = 0
            if not isDir then
                pcall(function() size = fs.size(path) or 0 end)
            end
            table.insert(win.files, {name=name, isDir=isDir, size=size, path=path})
        end
    end
end

local function formatSize(bytes)
    if bytes < 1024 then return bytes.."B"
    elseif bytes < 1024*1024 then return math.floor(bytes/1024).."K"
    else return math.floor(bytes/1024/1024).."M" end
end

local function canOpenInNotepad(filename)
    if not filename then return false end
    local ext = filename:match("%.([^%.]+)$")
    if not ext then return false end
    ext = ext:lower()
    return ext == "txt" or ext == "lua" or ext == "cfg" or ext == "md" or ext == "log"
end

function explorer.draw(win, gpu, cx, cy, cw, ch)
    if not win._ui then
        win._ui = dofile("/system/ui.lua")
        win._ui.init(gpu)
    end
    local UI = win._ui
    local T  = UI.Theme
    
    gpu.setBackground(T.surface)
    gpu.fill(cx, cy, cw, ch, " ")
    
    win.elements = {}
    
    -- Path bar
    gpu.setBackground(T.surfaceAlt)
    gpu.fill(cx, cy, cw, 1, " ")
    gpu.setForeground(T.accent); gpu.setBackground(T.surfaceAlt)
    local pathStr = "[/] " .. win.cwd
    gpu.set(cx + 1, cy, UI.truncate(pathStr, cw - 2))
    
    -- Column headers
    local headerY = cy + 1
    gpu.setBackground(T.surfaceInset)
    gpu.fill(cx, headerY, cw, 1, " ")
    gpu.setForeground(T.textSecondary); gpu.setBackground(T.surfaceInset)
    gpu.set(cx + 2, headerY, "Name")
    gpu.set(cx + cw - 10, headerY, "Size")
    
    -- File list area
    local listY = cy + 2
    local listH = ch - 4  -- Leave room for path, header, and action buttons
    local visibleFiles = math.floor(listH)
    
    local maxScroll = math.max(0, #win.files - visibleFiles)
    if win.scrollY > maxScroll then win.scrollY = maxScroll end
    
    for row = 0, visibleFiles - 1 do
        local idx = win.scrollY + row + 1
        local file = win.files[idx]
        if file then
            local y = listY + row
            local isSelected = (idx == win.selectedIdx)
            local bg = isSelected and T.accent or (row % 2 == 0 and T.surface or 0xFAFAFA)
            local fg = isSelected and T.textOnAccent or T.textPrimary
            
            gpu.setBackground(bg)
            gpu.fill(cx, y, cw - 1, 1, " ")
            gpu.setForeground(fg)
            
            -- Icon
            local icon = file.name == ".." and "[^]" or (file.isDir and "[D]" or "[-]")
            gpu.set(cx + 1, y, icon)
            
            -- Name
            local nameW = cw - 14
            gpu.set(cx + 5, y, UI.truncate(file.name, nameW))
            
            -- Size
            if not file.isDir and file.name ~= ".." then
                gpu.set(cx + cw - 10, y, formatSize(file.size))
            end
        end
    end
    
    -- Scrollbar
    UI.drawScrollbar(cx + cw - 1, listY, listH, math.max(listH, #win.files), listH, win.scrollY)
    
    -- Action buttons at bottom
    local btnY = cy + ch - 2
    gpu.setBackground(T.surfaceAlt)
    gpu.fill(cx, btnY, cw, 2, " ")
    
    if win.selectedFile and not win.selectedFile.isDir and canOpenInNotepad(win.selectedFile.name) then
        local btn = UI.drawButton(cx + 2, btnY, 18, 2, "Open in Notepad", "accent", true)
        btn.action = "open_notepad"
        table.insert(win.elements, btn)
    end
    
    -- Status bar
    local statusY = cy + ch - 1
    gpu.setBackground(T.surfaceInset)
    gpu.fill(cx, statusY, cw, 1, " ")
    gpu.setForeground(T.textSecondary)
    local status = #win.files .. " items"
    if win.selectedFile then
        status = status .. "  |  Selected: " .. win.selectedFile.name
    end
    gpu.set(cx + 1, statusY, UI.truncate(status, cw - 2))
end

function explorer.click(win, clickX, clickY, button)
    if not win._ui then return false end
    local UI = win._ui
    
    -- Check action buttons
    for _, elem in ipairs(win.elements) do
        if UI.hitTest(elem, clickX, clickY) then
            if elem.action == "open_notepad" and win.selectedFile then
                -- Open file in notepad
                if _G.createWindow then
                    _G.createWindow("notepad", {filepath = win.selectedFile.path})
                end
                return true
            end
        end
    end
    
    -- Check file list click
    local listY = win._cy + 2
    local listH = win._ch - 4
    
    if clickY >= listY and clickY < listY + listH then
        local row = clickY - listY
        local idx = win.scrollY + row + 1
        local file = win.files[idx]
        
        if file then
            local now = computer.uptime()
            local isDoubleClick = (win.lastClickIdx == idx) and (now - win.lastClickTime < 0.5)
            
            win.lastClickIdx = idx
            win.lastClickTime = now
            win.selectedIdx = idx
            win.selectedFile = file
            
            if isDoubleClick then
                -- Double-click: navigate or open
                if file.isDir or file.name == ".." then
                    win.cwd = file.path
                    explorer.refresh(win)
                    win.scrollY = 0
                    win.selectedIdx = nil
                    win.selectedFile = nil
                elseif canOpenInNotepad(file.name) then
                    -- Open in notepad
                    if _G.createWindow then
                        _G.createWindow("notepad", {filepath = file.path})
                    end
                end
            end
            
            return true
        end
    end
    
    return false
end

function explorer.key(win, char, code)
    -- Backspace: go up
    if code == 14 and win.cwd ~= "/" then
        win.cwd = win.cwd:match("^(.*)/[^/]+$") or "/"
        explorer.refresh(win)
        win.scrollY = 0
        return true
    end
    
    -- Arrow keys
    if code == 200 then -- Up
        if win.selectedIdx and win.selectedIdx > 1 then
            win.selectedIdx = win.selectedIdx - 1
            win.selectedFile = win.files[win.selectedIdx]
            if win.selectedIdx <= win.scrollY then
                win.scrollY = math.max(0, win.scrollY - 1)
            end
        end
        return true
    elseif code == 208 then -- Down
        if win.selectedIdx and win.selectedIdx < #win.files then
            win.selectedIdx = win.selectedIdx + 1
            win.selectedFile = win.files[win.selectedIdx]
            local visibleFiles = math.floor(win._ch - 4)
            if win.selectedIdx > win.scrollY + visibleFiles then
                win.scrollY = win.scrollY + 1
            end
        elseif not win.selectedIdx and #win.files > 0 then
            win.selectedIdx = 1
            win.selectedFile = win.files[1]
        end
        return true
    end
    
    -- Enter: open selected
    if code == 28 and win.selectedFile then
        if win.selectedFile.isDir or win.selectedFile.name == ".." then
            win.cwd = win.selectedFile.path
            explorer.refresh(win)
            win.scrollY = 0
            win.selectedIdx = nil
            win.selectedFile = nil
        elseif canOpenInNotepad(win.selectedFile.name) then
            if _G.createWindow then
                _G.createWindow("notepad", {filepath = win.selectedFile.path})
            end
        end
        return true
    end
    
    return false
end

function explorer.scroll(win, dir)
    if dir > 0 then
        win.scrollY = math.max(0, win.scrollY - 1)
    else
        win.scrollY = win.scrollY + 1
    end
    return true
end

return explorer