-- ==========================================================
-- FixOS 4.3.0 - system/lib/updater.lua   (НОВИЙ ФАЙЛ)
-- Логіка Update Center: оновлення з GitHub, версії окремих
-- компонентів, резервні копії, відкат.
--
-- Безпека оновлення (порядок важливий):
--   1. Завантажити маніфест репозиторію (manifest.txt).
--   2. Кожен файл скачується в /system/.staging і ПЕРЕВІРЯЄТЬСЯ:
--      розмір, контрольна сума Adler-32 та, для .lua, що файл
--      компілюється. Будь-яка помилка = нічого не змінено.
--   3. Поточні файли копіюються в /system/backups/bNNNN.
--   4. Лише тоді файли підміняються (rename зі staging).
--      Якщо підміна не вдалась - автоматичний відкат із копії.
--   5. Відкат у будь-який момент із вкладки "Резервні копії";
--      сам відкат теж створює копію, тож його можна скасувати.
--
-- Усе виконується як корутина-"робота" (Job:step()), тому UI
-- не блокується, а OC не вбиває скрипт за "too long without
-- yielding".
-- ==========================================================

local Updater = {}

Updater.REPO        = "FixlutGames21/FixOS"
Updater.BRANCH      = "main"
Updater.HOST        = "https://raw.githubusercontent.com"
Updater.CFG_PATH    = "/system/updater.cfg"
Updater.LOCAL_MF    = "/system/manifest.txt"
Updater.BACKUP_DIR  = "/system/backups"
Updater.STAGE_DIR   = "/system/.staging"
Updater.MAX_BACKUPS = 5
Updater.CHUNK       = 8192
Updater.SPACE_MARGIN = 16 * 1024

local CANCEL = {}   -- маркер скасування

-- ──────────────────────────────────────────────────────────
-- Файлова система
-- ──────────────────────────────────────────────────────────
local function getFs()
    return component.proxy(computer.getBootAddress())
end

