-- ==========================================================
-- FixOS 4.0.1 - system/programs/explorer.lua
-- FIX 4.0.1:
--   - listDir(): proxy.isDirectory() calls inside table.sort's
--     comparator were NOT wrapped in pcall.  Any filesystem
--     error during sorting crashed the entire Explorer.
--     Fixed: each isDirectory call is now protected by pcall,
--     defaulting to false on error.
-- ==========================================================

local explorer = {}

local SIDEBAR_W = 14

local EDITABLE = {
    lua=true, txt=true, cfg=true, md=true,
    log=true, json=true, ini=true, conf=true, lang=true,
}

local FILE_ICONS = {
    lua="[LUA]", txt="[TXT]", cfg="[CFG]", md="[MD] ",
    log="[LOG]", json="[JSN]", png="[PNG]",
    ["default"]="[---]",
}

local function getExt(name)
    return (name:match("%.([^%.]+)$") or ""):lower()
end

local function fileIcon(name, isDir)
    if isDir then return "[DIR]" end
    return FILE_ICONS[getExt(name)] or FILE_ICONS["default"]
end

-- ============================================================
-- FILESYSTEM HELPERS
-- ============================================================
local function getAllDrives()
    local drives    = {}
    local bootAddr  = computer.getBootAddress()

    for addr in component.list("filesystem") do
        local proxy = component.proxy(addr)
        if proxy then
            local lbl, ro, tot, used = "", false, 0, 0
            pcall(function() lbl  = proxy.getLabel() or "" end)
            pcall(function() ro   = proxy.isReadOnly() end)
            pcall(function() tot  = proxy.spaceTotal() or 0 end)
            pcall(function() used = proxy.spaceUsed()  or 0 end)
            if lbl == "" then lbl = addr:sub(1, 6) end
            table.insert(drives, {
                address  = addr,
                label    = lbl,
                proxy    = proxy,
                readOnly = ro,
                total    = tot,
                used     = used,
                isBoot   = (addr == bootAddr),
            })
        end
    end

    table.sort(drives, function(a, b)
        if a.isBoot ~= b.isBoot then return a.isBoot end
        return a.total > b.total
    end)
    return drives
end

