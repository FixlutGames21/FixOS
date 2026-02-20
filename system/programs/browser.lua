-- ==========================================================
-- FixOS 3.2.3 - system/programs/browser.lua
-- FIX: Navigation now works correctly (no about:home loop)
-- ==========================================================

local browser = {}

local BOOKMARKS = {
    {name="GitHub",    url="https://github.com"},
    {name="Wikipedia", url="https://en.m.wikipedia.org/wiki/Lua_(programming_language)"},
}

function browser.init(win)
    win.url         = "about:home"
    win.urlBarFocus = false
    win.urlInput    = ""
    win.lines       = {}
    win.scrollY     = 0
    win.loading     = false
    win.loadStatus  = ""
    win.history     = {}
    win.histIdx     = 0
    win.elements    = {}
    win._ui         = nil
    win._netHandle  = nil
    win._netBuf     = {}
    win._netGotData = false
    win._netTimeout = 0
    win._netUrl     = ""

    browser._showHome(win)
end

function browser._showHome(win)
    win.lines = {
        "",
        "  ══════════════════════════════════════",
        "      FixOS Browser v3.2.3",
        "  ══════════════════════════════════════",
        "",
        "  Welcome to FixOS Browser!",
        "",
        "  How to use:",
        "    • Click URL bar or press U to enter address",
        "    • Press Enter to navigate",
        "    • Use bookmarks below for quick access",
        "    • Click [<] and [>] for back/forward",
        "    • Scroll with mouse wheel or arrow keys",
        "",
        "  Supported:",
        "    ✓ HTML pages (auto-stripped to text)",
        "    ✓ Plain text / Markdown",
        "    ✓ Navigation history",
        "",
        "  Examples:",
        "    github.com",
        "    pastebin.com/raw/...",
        "    en.wikipedia.org/wiki/...",
        "",
    }
    win.scrollY    = 0
    win.url        = "about:home"
    win.loadStatus = "Ready"
    win.loading    = false
end

local function stripHtml(html)
    local s = html
    s = s:gsub("<script[^>]*>.-</script>", " ")
    s = s:gsub("<style[^>]*>.-</style>", " ")
    s = s:gsub("<!%-%-.-%%->", " ")
    s = s:gsub("<br%s*/?>", "\n")
    s = s:gsub("<p[^>]*>", "\n")
    s = s:gsub("</p>", "\n")
    s = s:gsub("<div[^>]*>", "\n")
    s = s:gsub("<h[1-6][^>]*>", "\n== ")
    s = s:gsub("</h[1-6]>", " ==\n")
    s = s:gsub("<li[^>]*>", "\n  • ")
    s = s:gsub("<tr[^>]*>", "\n")
    s = s:gsub("<td[^>]*>", "  ")
    s = s:gsub("<a[^>]*>", "[")
    s = s:gsub("</a>", "]")
    s = s:gsub("<[^>]*>", "")
    s = s:gsub("&nbsp;", " ")
    s = s:gsub("&amp;",  "&")
    s = s:gsub("&lt;",   "<")
    s = s:gsub("&gt;",   ">")
    s = s:gsub("&quot;", '"')
    s = s:gsub("&#(%d+);", function(n)
        local c = tonumber(n)
        return c and c <= 127 and string.char(c) or "?"
    end)
    s = s:gsub("[ \t]+", " ")
    s = s:gsub("\n[ \t]+", "\n")
    s = s:gsub("\n\n+", "\n\n")
    local out = {}
    for line in (s.."\n"):gmatch("([^\n]*)\n") do
        table.insert(out, line)
    end
    return out
end

local function wrapLine(line, w)
    if #line <= w then return {line} end
    local out = {}
    while #line > w do
        local cut = w
        local sp = line:sub(1, w):match("^(.* )") or ""
        if #sp > 10 then cut = #sp end
        table.insert(out, line:sub(1, cut))
        line = line:sub(cut + 1)
    end
    if #line > 0 then table.insert(out, line) end
    return out
end

local function wrapLines(lines, w)
    local out = {}
    for _, line in ipairs(lines) do
        for _, wrapped in ipairs(wrapLine(line, w)) do
            table.insert(out, wrapped)
        end
    end
    return out
end