local function readAll(fs, path)
    local h = fs.open(path, "r")
    if not h then return nil, "open failed: " .. path end
    local parts = {}
    while true do
        local chunk = fs.read(h, Updater.CHUNK)
        if not chunk then break end
        parts[#parts + 1] = chunk
    end
    fs.close(h)
    return table.concat(parts)
end

local function writeAll(fs, path, data)
    local h = fs.open(path, "w")
    if not h then return false end
    local ok = true
    local i, n = 1, #data
    while i <= n do
        local r = fs.write(h, data:sub(i, i + Updater.CHUNK - 1))
        if r == false then ok = false; break end
        i = i + Updater.CHUNK
    end
    fs.close(h)
    return ok
end

local function parentOf(path)
    return path:match("^(.*)/[^/]*$") or ""
end

local function mkdirs(fs, dir)
    if dir == "" or dir == "/" then return true end
    local cur = ""
    for part in dir:gmatch("[^/]+") do
        cur = cur .. "/" .. part
        if not fs.exists(cur) then
            if not fs.makeDirectory(cur) then
                if not fs.exists(cur) then return false end
            end
        end
    end
    return true
end

local function removeTree(fs, path)
    if not fs.exists(path) then return true end
    if fs.isDirectory(path) then
        local list = fs.list(path)
        if list then
            for _, name in ipairs(list) do
                removeTree(fs, path .. "/" .. name:gsub("/$", ""))
            end
        end
    end
    return fs.remove(path)
end

-- Потокове копіювання (не тримає файл цілком у пам'яті)
local function copyFile(fs, from, to, pause)
    local src = fs.open(from, "r")
    if not src then return false, "read " .. from end
    local dst = fs.open(to, "w")
    if not dst then fs.close(src); return false, "write " .. to end
    local ok = true
    while true do
        local chunk = fs.read(src, Updater.CHUNK)
        if not chunk then break end
        if fs.write(dst, chunk) == false then ok = false; break end
        if pause then pause() end
    end
    fs.close(src); fs.close(dst)
    if not ok then return false, "write failed " .. to end
    return true
end

-- Adler-32: лише додавання/залишок, працює однаково на Lua 5.2/5.3
function Updater.adler32(s)
    local a, b = 1, 0
    local i, n = 1, #s
    while i <= n do
        local j = math.min(n, i + 63)
        local bytes = {s:byte(i, j)}
        for k = 1, #bytes do
            a = a + bytes[k]
            b = b + a
        end
        a = a % 65521; b = b % 65521
        i = j + 1
    end
    return string.format("%08x", b * 65536 + a)
end

-- ──────────────────────────────────────────────────────────
-- Версії
-- ──────────────────────────────────────────────────────────
function Updater.compareVersions(a, b)
    local function parts(v)
        local t = {}
        for n in tostring(v or "0"):gmatch("%d+") do t[#t + 1] = tonumber(n) end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x < y then return -1 elseif x > y then return 1 end
    end
    return 0
end

-- ──────────────────────────────────────────────────────────
-- Маніфест
--   os=4.3.0
--   component|id|Назва|версія|прапорці(reboot)|залежності(id,id)
--   file|id|шлях у репозиторії|шлях на диску|розмір|adler32
--   log|версія|текст
-- ──────────────────────────────────────────────────────────
local function splitBar(line)
    local t = {}
    for f in (line .. "|"):gmatch("([^|]*)|") do t[#t + 1] = f end
    return t
end

function Updater.parseManifest(text)
    local m = {components = {}, order = {}, log = {}}
    for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local k, v = line:match("^(%w+)=(.*)$")
            if k then
                m[k] = v
            else
                local t = splitBar(line)
                if t[1] == "component" and t[2] and t[2] ~= "" then
                    local c = {id = t[2], name = t[3] or t[2], version = t[4] or "0",
                               reboot = (t[5] or ""):find("reboot", 1, true) ~= nil,
                               requires = {}, files = {}}
                    for r in (t[6] or ""):gmatch("[^,%s]+") do c.requires[#c.requires + 1] = r end
                    m.components[c.id] = c
                    m.order[#m.order + 1] = c.id
                elseif t[1] == "file" and t[2] and t[3] and t[4] then
                    local c = m.components[t[2]]
                    if c then
                        c.files[#c.files + 1] = {path = t[3], target = t[4],
                                                 size = tonumber(t[5]) or 0, adler = t[6]}
                    end
                elseif t[1] == "log" and t[2] then
                    m.log[#m.log + 1] = {version = t[2], text = t[3] or ""}
                end
            end
        end
    end
    return m
end

function Updater.serializeManifest(m)
    local out = {"manifest=1"}
    if m.os     then out[#out + 1] = "os=" .. m.os end
    if m.repo   then out[#out + 1] = "repo=" .. m.repo end
    if m.branch then out[#out + 1] = "branch=" .. m.branch end
    for _, id in ipairs(m.order) do
        local c = m.components[id]
        if c then
            out[#out + 1] = table.concat({"component", c.id, c.name, c.version,
                c.reboot and "reboot" or "", table.concat(c.requires or {}, ",")}, "|")
            for _, f in ipairs(c.files) do
                out[#out + 1] = table.concat({"file", c.id, f.path, f.target,
                    tostring(f.size or 0), f.adler or ""}, "|")
            end
        end
    end
    for _, l in ipairs(m.log or {}) do out[#out + 1] = "log|" .. l.version .. "|" .. l.text end
    return table.concat(out, "\n") .. "\n"
end

function Updater.loadLocal()
    local fs = getFs()
    if not fs.exists(Updater.LOCAL_MF) then return nil end
    local text = readAll(fs, Updater.LOCAL_MF)
    if not text then return nil end
    local m = Updater.parseManifest(text)
    if not m.os and next(m.components) == nil then return nil end
    return m
end

local function readVersionTxt(fs)
    if not fs.exists("/version.txt") then return nil end
    local v = readAll(fs, "/version.txt")
    return v and v:match("(%d+%.%d+[%d%.]*)")
end

function Updater.localOsVersion()
    local m = Updater.loadLocal()
    if m and m.os then return m.os end
    return readVersionTxt(getFs()) or "?"
end

-- ──────────────────────────────────────────────────────────
-- Налаштування (repo/branch)
-- ──────────────────────────────────────────────────────────
function Updater.loadConfig()
    local fs = getFs()
    if fs.exists(Updater.CFG_PATH) then
        local d = readAll(fs, Updater.CFG_PATH) or ""
        local repo   = d:match("repo=([%w%._%-]+/[%w%._%-]+)")
        local branch = d:match("branch=([%w%._%-/]+)")
        if repo then Updater.REPO = repo end
        if branch then Updater.BRANCH = branch end
    end
end

function Updater.saveConfig(repo, branch)
    Updater.REPO, Updater.BRANCH = repo, branch
    return writeAll(getFs(), Updater.CFG_PATH, "repo=" .. repo .. "\nbranch=" .. branch .. "\n")
end

function Updater.rawUrl(path)
    return Updater.HOST .. "/" .. Updater.REPO .. "/" .. Updater.BRANCH .. "/" .. path
end

-- ──────────────────────────────────────────────────────────
-- Порівняння локального та віддаленого маніфестів
-- status: new | update | repair | modified | current | newer | legacy
-- ──────────────────────────────────────────────────────────
function Updater.compare(localM, remote)
    local fs = getFs()
    local entries = {}
    for _, id in ipairs(remote.order) do
        local rc = remote.components[id]
        local lc = localM and localM.components[id]
        local present, missing, changed = 0, 0, 0
        local total = 0
        for _, f in ipairs(rc.files) do
            total = total + (f.size or 0)
            if fs.exists(f.target) then
                present = present + 1
                local ok, sz = pcall(fs.size, f.target)
                if ok and f.size and f.size > 0 and sz ~= f.size then changed = changed + 1 end
            else
                missing = missing + 1
            end
        end
        local status
        if lc then
            local cmp = Updater.compareVersions(lc.version, rc.version)
            if cmp < 0 then status = "update"
            elseif cmp > 0 then status = "newer"
            elseif missing > 0 then status = "repair"
            elseif changed > 0 then status = "modified"
            else status = "current" end
        else
            status = (present > 0) and "legacy" or "new"
        end
        entries[#entries + 1] = {
            id = id, name = rc.name, remoteVer = rc.version,
            localVer = lc and lc.version or (present > 0 and "?" or "-"),
            status = status, reboot = rc.reboot, requires = rc.requires,
            files = rc.files, totalSize = total, missing = missing, changed = changed,
        }
    end
    return entries
end

function Updater.needsAction(status)
    return status == "update" or status == "new" or status == "repair"
        or status == "modified" or status == "legacy"
end

-- ──────────────────────────────────────────────────────────
-- Jobs (корутини)
-- ──────────────────────────────────────────────────────────
local Job = {}
Job.__index = Job

local function newJob(kind, fn)
    local j = setmetatable({kind = kind, state = "running", phase = "", detail = "",
                            progress = 0, log = {}, cancellable = true}, Job)
    j.co = coroutine.create(function() return fn(j) end)
    return j
end

function Job:say(msg)
    self.log[#self.log + 1] = msg
    if #self.log > 300 then table.remove(self.log, 1) end
end

function Job:pause()
    if self.cancelled and self.cancellable then error(CANCEL, 0) end
    coroutine.yield()
end

function Job:cancel()
    if self.state == "running" and self.cancellable then self.cancelled = true end
end

function Job:step()
    if self.state ~= "running" then return self.state end
    local ok, a, b = coroutine.resume(self.co)
    if not ok then
        if a == CANCEL then
            self.state = "cancelled"; self.err = "Скасовано користувачем"
        else
            self.state = "error"; self.err = "Внутрішня помилка: " .. tostring(a)
        end
        -- обрив до підміни файлів: прибрати тимчасові файли
        if self.kind == "update" and self.cancellable then
            pcall(removeTree, getFs(), Updater.STAGE_DIR)
        end
    elseif coroutine.status(self.co) == "dead" then
        if a then self.state = "done"; self.result = b
        else self.state = "error"; self.err = tostring(b) end
    end
    if self.state ~= "running" and self.onFinish then pcall(self.onFinish, self) end
    return self.state
end

local function getNet()
    if _G._FixNet then return _G._FixNet end
    _G._FixNet = dofile("/system/lib/net.lua")
    return _G._FixNet
end

local function download(job, url, maxBytes, label)
    local Net = getNet()
    local req = Net.get(url, {maxBytes = maxBytes})
    while true do
        local st = req:step()
        if st == "done" then return req end
        if st == "error" then
            local why = req.errTitle or "Помилка мережі"
            if req.errRaw then why = why .. " (" .. tostring(req.errRaw):sub(1, 80) .. ")" end
            return nil, why
        end
        job.detail = string.format("%s %d КБ", label or "", math.floor((req.bytes or req.rawLen or 0) / 1024))
        job:pause()
    end
end

-- ── CHECK ────────────────────────────────────────────────
function Updater.check()
    Updater.loadConfig()
    return newJob("check", function(j)
        j.phase = "Завантаження маніфесту з GitHub…"
        j:say("GET " .. Updater.rawUrl("manifest.txt"))
        local req, err = download(j, Updater.rawUrl("manifest.txt"), 96 * 1024, "manifest")
        if not req then return false, err end
        if req.status ~= 200 then
            return false, "GitHub повернув HTTP " .. tostring(req.status) ..
                          " (перевірте репозиторій/гілку: " .. Updater.REPO .. "@" .. Updater.BRANCH .. ")"
        end
        local remote = Updater.parseManifest(req.body)
        if not remote.os or next(remote.components) == nil then
            return false, "Маніфест порожній або пошкоджений"
        end
        local localM = Updater.loadLocal()
        j.phase = "Порівняння версій…"
        local entries = Updater.compare(localM, remote)
        j:say("Знайдено компонентів: " .. #entries)
        return true, {remote = remote, localM = localM, entries = entries}
    end)
end

-- ── Резервні копії ───────────────────────────────────────
local function relPath(target) return (target:gsub("^/", "")) end

local function nextBackupId(fs)
    local max = 0
    if fs.exists(Updater.BACKUP_DIR) then
        for _, name in ipairs(fs.list(Updater.BACKUP_DIR) or {}) do
            local n = tonumber(name:match("^b(%d+)"))
            if n and n > max then max = n end
        end
    end
    return string.format("b%04d", max + 1)
end

local function readMeta(fs, id)
    local path = Updater.BACKUP_DIR .. "/" .. id .. "/meta.txt"
    if not fs.exists(path) then return nil end
    local text = readAll(fs, path)
    if not text then return nil end
    local meta = {id = id, files = {}, complete = false}
    for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local k, v = line:match("^(%w+)=(.*)$")
        if k then
            meta[k] = v
        else
            local t = splitBar(line)
            if t[1] == "file" then
                meta.files[#meta.files + 1] = {target = t[2], existed = (t[3] == "1"),
                                               size = tonumber(t[4]) or 0}
            end
        end
    end
    meta.complete = (meta.complete == "1" or meta.complete == true)
    return meta
end

function Updater.listBackups()
    local fs = getFs()
    local out = {}
    if fs.exists(Updater.BACKUP_DIR) then
        for _, name in ipairs(fs.list(Updater.BACKUP_DIR) or {}) do
            local id = name:gsub("/$", "")
            if id:match("^b%d+$") then
                local meta = readMeta(fs, id)
                if meta and meta.complete then
                    local size = 0
                    for _, f in ipairs(meta.files) do if f.existed then size = size + f.size end end
                    out[#out + 1] = {id = id, label = meta.label or "", os = meta.os or "?",
                                     files = #meta.files, size = size, meta = meta}
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.id > b.id end)
    return out
end

function Updater.deleteBackup(id)
    if not tostring(id):match("^b%d+$") then return false end
    return removeTree(getFs(), Updater.BACKUP_DIR .. "/" .. id)
end

local function pruneBackups(fs, keep)
    local list = Updater.listBackups()
    -- список відсортовано від нових до старих: усе після MAX_BACKUPS-го видаляємо
    for i = Updater.MAX_BACKUPS + 1, #list do
        local b = list[i]
        if not (keep and keep[b.id]) then removeTree(fs, Updater.BACKUP_DIR .. "/" .. b.id) end
    end
    -- незавершені копії (обрив живлення) теж прибираємо
    if fs.exists(Updater.BACKUP_DIR) then
        for _, name in ipairs(fs.list(Updater.BACKUP_DIR) or {}) do
            local id = name:gsub("/$", "")
            if id:match("^b%d+$") then
                local meta = readMeta(fs, id)
                if not meta or not meta.complete then removeTree(fs, Updater.BACKUP_DIR .. "/" .. id) end
            end
        end
    end
end

-- targets: список шляхів на диску. Повертає id або nil, err
local function createBackup(j, fs, targets, label)
    local id = nextBackupId(fs)
    local dir = Updater.BACKUP_DIR .. "/" .. id
    if not mkdirs(fs, dir .. "/files") then return nil, "Не вдалося створити " .. dir end
    local lines = {"backup=1", "id=" .. id, "label=" .. label,
                   "os=" .. Updater.localOsVersion()}
    local hadMf = fs.exists(Updater.LOCAL_MF)
    lines[#lines + 1] = "hadManifest=" .. (hadMf and "1" or "0")
    for i, target in ipairs(targets) do
        j.detail = "Копія: " .. target
        if fs.exists(target) then
            local dst = dir .. "/files/" .. relPath(target)
            mkdirs(fs, parentOf(dst))
            local ok, err = copyFile(fs, target, dst, function() j:pause() end)
            if not ok then removeTree(fs, dir); return nil, "Копіювання: " .. tostring(err) end
            lines[#lines + 1] = table.concat({"file", target, "1", tostring(fs.size(target))}, "|")
        else
            lines[#lines + 1] = table.concat({"file", target, "0", "0"}, "|")
        end
        j.progress = i / math.max(1, #targets)
        j:pause()
    end
    if hadMf then
        local ok = copyFile(fs, Updater.LOCAL_MF, dir .. "/manifest.txt")
        if not ok then removeTree(fs, dir); return nil, "Не вдалося зберегти маніфест" end
    end
    lines[#lines + 1] = "complete=1"
    if not writeAll(fs, dir .. "/meta.txt", table.concat(lines, "\n") .. "\n") then
        removeTree(fs, dir); return nil, "Не вдалося записати meta.txt"
    end
    return id
end

local function needsReboot(target)
    return target == "/init.lua" or target:match("^/system/[%w_]+%.lua$") ~= nil
        or target:match("^/system/language/") ~= nil or target == "/version.txt"
end

-- Відновлення файлів із копії (без створення нових копій)
local function restoreFromBackup(j, fs, meta)
    local dir = Updater.BACKUP_DIR .. "/" .. meta.id
    local reboot = false
    for i, f in ipairs(meta.files) do
        j.detail = "Відновлення: " .. f.target
        if f.existed then
            local src = dir .. "/files/" .. relPath(f.target)
            mkdirs(fs, parentOf(f.target))
            local tmp = f.target .. ".rst"
            local ok, err = copyFile(fs, src, tmp)
            if not ok then pcall(fs.remove, tmp); return false, "Відновлення " .. f.target .. ": " .. tostring(err) end
            if fs.exists(f.target) then fs.remove(f.target) end
            if not fs.rename(tmp, f.target) then
                local ok2 = copyFile(fs, tmp, f.target)
                pcall(fs.remove, tmp)
                if not ok2 then return false, "Не вдалося замінити " .. f.target end
            end
            if fs.size(f.target) ~= f.size then
                return false, "Розмір після відновлення не збігається: " .. f.target
            end
        else
            if fs.exists(f.target) then fs.remove(f.target) end
        end
        if needsReboot(f.target) then reboot = true end
        j.progress = i / math.max(1, #meta.files)
        j:pause()
    end
    -- маніфест версій
    if meta.hadManifest == "1" and fs.exists(dir .. "/manifest.txt") then
        copyFile(fs, dir .. "/manifest.txt", Updater.LOCAL_MF)
    elseif meta.hadManifest == "0" and fs.exists(Updater.LOCAL_MF) then
        fs.remove(Updater.LOCAL_MF)
    end
    return true, reboot
end

-- ── UPDATE ───────────────────────────────────────────────
-- entries: результат compare(); ids: множина вибраних компонентів {id=true}
function Updater.update(remote, entries, ids)
    return newJob("update", function(j)
        local fs = getFs()
        local Net = getNet()

        -- 1. Вибір компонентів + залежності
        local byId = {}
        for _, e in ipairs(entries) do byId[e.id] = e end
        local chosen, order = {}, {}
        local function add(id)
            if chosen[id] or not byId[id] then return end
            chosen[id] = true
            for _, r in ipairs(byId[id].requires or {}) do
                local dep = byId[r]
                if dep and Updater.needsAction(dep.status) then add(r) end
            end
            order[#order + 1] = id
        end
        for _, e in ipairs(entries) do if ids[e.id] then add(e.id) end end
        if #order == 0 then return false, "Нічого оновлювати" end

        local files, seen, total = {}, {}, 0
        for _, id in ipairs(order) do
            for _, f in ipairs(byId[id].files) do
                if not seen[f.target] then
                    seen[f.target] = true
                    files[#files + 1] = f
                    total = total + (f.size or 0)
                end
            end
        end
        j:say("Компоненти: " .. table.concat(order, ", "))
        j:say(string.format("Файлів: %d, %d КБ", #files, math.ceil(total / 1024)))

        -- 2. Перевірка місця та пам'яті
        local okSp, spaceTotal = pcall(fs.spaceTotal)
        local okUs, spaceUsed  = pcall(fs.spaceUsed)
        if okSp and okUs and spaceTotal and spaceUsed then
            local free = spaceTotal - spaceUsed
            local need = total * 2 + Updater.SPACE_MARGIN
            if free < need then
                return false, string.format("Недостатньо місця на диску: потрібно ~%d КБ, вільно %d КБ",
                    math.ceil(need / 1024), math.floor(free / 1024))
            end
        end
        local biggest = 0
        for _, f in ipairs(files) do if (f.size or 0) > biggest then biggest = f.size end end
        if biggest + 2048 > Net.memoryLimit() then
            return false, string.format("Недостатньо вільної RAM для файлу %d КБ (ліміт %d КБ). Закрийте програми.",
                math.ceil(biggest / 1024), math.floor(Net.memoryLimit() / 1024))
        end

        -- 3. Staging: завантаження + перевірка
        removeTree(fs, Updater.STAGE_DIR)
        if not mkdirs(fs, Updater.STAGE_DIR) then return false, "Не вдалося створити " .. Updater.STAGE_DIR end

        local function fail(msg)
            removeTree(fs, Updater.STAGE_DIR)
            return false, msg
        end

        for i, f in ipairs(files) do
            j.phase = string.format("Завантаження %d/%d: %s", i, #files, f.path)
            j.progress = (i - 1) / #files * 0.6
            local req, err = download(j, Updater.rawUrl(f.path), (f.size or 0) + 4096, f.path)
            if not req then return fail(f.path .. ": " .. tostring(err)) end
            if req.status ~= 200 then return fail(f.path .. ": HTTP " .. tostring(req.status)) end
            local body = req.body
            req = nil
            if #body ~= f.size then
                return fail(string.format("%s: розмір %d ≠ очікуваних %d (файл обірвано або репозиторій змінився)",
                    f.path, #body, f.size))
            end
            if f.adler and f.adler ~= "" and Updater.adler32(body) ~= f.adler then
                return fail(f.path .. ": контрольна сума не збігається")
            end
            if f.target:match("%.lua$") then
                local chunk, cerr = load(body, "=" .. f.path)
                if not chunk then return fail(f.path .. ": синтаксична помилка: " .. tostring(cerr)) end
            end
            local stagePath = Updater.STAGE_DIR .. "/" .. i .. ".dat"
            if not writeAll(fs, stagePath, body) or fs.size(stagePath) ~= #body then
                return fail("Не вдалося записати " .. stagePath .. " (диск повний або захищений від запису?)")
            end
            f._stage = stagePath
            body = nil
            j:say("✓ " .. f.path)
            j:pause()
        end

        -- 4. Резервна копія
        j.phase = "Резервна копія поточних файлів…"
        local targets = {}
        for _, f in ipairs(files) do targets[#targets + 1] = f.target end
        local label = "Перед оновленням: " .. table.concat(order, ", ")
        local backupId, berr = createBackup(j, fs, targets, label)
        if not backupId then return fail("Резервна копія не створена: " .. tostring(berr)) end
        j:say("Резервна копія " .. backupId)

        -- 5. Підміна файлів (точка неповернення для скасування)
        j.cancellable = false
        j.phase = "Встановлення файлів…"
        local reboot = false
        for i, f in ipairs(files) do
            j.progress = 0.6 + (i / #files) * 0.35
            j.detail = f.target
            mkdirs(fs, parentOf(f.target))
            local okMove = false
            if fs.exists(f.target) then fs.remove(f.target) end
            if fs.rename(f._stage, f.target) then
                okMove = true
            else
                okMove = copyFile(fs, f._stage, f.target)
            end
            if not okMove or not fs.exists(f.target) or fs.size(f.target) ~= f.size then
                j:say("✗ " .. f.target .. " - помилка, відкат")
                local meta = readMeta(fs, backupId)
                local rok, rr = restoreFromBackup(j, fs, meta)
                removeTree(fs, Updater.STAGE_DIR)
                if rok then
                    return false, "Не вдалося встановити " .. f.target .. ". Систему відкотено до копії " .. backupId .. "."
                end
                return false, "Не вдалося встановити " .. f.target .. " і відкат теж не вдався: " ..
                              tostring(rr) .. ". Відновіть файли з " .. Updater.BACKUP_DIR .. "/" .. backupId
            end
            if needsReboot(f.target) then reboot = true end
            j:pause()
        end

        -- 6. Локальний маніфест
        j.phase = "Збереження версій…"
        local localM = Updater.loadLocal() or {components = {}, order = {}, log = {}}
        local coreUpdated = false
        for _, id in ipairs(order) do
            local rc = remote.components[id]
            if not localM.components[id] then localM.order[#localM.order + 1] = id end
            localM.components[id] = rc
            if id == "core" then coreUpdated = true end
        end
        if coreUpdated or not localM.os then localM.os = remote.os end
        localM.repo, localM.branch = Updater.REPO, Updater.BRANCH
        localM.log = remote.log
        writeAll(fs, Updater.LOCAL_MF, Updater.serializeManifest(localM))

        removeTree(fs, Updater.STAGE_DIR)
        pruneBackups(fs, {[backupId] = true})

        -- кеш бібліотек міг застаріти
        _G._FixNet, _G._FixHtml = nil, nil

        j.phase = "Готово"; j.progress = 1
        j:say("Оновлено компонентів: " .. #order)
        return true, {backup = backupId, reboot = reboot, installed = order}
    end)
end

-- ── ROLLBACK ─────────────────────────────────────────────
function Updater.rollback(id)
    return newJob("rollback", function(j)
        local fs = getFs()
        local meta = readMeta(fs, id)
        if not meta or not meta.complete then return false, "Копія " .. tostring(id) .. " пошкоджена або не існує" end

        j.phase = "Перевірка резервної копії…"
        local dir = Updater.BACKUP_DIR .. "/" .. id
        for _, f in ipairs(meta.files) do
            if f.existed then
                local p = dir .. "/files/" .. relPath(f.target)
                if not fs.exists(p) or fs.size(p) ~= f.size then
                    return false, "Копія неповна: немає " .. f.target
                end
            end
        end
        j:pause()

        j.phase = "Збереження поточного стану (можна скасувати відкат)…"
        local targets = {}
        for _, f in ipairs(meta.files) do targets[#targets + 1] = f.target end
        local preId, perr = createBackup(j, fs, targets, "Перед відкатом до " .. id)
        if not preId then return false, "Не вдалося зберегти поточний стан: " .. tostring(perr) end
        j:say("Поточний стан збережено як " .. preId)

        j.cancellable = false
        j.phase = "Відновлення файлів…"
        local ok, reboot = restoreFromBackup(j, fs, meta)
        if not ok then
            return false, tostring(reboot) .. " (поточний стан у копії " .. preId .. ")"
        end
        pruneBackups(fs, {[id] = true, [preId] = true})
        _G._FixNet, _G._FixHtml = nil, nil
        j.phase = "Готово"; j.progress = 1
        j:say("Відкат до " .. id .. " виконано")
        return true, {backup = id, undo = preId, reboot = reboot, os = meta.os}
    end)
end

return Updater