local function listDir(proxy, path)
    local entries = {}
    local ok, list = pcall(function() return proxy.list(path) end)
    if not ok or not list then return entries, "Помилка читання каталогу" end

    if type(list) == "function" then
        for item in list do entries[#entries+1] = item end
    else
        for _, item in ipairs(list) do entries[#entries+1] = item end
    end

    -- FIX: proxy.isDirectory() is called inside a sort comparator.
    -- If it raises (e.g. permission error, broken FS), the sort
    -- itself crashes.  Use pcall and default to false on error.
    table.sort(entries, function(a, b)
        local aPath = path .. (path:match("/$") and "" or "/") .. a
        local bPath = path .. (path:match("/$") and "" or "/") .. b
        local aDir, bDir = false, false
        pcall(function() aDir = proxy.isDirectory(aPath) end)
        pcall(function() bDir = proxy.isDirectory(bPath) end)
        if aDir ~= bDir then return aDir end
        return a:lower() < b:lower()
    end)

    local result = {}

    if path ~= "/" then
        local parentPath = path:match("^(.*)/[^/]+$") or "/"
        table.insert(result, {name="..", path=parentPath, isDir=true, size=0})
    end

    for _, name in ipairs(entries) do
        local fullPath = path .. (path:match("/$") and "" or "/") .. name
        local isDir    = false
        local size     = 0
        pcall(function() isDir = proxy.isDirectory(fullPath) end)
        if not isDir then
            pcall(function() size = proxy.size(fullPath) or 0 end)
        end
        table.insert(result, {name=name, path=fullPath, isDir=isDir, size=size})
    end

    return result
end

local function formatSize(bytes)
    if bytes >= 1024*1024 then return string.format("%.1fM", bytes/(1024*1024))
    elseif bytes >= 1024  then return string.format("%.0fK", bytes/1024)
    else                       return bytes .. "B" end
end

-- ============================================================
-- INIT
-- ============================================================
function explorer.init(win)
    win.drives        = getAllDrives()
    win.driveIdx      = nil
    win.currentProxy  = nil
    win.cwd           = "/"
    win.files         = {}
    win.selIdx        = nil
    win.selFile       = nil
    win.scrollY       = 0
    win.driveScrollY  = 0
    win.lastClickIdx  = nil
    win.lastClickTime = 0
    win.elements      = {}
    win.errorMsg      = nil
    win._ui           = nil
    win._cx, win._cy, win._cw, win._ch = 0, 0, 0, 0

    if #win.drives > 0 then
        for i, d in ipairs(win.drives) do
            if d.isBoot then explorer.selectDrive(win, i); return end
        end
        explorer.selectDrive(win, 1)
    end
end

function explorer.selectDrive(win, idx)
    local d = win.drives[idx]
    if not d then return end
    win.driveIdx     = idx
    win.currentProxy = d.proxy
    win.cwd          = "/"
    win.selIdx       = nil
    win.selFile      = nil
    win.scrollY      = 0
    win.errorMsg     = nil
    explorer.refresh(win)
end

function explorer.refresh(win)
    if not win.currentProxy then return end
    win.drives = getAllDrives()
    local files, err = listDir(win.currentProxy, win.cwd)
    win.files    = files
    win.errorMsg = err
    if win.selFile then
        for i, f in ipairs(win.files) do
            if f.name == win.selFile.name then
                win.selIdx  = i
                win.selFile = f
                return
            end
        end
    end
    win.selIdx  = nil
    win.selFile = nil
end

-- ============================================================
-- DRAW
-- ============================================================
function explorer.draw(win, gpu, cx, cy, cw, ch)
    if not win._ui then
        win._ui = dofile("/system/ui.lua")
        win._ui.init(gpu)
    end
    local UI = win._ui
    local T  = UI.Theme

    win._cx, win._cy, win._cw, win._ch = cx, cy, cw, ch
    win.elements = {}

    gpu.setBackground(T.surface)
    gpu.fill(cx, cy, cw, ch, " ")

    -- Sidebar
    local sideX = cx
    local sideW = SIDEBAR_W
    local sideH = ch - 2

    gpu.setBackground(T.chromeMid)
    gpu.fill(sideX, cy, sideW, sideH, " ")

    gpu.setForeground(T.textOnDark); gpu.setBackground(T.chromeMid)
    gpu.set(sideX + 1, cy, "  ДИСКИ")

    for i, d in ipairs(win.drives) do
        local dy    = cy + 1 + (i - 1) * 3
        if dy + 2 >= cy + sideH then break end

        local isSelected = (i == win.driveIdx)
        local bg = isSelected and T.accent or T.chromeMid
        gpu.setBackground(bg)
        gpu.fill(sideX, dy, sideW, 3, " ")

        local diskIcon = d.isBoot and "[B]" or "[D]"
        gpu.setForeground(d.readOnly and T.textDisabled or T.textOnAccent)
        gpu.set(sideX + 1, dy,     diskIcon)
        gpu.set(sideX + 1, dy + 1, UI.truncate(d.label, sideW - 2))

        if d.total > 0 then
            local pct    = d.used / d.total
            local barW   = sideW - 2
            local filled = math.floor(barW * pct)
            local barBg  = isSelected and T.accentDark or T.chromeDark
            gpu.setBackground(barBg)
            gpu.fill(sideX + 1, dy + 2, barW, 1, " ")
            local barFg = pct > 0.9 and T.danger or T.success
            if filled > 0 then
                gpu.setBackground(barFg)
                gpu.fill(sideX + 1, dy + 2, filled, 1, " ")
            end
        end

        table.insert(win.elements, {
            x=sideX, y=dy, w=sideW, h=3,
            action="selectDrive", driveIdx=i
        })
    end

    gpu.setForeground(T.chromeBorder); gpu.setBackground(T.chromeMid)
    for row = cy, cy + sideH - 1 do
        gpu.set(sideX + sideW, row, "\xE2\x94\x82")
    end

    -- Main panel
    local mainX = cx + sideW + 1
    local mainW = cw - sideW - 1

    gpu.setBackground(T.surfaceAlt)
    gpu.fill(mainX, cy, mainW, 1, " ")
    gpu.setForeground(T.accent); gpu.setBackground(T.surfaceAlt)
    local driveLabel = win.drives[win.driveIdx] and win.drives[win.driveIdx].label or "?"
    local pathStr    = "[" .. driveLabel .. "] " .. win.cwd
    gpu.set(mainX + 1, cy, UI.truncate(pathStr, mainW - 2))

    local toolY = cy + 1
    gpu.setBackground(T.surfaceInset)
    gpu.fill(mainX, toolY, mainW, 1, " ")

    local bx = mainX + 1
    local function addBtn(label, action, enabled)
        if enabled == nil then enabled = true end
        local w = #label + 2
        if bx + w >= mainX + mainW then return end
        gpu.setBackground(enabled and T.accent or T.surfaceInset)
        gpu.setForeground(enabled and T.textOnAccent or T.textDisabled)
        gpu.set(bx, toolY, " " .. label .. " ")
        table.insert(win.elements, {x=bx, y=toolY, w=w, h=1, action=action, enabled=enabled})
        bx = bx + w + 1
    end

    addBtn("[^] Назад",     "goUp",       win.cwd ~= "/")
    addBtn("[+] Папка",     "newDir",     win.currentProxy and not (win.drives[win.driveIdx] and win.drives[win.driveIdx].readOnly))
    addBtn("[DEL] Видалити","deleteFile",  win.selFile ~= nil and win.selFile.name ~= "..")
    if win.selFile and not win.selFile.isDir and EDITABLE[getExt(win.selFile.name)] then
        addBtn("[N] Відкрити", "openNotepad", true)
    end

    local headerY = cy + 2
    gpu.setBackground(T.surfaceInset)
    gpu.fill(mainX, headerY, mainW, 1, " ")
    gpu.setForeground(T.textSecondary)
    gpu.set(mainX + 1, headerY, "Тип  Назва")
    gpu.set(mainX + mainW - 8, headerY, "Розмір")

    local listY = cy + 3
    local listH = ch - 5
    local visN  = listH

    local maxScroll = math.max(0, #win.files - visN)
    if win.scrollY > maxScroll then win.scrollY = maxScroll end

    for row = 0, visN - 1 do
        local idx  = win.scrollY + row + 1
        local file = win.files[idx]
        if not file then break end

        local fy     = listY + row
        local isSel  = (idx == win.selIdx)
        local rowBg  = isSel and T.accent or (row%2==0 and T.surface or T.surfaceAlt)
        local rowFg  = isSel and T.textOnAccent or T.textPrimary
        local iconFg = isSel and T.textOnAccent or (file.isDir and T.accent or T.textSecondary)

        gpu.setBackground(rowBg)
        gpu.fill(mainX, fy, mainW - 1, 1, " ")

        gpu.setForeground(iconFg)
        gpu.set(mainX + 1, fy, fileIcon(file.name, file.isDir))

        gpu.setForeground(rowFg)
        local nameW = mainW - 10
        gpu.set(mainX + 6, fy, UI.truncate(file.name, nameW))

        if not file.isDir and file.name ~= ".." then
            gpu.set(mainX + mainW - 8, fy, string.format("%6s", formatSize(file.size)))
        end

        table.insert(win.elements, {
            x=mainX, y=fy, w=mainW-1, h=1, action="fileClick", fileIdx=idx
        })
    end

    UI.drawScrollbar(mainX + mainW - 1, listY, listH,
        math.max(listH, #win.files), listH, win.scrollY)

    -- Status bar
    local statusY = cy + ch - 2
    gpu.setBackground(T.surfaceInset)
    gpu.fill(cx, statusY, cw, 2, " ")

    if win.drives[win.driveIdx] then
        local d    = win.drives[win.driveIdx]
        local free = d.total - d.used
        gpu.setForeground(T.textSecondary)
        gpu.set(cx + 1, statusY, string.format(
            "Диск: %s | Всього: %s | Вільно: %s%s",
            d.label, formatSize(d.total), formatSize(free),
            d.readOnly and " | ТІЛЬКИ ЧИТАННЯ" or ""
        ))
    end

    gpu.setForeground(T.textSecondary)
    local status = string.format("%d елементів", #win.files)
    if win.selFile then
        status = status .. " | Обрано: " .. win.selFile.name
        if not win.selFile.isDir and win.selFile.name ~= ".." then
            status = status .. " (" .. formatSize(win.selFile.size) .. ")"
        end
    end
    if win.errorMsg then
        gpu.setForeground(T.danger)
        status = "[ERR] " .. win.errorMsg
    end
    gpu.set(cx + 1, statusY + 1, UI.truncate(status, cw - 2))
end

-- ============================================================
-- CLICK
-- ============================================================
function explorer.click(win, clickX, clickY, btn)
    if not win._ui then return false end
    local UI = win._ui

    for _, elem in ipairs(win.elements) do
        if UI.hitTest(elem, clickX, clickY) then
            if elem.action == "selectDrive" then
                explorer.selectDrive(win, elem.driveIdx)
                return true

            elseif elem.action == "fileClick" then
                local file = win.files[elem.fileIdx]
                if not file then return false end

                local now      = computer.uptime()
                local isDouble = (win.lastClickIdx == elem.fileIdx)
                              and (now - win.lastClickTime < 0.5)

                win.lastClickIdx  = elem.fileIdx
                win.lastClickTime = now
                win.selIdx        = elem.fileIdx
                win.selFile       = file

                if isDouble then explorer._openFile(win, file) end
                return true

            elseif elem.action == "goUp" then
                if win.cwd ~= "/" then
                    win.cwd     = win.cwd:match("^(.*)/[^/]+$") or "/"
                    win.selIdx  = nil
                    win.selFile = nil
                    win.scrollY = 0
                    explorer.refresh(win)
                end
                return true

            elseif elem.action == "newDir" then
                -- FIX: defensive nil-check — win.drives[win.driveIdx]
                -- indexed directly here would error if state ever got
                -- out of sync (currentProxy set without a matching
                -- driveIdx entry).
                local drive = win.drives[win.driveIdx]
                if win.currentProxy and not (drive and drive.readOnly) then
                    local newPath = win.cwd .. (win.cwd:match("/$") and "" or "/") .. "nova_papka"
                    local i = 1
                    while win.currentProxy.exists(newPath) do
                        newPath = win.cwd .. "/nova_papka_" .. i
                        i = i + 1
                    end
                    pcall(win.currentProxy.makeDirectory, newPath)
                    explorer.refresh(win)
                end
                return true

            elseif elem.action == "deleteFile" then
                -- FIX (Critical Bug #2): never allow deleting the ".."
                -- pseudo-entry. Previously the enabled=false state only
                -- affected the button's colour — a click at the same
                -- screen coordinates still fired this handler, which
                -- had no name~=".." guard, so it could call
                -- proxy.remove() on the PARENT directory path.
                -- OpenComputers' filesystem.remove() deletes
                -- directories recursively with no confirmation, so this
                -- could destroy an entire branch of the filesystem.
                -- Also guard against attempting to delete on a
                -- read-only drive (the button already hides itself for
                -- that case via addBtn's `enabled` flag, but the click
                -- handler must not rely solely on that).
                local drive = win.drives[win.driveIdx]
                if win.selFile and win.currentProxy
                   and win.selFile.name ~= ".."
                   and not (drive and drive.readOnly) then
                    pcall(win.currentProxy.remove, win.selFile.path)
                    win.selIdx  = nil
                    win.selFile = nil
                    explorer.refresh(win)
                end
                return true

            elseif elem.action == "openNotepad" then
                if win.selFile then explorer._openFile(win, win.selFile) end
                return true
            end
        end
    end
    return false
end

function explorer._openFile(win, file)
    if not file then return end
    if file.isDir or file.name == ".." then
        win.cwd     = file.path
        win.selIdx  = nil
        win.selFile = nil
        win.scrollY = 0
        explorer.refresh(win)
    elseif EDITABLE[getExt(file.name)] then
        if _G.createWindow then
            _G.createWindow("notepad", {filepath = file.path, proxy = win.currentProxy})
        end
    end
end

-- ============================================================
-- KEY
-- ============================================================
function explorer.key(win, char, code)
    if code == 14 then
        if win.cwd ~= "/" then
            win.cwd     = win.cwd:match("^(.*)/[^/]+$") or "/"
            win.selIdx  = nil
            win.selFile = nil
            win.scrollY = 0
            explorer.refresh(win)
            return true
        end
    elseif code == 200 then
        if win.selIdx and win.selIdx > 1 then
            win.selIdx  = win.selIdx - 1
            win.selFile = win.files[win.selIdx]
            if win.selIdx <= win.scrollY then win.scrollY = math.max(0, win.scrollY - 1) end
        elseif not win.selIdx and #win.files > 0 then
            win.selIdx  = 1
            win.selFile = win.files[1]
        end
        return true
    elseif code == 208 then
        if win.selIdx and win.selIdx < #win.files then
            win.selIdx  = win.selIdx + 1
            win.selFile = win.files[win.selIdx]
            local visN  = (win._ch or 20) - 5
            if win.selIdx > win.scrollY + visN then win.scrollY = win.scrollY + 1 end
        elseif not win.selIdx and #win.files > 0 then
            win.selIdx  = 1
            win.selFile = win.files[1]
        end
        return true
    elseif code == 28 then
        if win.selFile then explorer._openFile(win, win.selFile); return true end
    elseif code == 211 then
        -- FIX: same ".." guard as the Delete button click handler.
        local drive = win.drives[win.driveIdx]
        if win.selFile and win.currentProxy
           and win.selFile.name ~= ".."
           and not (drive and drive.readOnly) then
            pcall(win.currentProxy.remove, win.selFile.path)
            win.selIdx  = nil
            win.selFile = nil
            explorer.refresh(win)
            return true
        end
    elseif code == 61 then
        explorer.refresh(win)
        return true
    end
    return false
end

-- ============================================================
-- SCROLL
-- ============================================================
function explorer.scroll(win, dir)
    win.scrollY = math.max(0, win.scrollY + (dir > 0 and -2 or 2))
    return true
end

return explorer