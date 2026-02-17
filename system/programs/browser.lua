-- ==========================================================
-- FixOS 3.2.1 - system/programs/browser.lua
-- Text-mode web browser for OpenComputers
-- Features:
--   - URL bar (click or press U to focus)
--   - Fetches pages via internet card
--   - Strips HTML tags, decodes entities
--   - Scrollable text content
--   - Back / Forward history
--   - Bookmarks bar
-- ==========================================================

local browser = {}

local BOOKMARKS = {
    {name="FixOS Repo", url="https://raw.githubusercontent.com/FixlutGames21/FixOS/main/README.md"},
    {name="Google",     url="https://www.google.com/"},
    {name="Wikipedia",  url="https://en.m.wikipedia.org/wiki/OpenComputers"},
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
        "  FixOS Browser v3.2.1",
        "  ----------------------",
        "",
        "  Welcome! Enter a URL in the address bar and",
        "  press Enter, or click a bookmark below.",
        "",
        "  Tips:",
        "    - Press U to focus the address bar",
        "    - Scroll with mouse wheel or arrow keys",
        "    - Click [<] and [>] for back/forward",
        "",
    }
    win.scrollY  = 0
    win.url      = "about:home"
    win.loadStatus = "Ready"
end

-- Strip HTML tags and decode basic entities
local function stripHtml(html)
    -- Remove script and style blocks
    local s = html
    s = s:gsub("<script[^>]*>.-</script>", "")
    s = s:gsub("<style[^>]*>.-</style>", "")
    s = s:gsub("<!%-%-.-%%->", "")

    -- Block-level tags -> newlines
    s = s:gsub("<br%s*/?>", "\n")
    s = s:gsub("<p[^>]*>", "\n")
    s = s:gsub("</p>", "\n")
    s = s:gsub("<div[^>]*>", "\n")
    s = s:gsub("</div>", "")
    s = s:gsub("<h[1-6][^>]*>", "\n== ")
    s = s:gsub("</h[1-6]>", " ==\n")
    s = s:gsub("<li[^>]*>", "\n  * ")
    s = s:gsub("<tr[^>]*>", "\n")
    s = s:gsub("<td[^>]*>", "  ")

    -- Remove all remaining tags
    s = s:gsub("<[^>]+>", "")

    -- Decode common entities
    s = s:gsub("&nbsp;", " ")
    s = s:gsub("&amp;",  "&")
    s = s:gsub("&lt;",   "<")
    s = s:gsub("&gt;",   ">")
    s = s:gsub("&quot;", '"')
    s = s:gsub("&#(%d+);", function(n) return string.char(math.min(tonumber(n) or 63, 127)) end)

    -- Collapse multiple blank lines
    s = s:gsub("\n%s*\n%s*\n+", "\n\n")
    -- Trim leading whitespace per line but keep indent
    local out = {}
    for line in (s.."\n"):gmatch("([^\n]*)\n") do
        table.insert(out, line)
    end
    return out
end

