-- ==========================================================
-- FixOS 3.2.4 - system/programs/notepad.lua
-- NEW:
--   - Open files from Explorer
--   - Save button with dialog
--   - Save As... to choose path
--   - Shows current filename in status bar
-- ==========================================================

local notepad = {}

function notepad.init(win, initData)
    win.lines       = {""}
    win.cursorX     = 0
    win.cursorY     = 0
    win.scrollY     = 0
    win.filepath    = nil
    win.modified    = false
    win.saveDialog  = false
    win.saveInput   = ""
    win.elements    = {}
    win._ui         = nil
    
    -- Load file if provided
    if initData and initData.filepath then
        notepad.loadFile(win, initData.filepath)
    end
end

function notepad.loadFile(win, path)
    local fs = component.proxy(computer.getBootAddress())
    if not fs.exists(path) then
        win.lines = {"[Error] File not found: " .. path}
        return
    end
    
    local h = fs.open(path, "r")
    if not h then
        win.lines = {"[Error] Cannot open file"}
        return
    end
    
    win.lines = {}
    repeat
        local chunk = fs.read(h, math.huge)
        if chunk then
            for line in (chunk.."\n"):gmatch("([^\n]*)\n") do
                table.insert(win.lines, line)
            end
        end
    until not chunk
    fs.close(h)
    
    if #win.lines == 0 then win.lines = {""} end
    
    win.filepath = path
    win.modified = false
    win.cursorX  = 0
    win.cursorY  = 0
    win.scrollY  = 0
end

function notepad.saveFile(win, path)
    local fs = component.proxy(computer.getBootAddress())
    
    -- Create parent directories
    local dir = path:match("(.+)/[^/]+$")
    if dir then
        local current = ""
        for part in dir:gmatch("[^/]+") do
            current = current .. "/" .. part
            if not fs.exists(current) then
                pcall(fs.makeDirectory, current)
            end
        end
    end
    
    -- Write file
    local h = fs.open(path, "w")
    if not h then
        win.statusMsg = "Error: Cannot save file"
        return false
    end
    
    for i, line in ipairs(win.lines) do
        fs.write(h, line)
        if i < #win.lines then fs.write(h, "\n") end
    end
    fs.close(h)
    
    win.filepath = path
    win.modified = false
    win.statusMsg = "Saved: " .. path
    return true
end

