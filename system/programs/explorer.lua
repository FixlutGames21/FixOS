-- ==========================================================
-- FixOS 3.2.0 - system/programs/explorer.lua
-- IMPROVEMENTS:
--   - Vertical scrollbar (UI.drawScrollbar)
--   - Backspace = go up one level
--   - Single click = select, double click = open
--   - No emoji (ASCII icons only for OC compatibility)
--   - Better path bar and status bar
-- ==========================================================

local explorer = {}

local function L(key, ...) return (_G.Lang and _G.Lang.t(key, ...)) or key end

function explorer.init(win)
    win.currentPath  = "/"
    win.files        = {}
    win.selectedFile = 1
    win.scrollY      = 0
    win.lastClickIdx = -1   -- for double-click detection
    win.fs           = component.proxy(computer.getBootAddress())
    explorer.loadFiles(win)
end

function explorer.loadFiles(win)
    win.files = {}

    if win.currentPath ~= "/" then
        table.insert(win.files, {name="..", isDir=true, size=0})
    end

    local ok, listResult = pcall(function() return win.fs.list(win.currentPath) end)
    if ok and listResult then
        local items = {}
        if type(listResult) == "function" then
            for f in listResult do table.insert(items, f) end
        else
            items = listResult
        end
        for _, file in ipairs(items) do
            if file and file ~= "" and file ~= "." then
                local fullPath = win.currentPath
                if not fullPath:match("/$") then fullPath = fullPath .. "/" end
                fullPath = fullPath .. file

                local isDir, size = false, 0
                local ok2, r2 = pcall(win.fs.isDirectory, fullPath)
                if ok2 then isDir = r2 end
                if not isDir then
                    local ok3, r3 = pcall(win.fs.size, fullPath)
                    if ok3 then size = r3 end
                end
                table.insert(win.files, {name=file, isDir=isDir, size=size})
            end
        end
    end

    table.sort(win.files, function(a, b)
        if a.name == ".." then return true end
        if b.name == ".." then return false end
        if a.isDir ~= b.isDir then return a.isDir end
        return a.name:lower() < b.name:lower()
    end)

    win.selectedFile = 1
    win.scrollY      = 0
    win.lastClickIdx = -1
end

local function formatSize(bytes)
    if bytes >= 1024*1024 then return string.format("%.1fM", bytes/(1024*1024))
    elseif bytes >= 1024  then return string.format("%.1fK", bytes/1024)
    else                       return bytes .. "B"
    end
end

