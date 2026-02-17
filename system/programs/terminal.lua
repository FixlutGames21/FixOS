-- ==========================================================
-- FixOS 3.2.0 - system/programs/terminal.lua
-- IMPROVEMENTS:
--   - Current directory tracking (cd command)
--   - Commands: cd, cat, mkdir, rm, cp, ls, dir, cls, clear,
--               help, uptime, mem, beep, ver, time, echo
--   - Vertical scrollbar
--   - Scrollback buffer
-- ==========================================================

local terminal = {}

local function L(key, ...) return (_G.Lang and _G.Lang.t(key, ...)) or key end

local PROMPT_COLOR = 0x00CC44
local TEXT_COLOR   = 0xCCCCCC
local BG_COLOR     = 0x0C0C0C
local ERROR_COLOR  = 0xFF4444
local INFO_COLOR   = 0x0078D7

function terminal.init(win)
    win.lines       = {
        L("terminal.welcome"),
        L("terminal.help_hint"),
        ""
    }
    win.currentLine = ""
    win.cursorPos   = 1
    win.scrollY     = 0
    win.maxLines    = 200
    win.prompt      = "C:\\> "
    win.cwd         = "/"            -- current directory
    win.history     = {}
    win.histIdx     = 0
    win._ui         = nil

    table.insert(win.lines, win.prompt)
end

local function getFS()
    return component.proxy(computer.getBootAddress())
end

local function pushLine(win, text, color)
    table.insert(win.lines, (color and ("\x01"..color.."\x02") or "") .. tostring(text))
    while #win.lines > win.maxLines do table.remove(win.lines, 1) end
end

local function resolvePath(win, path)
    if path == nil or path == "" then return win.cwd end
    if path:sub(1,1) == "/" then return path end
    if path == ".." then
        if win.cwd == "/" then return "/" end
        return win.cwd:match("(.+)/[^/]+$") or "/"
    end
    local sep = win.cwd:match("/$") and "" or "/"
    return win.cwd .. sep .. path
end