-- Wrap a single line to fit width
local function wrapLine(line, w)
    if #line <= w then return {line} end
    local out = {}
    while #line > w do
        table.insert(out, line:sub(1, w))
        line = line:sub(w + 1)
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

    -- Background
    gpu.setBackground(T.surface)
    gpu.fill(cx, cy, cw, ch, " ")

    win.elements = {}
    local y = cy

    -- ---- Navigation bar (row 1) ----
    gpu.setBackground(T.surfaceAlt)
    gpu.fill(cx, y, cw, 1, " ")

    -- Back button
    local hasBack = win.histIdx > 1
    local btnBack = {x=cx, y=y, w=4, h=1}
    gpu.setBackground(hasBack and T.accent or T.surfaceInset)
    gpu.setForeground(T.textOnAccent); gpu.set(cx, y, " [<]")
    btnBack.action = "back"; table.insert(win.elements, btnBack)

    -- Forward button
    local hasFwd = win.histIdx < #win.history
    local btnFwd  = {x=cx+4, y=y, w=4, h=1}
    gpu.setBackground(hasFwd and T.accent or T.surfaceInset)
    gpu.setForeground(T.textOnAccent); gpu.set(cx+4, y, "[>] ")
    btnFwd.action = "fwd"; table.insert(win.elements, btnFwd)

    -- Reload button
    gpu.setBackground(T.accent); gpu.setForeground(T.textOnAccent)
    gpu.set(cx+8, y, "[R]")
    table.insert(win.elements, {x=cx+8, y=y, w=3, h=1, action="reload"})

    -- URL bar
    local urlBarX = cx + 12
    local urlBarW = cw - 14
    local urlBg   = win.urlBarFocus and T.accentSubtle or T.surfaceInset
    gpu.setBackground(urlBg); gpu.fill(urlBarX, y, urlBarW, 1, " ")
    gpu.setForeground(T.textPrimary)
    local displayUrl = win.urlBarFocus and win.urlInput or win.url
    if #displayUrl > urlBarW - 2 then displayUrl = displayUrl:sub(-(urlBarW-2)) end
    gpu.set(urlBarX + 1, y, displayUrl)
    if win.urlBarFocus then
        -- cursor at end
        local cx2 = urlBarX + 1 + #displayUrl
        if cx2 < urlBarX + urlBarW then
            gpu.setBackground(T.textPrimary); gpu.setForeground(urlBg)
            gpu.set(cx2, y, " ")
        end
    end
    table.insert(win.elements, {x=urlBarX, y=y, w=urlBarW, h=1, action="urlbar"})

    y = cy + 1

    -- ---- Bookmarks bar (row 2) ----
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

    -- ---- Status / loading bar (row 3) ----
    gpu.setBackground(win.loading and T.accentSubtle or T.surfaceAlt)
    gpu.fill(cx, y, cw, 1, " ")
    gpu.setForeground(win.loading and T.accent or T.textSecondary)
    local status = win.loading and ("Loading: " .. win._netUrl) or win.loadStatus
    gpu.set(cx + 1, y, UI.truncate(status, cw - 2))

    y = cy + 3

    -- ---- Content area ----
    local contentH  = ch - 4   -- 3 header rows + 1 scrollbar row
    local contentW  = cw - 1   -- 1 col for scrollbar

    -- Re-wrap lines to current content width
    local wrapped = wrapLines(win.lines, contentW)

    gpu.setBackground(T.surface); gpu.fill(cx, y, contentW, contentH, " ")
    gpu.setForeground(T.textPrimary)

    local maxScroll = math.max(0, #wrapped - contentH)
    if win.scrollY > maxScroll then win.scrollY = maxScroll end

    for row = 0, contentH - 1 do
        local lineIdx = win.scrollY + row + 1
        local line    = wrapped[lineIdx]
        if line then
            -- Headers (== text ==) in accent color
            if line:match("^== .* ==$") then
                gpu.setForeground(T.accent)
            elseif line:match("^  %* ") then
                gpu.setForeground(T.textSecondary)
            else
                gpu.setForeground(T.textPrimary)
            end
            gpu.setBackground(T.surface)
            gpu.set(cx, y + row, line)
        end
    end

    -- Scrollbar
    UI.drawScrollbar(cx + cw - 1, y, contentH, math.max(contentH, #wrapped), contentH, win.scrollY)

    -- Bottom status: line counter
    gpu.setBackground(T.surfaceAlt); gpu.fill(cx, cy + ch - 1, cw, 1, " ")
    gpu.setForeground(T.textSecondary)
    gpu.set(cx + 1, cy + ch - 1,
        string.format("Lines: %d  Scroll: %d/%d  Press U = address bar",
            #wrapped, win.scrollY + 1, math.max(1, #wrapped)))
end

-- ----------------------------------------------------------
-- tick() - called every frame by desktop for async loading
-- ----------------------------------------------------------
function browser.tick(win)
    if not win.loading or not win._netHandle then return false end

    local ok, chunk = pcall(win._netHandle.read, math.huge)
    if ok and chunk and chunk ~= "" then
        table.insert(win._netBuf, chunk)
        win._netGotData = true
    elseif win._netGotData then
        -- EOF after data
        pcall(win._netHandle.close)
        win._netHandle = nil
        local raw = table.concat(win._netBuf)

        -- Detect content type and process
        local lines
        local ct = raw:sub(1, 200):lower()
        if ct:match("<html") or ct:match("<!doctype") then
            lines = stripHtml(raw)
        else
            -- Plain text / markdown
            lines = {}
            for line in (raw.."\n"):gmatch("([^\n]*)\n") do
                table.insert(lines, line)
            end
        end

        win.lines      = lines
        win.scrollY    = 0
        win.loading    = false
        win.loadStatus = "Done - " .. #raw .. " bytes - " .. win._netUrl

        -- Add to history
        if win.history[win.histIdx] ~= win._netUrl then
            while #win.history > win.histIdx do table.remove(win.history) end
            table.insert(win.history, win._netUrl)
            win.histIdx = #win.history
        end
        win.url = win._netUrl
        return true

    else
        win._netTimeout = (win._netTimeout or 0) + 1
        if win._netTimeout > 500 then  -- ~10s
            pcall(win._netHandle.close)
            win._netHandle = nil
            win.loading    = false
            win.lines      = {"[Timeout] Connection timed out.", "", "URL: " .. win._netUrl}
            win.loadStatus = "Timeout"
            return true
        end
    end
    return false
end

-- ----------------------------------------------------------
-- NAVIGATE
-- ----------------------------------------------------------
function browser.navigate(win, url)
    url = url:match("^%s*(.-)%s*$")
    if url == "" then return end

    -- Add http:// if missing
    if not url:match("^https?://") and not url:match("^about:") then
        url = "http://" .. url
    end

    if url == "about:home" then
        browser._showHome(win); return
    end

    if not component.isAvailable("internet") then
        win.lines = {
            "[Error] No Internet Card",
            "",
            "Install an internet card to browse the web.",
        }
        win.loadStatus = "No internet card"
        win.loading    = false
        return
    end

    -- Start async request
    local net = component.internet
    local ok, handle = pcall(net.request, url)
    if not ok or not handle then
        win.lines      = {"[Error] Could not connect:", "", "  " .. url}
        win.loadStatus = "Connection failed"
        win.loading    = false
        return
    end

    win._netHandle  = handle
    win._netBuf     = {}
    win._netGotData = false
    win._netTimeout = 0
    win._netUrl     = url
    win.loading     = true
    win.loadStatus  = "Connecting..."
    win.lines       = {"Loading " .. url .. "..."}
    win.scrollY     = 0
end

-- ----------------------------------------------------------
-- CLICK
-- ----------------------------------------------------------
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

    -- Click outside URL bar = unfocus
    if win.urlBarFocus then
        win.urlBarFocus = false; return true
    end
    return false
end

-- ----------------------------------------------------------
-- KEY
-- ----------------------------------------------------------
function browser.key(win, char, code)
    -- U = focus URL bar
    if not win.urlBarFocus and (char == 117 or char == 85) then
        win.urlBarFocus = true
        win.urlInput    = win.url
        return true
    end

    if win.urlBarFocus then
        if code == 28 then  -- Enter
            local url = win.urlInput
            win.urlBarFocus = false
            browser.navigate(win, url)
            return true

        elseif code == 1 then  -- Escape
            win.urlBarFocus = false; return true

        elseif code == 14 then  -- Backspace
            if #win.urlInput > 0 then
                win.urlInput = win.urlInput:sub(1, -2); return true
            end

        elseif char and char >= 32 and char <= 126 then
            win.urlInput = win.urlInput .. string.char(char); return true
        end
    else
        -- Scroll keys
        if code == 200 then  -- Up
            win.scrollY = math.max(0, win.scrollY - 1); return true
        elseif code == 208 then  -- Down
            win.scrollY = win.scrollY + 3; return true
        elseif code == 201 then  -- PgUp
            win.scrollY = math.max(0, win.scrollY - 10); return true
        elseif code == 209 then  -- PgDn
            win.scrollY = win.scrollY + 10; return true
        end
    end
    return false
end

-- ----------------------------------------------------------
-- SCROLL
-- ----------------------------------------------------------
function browser.scroll(win, dir)
    if dir > 0 then
        win.scrollY = math.max(0, win.scrollY - 3)
    else
        win.scrollY = win.scrollY + 3
    end
    return true
end

return browser