function notepad.draw(win, gpu, cx, cy, cw, ch)
    if not win._ui then
        win._ui = dofile("/system/ui.lua")
        win._ui.init(gpu)
    end
    local UI = win._ui
    local T  = UI.Theme
    
    gpu.setBackground(T.surface)
    gpu.fill(cx, cy, cw, ch, " ")
    
    win.elements = {}
    
    -- Save dialog
    if win.saveDialog then
        local dw, dh = math.min(50, cw - 4), 8
        local dx = cx + math.floor((cw - dw) / 2)
        local dy = cy + math.floor((ch - dh) / 2)
        
        -- Dialog background
        gpu.setBackground(T.surfaceAlt)
        gpu.fill(dx, dy, dw, dh, " ")
        
        -- Border
        gpu.setForeground(T.borderSubtle); gpu.setBackground(T.surfaceAlt)
        for col = 0, dw - 1 do
            gpu.set(dx + col, dy, "\xE2\x94\x80")
            gpu.set(dx + col, dy + dh - 1, "\xE2\x94\x80")
        end
        for row = 1, dh - 2 do
            gpu.set(dx, dy + row, "\xE2\x94\x82")
            gpu.set(dx + dw - 1, dy + row, "\xE2\x94\x82")
        end
        
        -- Title
        gpu.setBackground(T.accent); gpu.fill(dx, dy, dw, 1, " ")
        UI.centerText(dx, dy, dw, "Save File", T.textOnAccent, T.accent)
        
        -- Prompt
        gpu.setForeground(T.textPrimary); gpu.setBackground(T.surfaceAlt)
        gpu.set(dx + 2, dy + 2, "Enter filename:")
        
        -- Input box
        gpu.setBackground(T.surfaceInset)
        gpu.fill(dx + 2, dy + 3, dw - 4, 1, " ")
        gpu.setForeground(T.textPrimary)
        local displayInput = win.saveInput
        if #displayInput > dw - 6 then
            displayInput = "..." .. displayInput:sub(-(dw - 9))
        end
        gpu.set(dx + 3, dy + 3, displayInput)
        
        -- Cursor
        local cursorX = dx + 3 + #displayInput
        if cursorX < dx + dw - 3 then
            gpu.setBackground(T.textPrimary); gpu.setForeground(T.surfaceInset)
            gpu.set(cursorX, dy + 3, " ")
        end
        
        -- Buttons
        local btnSave = UI.drawButton(dx + 2, dy + 5, math.floor(dw/2) - 3, 2, "Save", "accent", true)
        btnSave.action = "dialog_save"
        table.insert(win.elements, btnSave)
        
        local btnCancel = UI.drawButton(dx + math.floor(dw/2) + 1, dy + 5, math.floor(dw/2) - 3, 2, "Cancel", "secondary", true)
        btnCancel.action = "dialog_cancel"
        table.insert(win.elements, btnCancel)
        
        return
    end
    
    -- Normal editor view
    -- Toolbar
    gpu.setBackground(T.surfaceAlt)
    gpu.fill(cx, cy, cw, 1, " ")
    
    local btnSave = UI.drawButton(cx + 1, cy, 8, 1, "[Save]", win.modified and "accent" or "secondary", true)
    btnSave.action = "save"
    table.insert(win.elements, btnSave)
    
    local btnSaveAs = UI.drawButton(cx + 10, cy, 12, 1, "[Save As...]", "secondary", true)
    btnSaveAs.action = "saveas"
    table.insert(win.elements, btnSaveAs)
    
    -- Text area
    local textY = cy + 1
    local textH = ch - 2
    
    local visibleLines = textH
    local maxScroll = math.max(0, #win.lines - visibleLines)
    if win.scrollY > maxScroll then win.scrollY = maxScroll end
    
    gpu.setBackground(T.surface)
    for row = 0, visibleLines - 1 do
        local lineIdx = win.scrollY + row + 1
        local line = win.lines[lineIdx]
        if line then
            local y = textY + row
            gpu.setForeground(T.textPrimary); gpu.setBackground(T.surface)
            gpu.set(cx, y, line:sub(1, cw))
            
            -- Cursor
            if lineIdx - 1 == win.cursorY and win.cursorX <= #line then
                local cursorCol = cx + win.cursorX
                if cursorCol < cx + cw then
                    local char = line:sub(win.cursorX + 1, win.cursorX + 1)
                    if char == "" then char = " " end
                    gpu.setBackground(T.textPrimary); gpu.setForeground(T.surface)
                    gpu.set(cursorCol, y, char)
                end
            end
        end
    end
    
    -- Status bar
    local statusY = cy + ch - 1
    gpu.setBackground(T.surfaceInset)
    gpu.fill(cx, statusY, cw, 1, " ")
    gpu.setForeground(T.textSecondary)
    
    local status = ""
    if win.filepath then
        status = win.filepath
    else
        status = "[Untitled]"
    end
    if win.modified then status = status .. " *" end
    status = status .. "  |  Ln " .. (win.cursorY + 1) .. ", Col " .. (win.cursorX + 1)
    
    if win.statusMsg then
        status = win.statusMsg .. "  |  " .. status
    end
    
    gpu.set(cx + 1, statusY, UI.truncate(status, cw - 2))
end

function notepad.click(win, clickX, clickY, button)
    if not win._ui then return false end
    local UI = win._ui
    
    for _, elem in ipairs(win.elements) do
        if UI.hitTest(elem, clickX, clickY) then
            if elem.action == "save" then
                if win.filepath then
                    notepad.saveFile(win, win.filepath)
                else
                    -- Show save dialog
                    win.saveDialog = true
                    win.saveInput = "/"
                end
                return true
                
            elseif elem.action == "saveas" then
                win.saveDialog = true
                win.saveInput = win.filepath or "/untitled.txt"
                return true
                
            elseif elem.action == "dialog_save" then
                if #win.saveInput > 0 then
                    notepad.saveFile(win, win.saveInput)
                    win.saveDialog = false
                end
                return true
                
            elseif elem.action == "dialog_cancel" then
                win.saveDialog = false
                return true
            end
        end
    end
    
    return false
end

function notepad.key(win, char, code)
    win.statusMsg = nil
    
    -- Save dialog input
    if win.saveDialog then
        if code == 28 then -- Enter
            if #win.saveInput > 0 then
                notepad.saveFile(win, win.saveInput)
                win.saveDialog = false
            end
            return true
        elseif code == 1 then -- Escape
            win.saveDialog = false
            return true
        elseif code == 14 then -- Backspace
            if #win.saveInput > 0 then
                win.saveInput = win.saveInput:sub(1, -2)
            end
            return true
        elseif char and char >= 32 and char <= 126 then
            win.saveInput = win.saveInput .. string.char(char)
            return true
        end
        return false
    end
    
    -- Normal editing
    if code == 28 then -- Enter
        local currentLine = win.lines[win.cursorY + 1]
        local before = currentLine:sub(1, win.cursorX)
        local after = currentLine:sub(win.cursorX + 1)
        win.lines[win.cursorY + 1] = before
        table.insert(win.lines, win.cursorY + 2, after)
        win.cursorY = win.cursorY + 1
        win.cursorX = 0
        win.modified = true
        
        local visibleLines = win._ch - 2
        if win.cursorY > win.scrollY + visibleLines - 1 then
            win.scrollY = win.scrollY + 1
        end
        return true
        
    elseif code == 14 then -- Backspace
        if win.cursorX > 0 then
            local line = win.lines[win.cursorY + 1]
            win.lines[win.cursorY + 1] = line:sub(1, win.cursorX - 1) .. line:sub(win.cursorX + 1)
            win.cursorX = win.cursorX - 1
            win.modified = true
        elseif win.cursorY > 0 then
            local prevLine = win.lines[win.cursorY]
            local currLine = win.lines[win.cursorY + 1]
            win.cursorX = #prevLine
            win.lines[win.cursorY] = prevLine .. currLine
            table.remove(win.lines, win.cursorY + 1)
            win.cursorY = win.cursorY - 1
            win.modified = true
        end
        return true
        
    elseif code == 200 then -- Up
        if win.cursorY > 0 then
            win.cursorY = win.cursorY - 1
            if win.cursorY < win.scrollY then win.scrollY = win.scrollY - 1 end
            local newLine = win.lines[win.cursorY + 1]
            if win.cursorX > #newLine then win.cursorX = #newLine end
        end
        return true
        
    elseif code == 208 then -- Down
        if win.cursorY < #win.lines - 1 then
            win.cursorY = win.cursorY + 1
            local visibleLines = win._ch - 2
            if win.cursorY > win.scrollY + visibleLines - 1 then
                win.scrollY = win.scrollY + 1
            end
            local newLine = win.lines[win.cursorY + 1]
            if win.cursorX > #newLine then win.cursorX = #newLine end
        end
        return true
        
    elseif code == 203 then -- Left
        if win.cursorX > 0 then
            win.cursorX = win.cursorX - 1
        elseif win.cursorY > 0 then
            win.cursorY = win.cursorY - 1
            win.cursorX = #win.lines[win.cursorY + 1]
        end
        return true
        
    elseif code == 205 then -- Right
        local line = win.lines[win.cursorY + 1]
        if win.cursorX < #line then
            win.cursorX = win.cursorX + 1
        elseif win.cursorY < #win.lines - 1 then
            win.cursorY = win.cursorY + 1
            win.cursorX = 0
        end
        return true
        
    elseif char and char >= 32 and char <= 126 then
        local line = win.lines[win.cursorY + 1]
        win.lines[win.cursorY + 1] = line:sub(1, win.cursorX) .. string.char(char) .. line:sub(win.cursorX + 1)
        win.cursorX = win.cursorX + 1
        win.modified = true
        return true
    end
    
    return false
end

function notepad.scroll(win, dir)
    if dir > 0 then
        win.scrollY = math.max(0, win.scrollY - 1)
    else
        win.scrollY = win.scrollY + 1
    end
    return true
end

return notepad