function explorer.draw(win, gpu, x, y, w, h)
    local UI = dofile and pcall(dofile, "/system/ui.lua") and true
    -- Use cached UI from win
    if not win._ui then
        win._ui = dofile("/system/ui.lua")
        win._ui.init(gpu)
    end
    local SB_W = 1  -- scrollbar width

    -- Background
    gpu.setBackground(0xFFFFFF)
    gpu.fill(x, y, w, h, " ")

    -- Path bar
    gpu.setBackground(0xF0F0F0)
    gpu.fill(x, y, w, 1, " ")
    gpu.setForeground(0x0078D7)
    local pathText = "[/] " .. win.currentPath
    if #pathText > w - 2 then pathText = "..." .. pathText:sub(-(w-5)) end
    gpu.set(x + 1, y, pathText)

    -- Column headers
    gpu.setBackground(0xE8E8E8)
    gpu.setForeground(0x666666)
    gpu.fill(x, y + 1, w, 1, " ")
    gpu.set(x + 1, y + 1, L("explorer.name"))
    gpu.set(x + w - 8 - SB_W, y + 1, L("explorer.size"))

    -- File list
    local visibleLines = h - 3   -- path + header + status
    local listW        = w - SB_W

    for i = 0, visibleLines - 1 do
        local idx  = win.scrollY + i + 1
        local file = win.files[idx]
        if file then
            local lineY   = y + 2 + i
            local isSel   = (idx == win.selectedFile)

            if isSel then
                gpu.setBackground(0x0078D7); gpu.setForeground(0xFFFFFF)
            else
                gpu.setBackground(i % 2 == 0 and 0xFFFFFF or 0xFAFAFA)
                gpu.setForeground(0x1B1B1B)
            end
            gpu.fill(x, lineY, listW, 1, " ")

            -- Icon (ASCII only for OC compatibility)
            local icon
            if    file.name == ".."   then icon = "[^]"
            elseif file.isDir          then icon = "[D]"
            else                            icon = "[-]"
            end
            gpu.set(x + 1, lineY, icon)

            -- Name (truncated to fit)
            local maxNameW = listW - 12
            local name = file.name
            if file.isDir and file.name ~= ".." then name = name .. "/" end
            if #name > maxNameW then name = name:sub(1, maxNameW - 2) .. ".." end
            gpu.set(x + 5, lineY, name)

            -- Size (right-aligned, skip for dirs)
            if not file.isDir then
                local sz = formatSize(file.size)
                gpu.set(x + listW - #sz - 1, lineY, sz)
            end
        end
    end

    -- Scrollbar
    win._ui.drawScrollbar(x + w - SB_W, y + 2, visibleLines,
        #win.files, visibleLines, win.scrollY)

    -- Status bar
    gpu.setBackground(0xF0F0F0)
    gpu.setForeground(0x666666)
    gpu.fill(x, y + h - 1, w, 1, " ")
    local selFile = win.files[win.selectedFile]
    local status  = L("explorer.items", #win.files)
    if selFile and selFile.name ~= ".." then
        if selFile.isDir then
            status = status .. "  [D] " .. selFile.name
        else
            status = status .. "  " .. selFile.name .. "  " .. formatSize(selFile.size)
        end
    end
    gpu.set(x + 1, y + h - 1, status:sub(1, w - 2))
end

function explorer.click(win, clickX, clickY, button)
    -- Content area: y+2 (after path bar + header) to y+h-2 (before status)
    local fileAreaY = (win._cy or (win.y + 2)) + 2
    local visLines  = win.h - 3 - (win._ch and (win.h - 4 - win._ch) or 1)
    visLines = win._ch and (win._ch - 3) or (win.h - 7)

    if clickY < fileAreaY then return false end
    local relY   = clickY - fileAreaY
    local idx    = win.scrollY + relY + 1

    if idx < 1 or idx > #win.files then return false end

    if win.selectedFile == idx then
        -- Double click (click same item twice)
        explorer.openFile(win, idx)
    else
        win.selectedFile = idx
    end
    win.lastClickIdx = idx
    return true
end

function explorer.openFile(win, idx)
    local file = win.files[idx]
    if not file then return end

    if file.name == ".." then
        local path = win.currentPath
        if path ~= "/" then
            win.currentPath = path:match("(.+)/[^/]*$") or "/"
            explorer.loadFiles(win)
        end

    elseif file.isDir then
        local sep = win.currentPath:match("/$") and "" or "/"
        win.currentPath = win.currentPath .. sep .. file.name
        explorer.loadFiles(win)
    end
end

function explorer.key(win, char, code)
    -- Enter = open selected
    if code == 28 then
        explorer.openFile(win, win.selectedFile); return true

    -- Backspace = go up
    elseif code == 14 then
        if win.currentPath ~= "/" then
            win.currentPath = win.currentPath:match("(.+)/[^/]*$") or "/"
            explorer.loadFiles(win); return true
        end

    -- Up arrow
    elseif code == 200 then
        if win.selectedFile > 1 then
            win.selectedFile = win.selectedFile - 1
            if win.selectedFile <= win.scrollY then
                win.scrollY = math.max(0, win.selectedFile - 1)
            end
            return true
        end

    -- Down arrow
    elseif code == 208 then
        if win.selectedFile < #win.files then
            win.selectedFile = win.selectedFile + 1
            local vis = win._ch and (win._ch - 3) or 10
            if win.selectedFile > win.scrollY + vis then
                win.scrollY = win.selectedFile - vis
            end
            return true
        end
    end
    return false
end

function explorer.scroll(win, direction)
    local vis = win._ch and (win._ch - 3) or 10
    if direction > 0 then
        if win.scrollY > 0 then
            win.scrollY = win.scrollY - 1
            if win.selectedFile > win.scrollY + vis then
                win.selectedFile = win.scrollY + vis
            end
        end
    else
        local maxScroll = math.max(0, #win.files - vis)
        if win.scrollY < maxScroll then
            win.scrollY = win.scrollY + 1
            if win.selectedFile <= win.scrollY then
                win.selectedFile = win.scrollY + 1
            end
        end
    end
    return true
end

return explorer