function browser.draw(win, gpu, cx, cy, cw, ch)
    if not win._ui then
        win._ui = dofile("/system/ui.lua")
        win._ui.init(gpu)
    end
    local UI = win._ui
    local T  = UI.Theme

    gpu.setBackground(T.surface)
    gpu.fill(cx, cy, cw, ch, " ")

    win.elements = {}
    local y = cy

    -- Navigation bar
    gpu.setBackground(T.surfaceAlt)
    gpu.fill(cx, y, cw, 1, " ")

    local hasBack = win.histIdx > 1
    local btnBack = {x=cx, y=y, w=4, h=1}
    gpu.setBackground(hasBack and T.accent or T.surfaceInset)
    gpu.setForeground(T.textOnAccent); gpu.set(cx, y, " [<]")
    btnBack.action = "back"; table.insert(win.elements, btnBack)

    local hasFwd = win.histIdx < #win.history
    local btnFwd = {x=cx+4, y=y, w=4, h=1}
    gpu.setBackground(hasFwd and T.accent or T.surfaceInset)
    gpu.setForeground(T.textOnAccent); gpu.set(cx+4, y, "[>] ")
    btnFwd.action = "fwd"; table.insert(win.elements, btnFwd)

    gpu.setBackground(T.accent); gpu.setForeground(T.textOnAccent)
    gpu.set(cx+8, y, "[R]")
    table.insert(win.elements, {x=cx+8, y=y, w=3, h=1, action="reload"})

    local urlBarX = cx + 12
    local urlBarW = cw - 14
    local urlBg   = win.urlBarFocus and T.accentSubtle or T.surfaceInset
    gpu.setBackground(urlBg); gpu.fill(urlBarX, y, urlBarW, 1, " ")
    gpu.setForeground(T.textPrimary)
    local displayUrl = win.urlBarFocus and win.urlInput or win.url
    if #displayUrl > urlBarW - 2 then displayUrl = "..." .. displayUrl:sub(-(urlBarW-5)) end
    gpu.set(urlBarX + 1, y, displayUrl)
    if win.urlBarFocus then
        local cx2 = urlBarX + 1 + #displayUrl
        if cx2 < urlBarX + urlBarW then
            gpu.setBackground(T.textPrimary); gpu.setForeground(urlBg)
            gpu.set(cx2, y, " ")
        end
    end
    table.insert(win.elements, {x=urlBarX, y=y, w=urlBarW, h=1, action="urlbar"})

    y = cy + 1

    -- Bookmarks
    gpu.setBackground(T.surfaceAlt)
    gpu.fill(cx, y, cw, 1, " ")
    local bx = cx + 1
    for _, bm in ipairs(BOOKMARKS) do
        local label = "[" .. bm.name .. "]"
        if bx + #label < cx + cw - 2 then
            gpu.setBackground(T.accent); gpu.setForeground(T.textOnAccent)
            gpu.set(bx, y, label)
            table.insert(win.elements, {x=bx, y=y, w=#label, h=1, action="bookmark", url=bm.url})
            bx = bx + #label + 1
        end
    end

    y = cy + 2

    -- Status
    gpu.setBackground(win.loading and T.accentSubtle or T.surfaceAlt)
    gpu.fill(cx, y, cw, 1, " ")
    gpu.setForeground(win.loading and T.accent or T.textSecondary)
    local status = win.loading and ("Loading: " .. (win._netUrl or "")) or win.loadStatus
    gpu.set(cx + 1, y, UI.truncate(status, cw - 2))

    y = cy + 3

    -- Content
    local contentH = ch - 4
    local contentW = cw - 1

    local wrapped = wrapLines(win.lines, contentW)
    local maxScroll = math.max(0, #wrapped - contentH)
    if win.scrollY > maxScroll then win.scrollY = maxScroll end

    gpu.setBackground(T.surface); gpu.fill(cx, y, contentW, contentH, " ")
    gpu.setForeground(T.textPrimary)

    for row = 0, contentH - 1 do
        local lineIdx = win.scrollY + row + 1
        local line    = wrapped[lineIdx]
        if line then
            if line:match("^==.*==$") then
                gpu.setForeground(T.accent)
            elseif line:match("^  •") then
                gpu.setForeground(T.textSecondary)
            else
                gpu.setForeground(T.textPrimary)
            end
            gpu.setBackground(T.surface)
            gpu.set(cx, y + row, line)
        end
    end

    UI.drawScrollbar(cx + cw - 1, y, contentH, math.max(contentH, #wrapped), contentH, win.scrollY)

    gpu.setBackground(T.surfaceAlt); gpu.fill(cx, cy + ch - 1, cw, 1, " ")
    gpu.setForeground(T.textSecondary)
    gpu.set(cx + 1, cy + ch - 1,
        string.format("Lines: %d | Scroll: %d | Press U = address bar",
            #wrapped, win.scrollY + 1))
end

function browser.tick(win)
    if not win.loading or not win._netHandle then return false end

    local ok, chunk = pcall(win._netHandle.read, 8192)
    if ok and chunk and chunk ~= "" then
        table.insert(win._netBuf, chunk)
        win._netGotData = true
        win.loadStatus  = "Downloading... " .. math.floor(#table.concat(win._netBuf)/1024) .. "KB"
    elseif win._netGotData then
        pcall(win._netHandle.close)
        win._netHandle = nil
        local raw = table.concat(win._netBuf)

        local lines
        if raw:lower():match("<html") or raw:lower():match("<!doctype") then
            lines = stripHtml(raw)
        else
            lines = {}
            for line in (raw.."\n"):gmatch("([^\n]*)\n") do
                table.insert(lines, line)
            end
        end

        win.lines      = lines
        win.scrollY    = 0
        win.loading    = false
        win.loadStatus = "Done - " .. #raw .. " bytes"

        -- FIX: Add to history ONLY if different from current
        if #win.history == 0 or win.history[#win.history] ~= win._netUrl then
            -- Remove forward history if we navigated from middle
            while #win.history > win.histIdx do
                table.remove(win.history)
            end
            table.insert(win.history, win._netUrl)
            win.histIdx = #win.history
        end
        
        win.url = win._netUrl
        return true

    else
        win._netTimeout = (win._netTimeout or 0) + 1
        if win._netTimeout > 500 then
            pcall(win._netHandle.close)
            win._netHandle = nil
            win.loading    = false
            win.lines = {
                "",
                "  [Timeout]",
                "",
                "  Connection timed out after 10 seconds.",
                "",
                "  URL: " .. (win._netUrl or ""),
                "",
            }
            win.loadStatus = "Timeout"
            return true
        end
    end
    return false
end

-- FIX: Navigation logic corrected
function browser.navigate(win, url)
    url = url:match("^%s*(.-)%s*$")
    if url == "" then return end

    -- Add http:// if no protocol
    if not url:match("^https?://") and not url:match("^about:") then
        url = "http://" .. url
    end

    -- Handle about:home specially
    if url == "about:home" then
        browser._showHome(win)
        return
    end

    -- Check for internet card
    if not component.isAvailable("internet") then
        win.lines = {
            "",
            "  [Error] No Internet Card",
            "",
            "  The Internet Card is required to browse the web.",
        }
        win.loadStatus = "No internet card"
        win.loading    = false
        return
    end

    -- Start request
    local net = component.internet
    local ok, handle = pcall(net.request, url)
    if not ok or not handle then
        win.lines = {
            "",
            "  [Error] Connection Failed",
            "",
            "  Could not connect to:",
            "  " .. url,
            "",
        }
        win.loadStatus = "Connection failed"
        win.loading    = false
        return
    end

    -- Set loading state
    win._netHandle  = handle
    win._netBuf     = {}
    win._netGotData = false
    win._netTimeout = 0
    win._netUrl     = url
    win.loading     = true
    win.loadStatus  = "Connecting..."
    win.lines       = {"", "  Loading " .. url .. "...", ""}
    win.scrollY     = 0
end

function browser.click(win, clickX, clickY, btn)
    if not win._ui then return false end
    local UI = win._ui

    for _, elem in ipairs(win.elements) do
        if UI.hitTest(elem, clickX, clickY) then
            if elem.action == "urlbar" then
                win.urlBarFocus = true
                win.urlInput    = win.url
                return true

            elseif elem.action == "back" then
                if win.histIdx > 1 then
                    win.histIdx = win.histIdx - 1
                    browser.navigate(win, win.history[win.histIdx])
                end
                return true

            elseif elem.action == "fwd" then
                if win.histIdx < #win.history then
                    win.histIdx = win.histIdx + 1
                    browser.navigate(win, win.history[win.histIdx])
                end
                return true

            elseif elem.action == "reload" then
                browser.navigate(win, win.url)
                return true

            elseif elem.action == "bookmark" then
                win.urlBarFocus = false
                browser.navigate(win, elem.url)
                return true
            end
        end
    end

    if win.urlBarFocus then
        win.urlBarFocus = false; return true
    end
    return false
end

function browser.key(win, char, code)
    if not win.urlBarFocus and (char == 117 or char == 85) then
        win.urlBarFocus = true
        win.urlInput    = win.url
        return true
    end

    if win.urlBarFocus then
        if code == 28 then
            local url = win.urlInput
            win.urlBarFocus = false
            browser.navigate(win, url)
            return true
        elseif code == 1 then
            win.urlBarFocus = false; return true
        elseif code == 14 then
            if #win.urlInput > 0 then
                win.urlInput = win.urlInput:sub(1, -2); return true
            end
        elseif char and char >= 32 and char <= 126 then
            win.urlInput = win.urlInput .. string.char(char); return true
        end
    else
        if code == 200 then
            win.scrollY = math.max(0, win.scrollY - 1); return true
        elseif code == 208 then
            win.scrollY = win.scrollY + 1; return true
        elseif code == 201 then
            win.scrollY = math.max(0, win.scrollY - 10); return true
        elseif code == 209 then
            win.scrollY = win.scrollY + 10; return true
        end
    end
    return false
end

function browser.scroll(win, dir)
    if dir > 0 then
        win.scrollY = math.max(0, win.scrollY - 3)
    else
        win.scrollY = win.scrollY + 3
    end
    return true
end

return browser