local function executeCommand(win, cmdLine)
    cmdLine = cmdLine:match("^%s*(.-)%s*$")
    if cmdLine == "" then return end

    table.insert(win.history, 1, cmdLine)
    if #win.history > 50 then table.remove(win.history) end
    win.histIdx = 0

    -- Parse command and args
    local parts = {}
    for p in cmdLine:gmatch("%S+") do table.insert(parts, p) end
    local cmd  = parts[1] and parts[1]:lower() or ""
    local arg1 = parts[2] or ""
    local arg2 = parts[3] or ""

    local fs = getFS()

    if cmd == "help" then
        pushLine(win, "Commands:")
        local cmds = {
            "  help              - This help",
            "  cls / clear       - Clear screen",
            "  echo <text>       - Print text",
            "  ls / dir [path]   - List files",
            "  cd <path>         - Change directory",
            "  cat <file>        - Read file",
            "  mkdir <dir>       - Create directory",
            "  rm <path>         - Delete file/dir",
            "  cp <src> <dst>    - Copy file",
            "  uptime            - System uptime",
            "  mem               - Memory info",
            "  ver               - OS version",
            "  time              - Current time",
            "  beep              - Beep",
        }
        for _, line in ipairs(cmds) do pushLine(win, line) end

    elseif cmd == "cls" or cmd == "clear" then
        win.lines = {}

    elseif cmd:match("^echo") then
        pushLine(win, cmdLine:sub(6))

    elseif cmd == "ls" or cmd == "dir" then
        local path = arg1 ~= "" and resolvePath(win, arg1) or win.cwd
        local ok, list = pcall(function() return fs.list(path) end)
        if not ok or not list then
            pushLine(win, "[ERR] Cannot list: " .. path)
        else
            pushLine(win, "Directory of " .. path)
            pushLine(win, "")
            local count = 0
            local function addFile(f)
                if count > 30 then return end
                local fp   = (path:match("/$") and path or (path.."/")) .. f
                local isD  = pcall(fs.isDirectory, fp) and fs.isDirectory(fp) or false
                local pre  = isD and "<DIR>  " or "       "
                pushLine(win, pre .. f)
                count = count + 1
            end
            if type(list) == "function" then
                for f in list do addFile(f) end
            else
                for _, f in ipairs(list) do addFile(f) end
            end
            if count == 0 then pushLine(win, "(empty)") end
            pushLine(win, "")
            pushLine(win, count .. " item(s)")
        end

    elseif cmd == "cd" then
        if arg1 == "" then
            pushLine(win, win.cwd)
        else
            local target = resolvePath(win, arg1)
            if target ~= "/" then
                local ok, isDir = pcall(fs.isDirectory, target)
                if ok and isDir then
                    win.cwd = target
                    win.prompt = "C:" .. target:gsub("/","\\") .. "> "
                else
                    pushLine(win, "[ERR] Not a directory: " .. target)
                end
            else
                win.cwd = "/"
                win.prompt = "C:\\> "
            end
        end

    elseif cmd == "cat" then
        if arg1 == "" then
            pushLine(win, "[ERR] Usage: cat <file>")
        else
            local path = resolvePath(win, arg1)
            if not fs.exists(path) then
                pushLine(win, "[ERR] File not found: " .. path)
            elseif fs.isDirectory(path) then
                pushLine(win, "[ERR] Is a directory: " .. path)
            else
                local h = fs.open(path, "r")
                if h then
                    local data = fs.read(h, math.huge); fs.close(h)
                    local lines = 0
                    for line in (data .. "\n"):gmatch("([^\n]*)\n") do
                        pushLine(win, line)
                        lines = lines + 1
                        if lines > 50 then pushLine(win, "... (truncated)"); break end
                    end
                else
                    pushLine(win, "[ERR] Cannot open: " .. path)
                end
            end
        end

    elseif cmd == "mkdir" then
        if arg1 == "" then
            pushLine(win, "[ERR] Usage: mkdir <dir>")
        else
            local path = resolvePath(win, arg1)
            local ok, err = pcall(fs.makeDirectory, path)
            if ok then pushLine(win, "Created: " .. path)
            else  pushLine(win, "[ERR] " .. tostring(err)) end
        end

    elseif cmd == "rm" then
        if arg1 == "" then
            pushLine(win, "[ERR] Usage: rm <path>")
        else
            local path = resolvePath(win, arg1)
            if not fs.exists(path) then
                pushLine(win, "[ERR] Not found: " .. path)
            else
                local ok, err = pcall(fs.remove, path)
                if ok then pushLine(win, "Deleted: " .. path)
                else  pushLine(win, "[ERR] " .. tostring(err)) end
            end
        end

    elseif cmd == "cp" then
        if arg1 == "" or arg2 == "" then
            pushLine(win, "[ERR] Usage: cp <src> <dst>")
        else
            local src = resolvePath(win, arg1)
            local dst = resolvePath(win, arg2)
            if not fs.exists(src) then
                pushLine(win, "[ERR] Not found: " .. src)
            else
                local h1 = fs.open(src, "r")
                if h1 then
                    local data = fs.read(h1, math.huge); fs.close(h1)
                    local h2 = fs.open(dst, "w")
                    if h2 then
                        fs.write(h2, data); fs.close(h2)
                        pushLine(win, "Copied: " .. src .. " -> " .. dst)
                    else
                        pushLine(win, "[ERR] Cannot write: " .. dst)
                    end
                else
                    pushLine(win, "[ERR] Cannot read: " .. src)
                end
            end
        end

    elseif cmd == "uptime" then
        local up  = math.floor(computer.uptime())
        local h   = math.floor(up / 3600)
        local m   = math.floor((up % 3600) / 60)
        local s   = up % 60
        pushLine(win, string.format("Uptime: %02d:%02d:%02d", h, m, s))

    elseif cmd == "mem" then
        local total = computer.totalMemory()
        local free  = computer.freeMemory()
        local used  = total - free
        pushLine(win, string.format("Memory: %dKB used / %dKB total (%d%%)",
            math.floor(used/1024), math.floor(total/1024),
            math.floor(used/total*100)))

    elseif cmd == "beep" then
        computer.beep(1000, 0.2); pushLine(win, "BEEP!")

    elseif cmd == "ver" or cmd == "version" then
        pushLine(win, "FixOS 3.2.0 - Windows 10 Edition")

    elseif cmd == "time" then
        pushLine(win, "Time: " .. os.date("%H:%M:%S"))

    elseif cmd == "pwd" then
        pushLine(win, win.cwd)

    else
        pushLine(win, L("terminal.unknown", cmd))
    end
end

function terminal.draw(win, gpu, x, y, w, h)
    if not win._ui then
        win._ui = dofile("/system/ui.lua")
        win._ui.init(gpu)
    end

    local SB_W = 1
    local textW = w - SB_W

    gpu.setBackground(BG_COLOR)
    gpu.setForeground(TEXT_COLOR)
    gpu.fill(x, y, w, h, " ")

    local visLines = h - 1   -- last line reserved for input
    -- Adjust scroll so current input is always visible
    local maxScroll = math.max(0, #win.lines - visLines)
    if win.scrollY > maxScroll then win.scrollY = maxScroll end

    local startLine = win.scrollY + 1

    for i = 0, visLines - 1 do
        local idx  = startLine + i
        local line = win.lines[idx]
        if line then
            -- Strip color codes (simple)
            line = line:gsub("\x01%x+\x02", "")
            if #line > textW then line = line:sub(1, textW) end

            -- Prompt lines in special color
            if line:match("^C:") then
                gpu.setForeground(PROMPT_COLOR)
            else
                gpu.setForeground(TEXT_COLOR)
            end
            gpu.setBackground(BG_COLOR)
            gpu.set(x, y + i, line)
        end
    end

    -- Input line (always at bottom)
    local inputY = y + h - 1
    gpu.setBackground(0x1A1A1A)
    gpu.fill(x, inputY, textW, 1, " ")
    gpu.setForeground(PROMPT_COLOR)
    gpu.set(x, inputY, win.prompt)
    gpu.setForeground(TEXT_COLOR)
    local promptLen = #win.prompt
    gpu.set(x + promptLen, inputY, win.currentLine)

    -- Cursor
    local curX = x + promptLen + win.cursorPos - 1
    if curX < x + textW then
        gpu.setBackground(TEXT_COLOR)
        gpu.setForeground(BG_COLOR)
        local ch = win.currentLine:sub(win.cursorPos, win.cursorPos)
        gpu.set(curX, inputY, ch ~= "" and ch or " ")
    end

    -- Scrollbar
    win._ui.drawScrollbar(x + w - SB_W, y, visLines,
        math.max(visLines, #win.lines), visLines, win.scrollY)
end

function terminal.key(win, char, code)
    -- Enter
    if code == 28 then
        pushLine(win, win.prompt .. win.currentLine)
        executeCommand(win, win.currentLine)
        win.currentLine = ""
        win.cursorPos   = 1
        table.insert(win.lines, "")  -- blank separator
        win.scrollY = math.max(0, #win.lines - 20)
        return true

    -- Backspace
    elseif code == 14 then
        if win.cursorPos > 1 then
            win.currentLine = win.currentLine:sub(1, win.cursorPos - 2) ..
                              win.currentLine:sub(win.cursorPos)
            win.cursorPos = win.cursorPos - 1
            return true
        end

    -- Delete
    elseif code == 211 then
        if win.cursorPos <= #win.currentLine then
            win.currentLine = win.currentLine:sub(1, win.cursorPos - 1) ..
                              win.currentLine:sub(win.cursorPos + 1)
            return true
        end

    -- Left
    elseif code == 203 then
        if win.cursorPos > 1 then win.cursorPos = win.cursorPos - 1; return true end

    -- Right
    elseif code == 205 then
        if win.cursorPos <= #win.currentLine then win.cursorPos = win.cursorPos + 1; return true end

    -- Home
    elseif code == 199 then win.cursorPos = 1; return true

    -- End
    elseif code == 207 then win.cursorPos = #win.currentLine + 1; return true

    -- Up = history previous
    elseif code == 200 then
        if win.histIdx < #win.history then
            win.histIdx = win.histIdx + 1
            win.currentLine = win.history[win.histIdx] or ""
            win.cursorPos   = #win.currentLine + 1
            return true
        end

    -- Down = history next
    elseif code == 208 then
        if win.histIdx > 1 then
            win.histIdx = win.histIdx - 1
            win.currentLine = win.history[win.histIdx] or ""
            win.cursorPos   = #win.currentLine + 1
            return true
        elseif win.histIdx == 1 then
            win.histIdx = 0; win.currentLine = ""; win.cursorPos = 1; return true
        end

    -- Printable chars
    elseif char and char >= 32 and char <= 255 then
        win.currentLine = win.currentLine:sub(1, win.cursorPos - 1) ..
                          string.char(char) ..
                          win.currentLine:sub(win.cursorPos)
        win.cursorPos = win.cursorPos + 1
        return true
    end
    return false
end

function terminal.scroll(win, direction)
    if direction > 0 then
        win.scrollY = math.max(0, win.scrollY - 3)
    else
        local maxS = math.max(0, #win.lines - 18)
        win.scrollY = math.min(maxS, win.scrollY + 3)
    end
    return true
end

return terminal