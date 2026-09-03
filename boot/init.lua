-- =================================================================
-- FixOS 4.0.2 - init.lua
-- Повністю переписаний для OpenComputers
--
-- КРИТИЧНІ ПРАВИЛА OC які раніше порушувались:
--   1. НЕ перевизначати _G.error через shutdown() -- це і давало
--      "computer halted" замість нормального повідомлення
--   2. component.list() повертає ітератор, не масив
--   3. pcall треба скрізь де є fs/gpu виклики
--   4. os.sleep потрібен свій, бо OC не має os до init
-- =================================================================

-- -----------------------------------------------------------------
-- 0. Отримати GPU та Screen ОДРАЗУ (без зайвих оберток)
-- -----------------------------------------------------------------
local gpuAddr, screenAddr

for a in component.list("gpu")    do gpuAddr    = a; break end
for a in component.list("screen") do screenAddr = a; break end

-- Прив'язати GPU до екрану
if gpuAddr and screenAddr then
    pcall(component.invoke, gpuAddr, "bind", screenAddr)
    local ok, mw, mh = pcall(component.invoke, gpuAddr, "maxResolution")
    if ok and mw then
        pcall(component.invoke, gpuAddr, "setResolution",
              math.min(80, mw), math.min(25, mh))
    end
    pcall(component.invoke, gpuAddr, "setBackground", 0x000000)
    pcall(component.invoke, gpuAddr, "setForeground",  0x00FF00)
    pcall(component.invoke, gpuAddr, "fill", 1, 1, 80, 25, " ")
end

-- -----------------------------------------------------------------
-- 1. Мінімальний вивід на екран
-- -----------------------------------------------------------------
local row = 1

local function put(msg)
    if gpuAddr then
        pcall(component.invoke, gpuAddr, "set", 2, row, tostring(msg))
        row = row + 1
    end
end

put("FixOS 4.0.2 - init.lua")
put("------------------------")

-- -----------------------------------------------------------------
-- 2. os.sleep (потрібен раніше за все інше)
-- -----------------------------------------------------------------
local function sleep(sec)
    local t = computer.uptime() + (sec or 0)
    repeat computer.pullSignal(t - computer.uptime())
    until computer.uptime() >= t
end

-- -----------------------------------------------------------------
-- 3. Функція критичної помилки
--    НЕ викликає computer.shutdown() -- це давало "computer halted"
--    Просто малює BSoD і чекає, потім дає OC показати помилку
-- -----------------------------------------------------------------
local function bsod(msg)
    msg = tostring(msg or "unknown error")

    -- Намалювати синій екран
    pcall(function()
        pcall(component.invoke, gpuAddr, "setBackground", 0x0000AA)
        pcall(component.invoke, gpuAddr, "setForeground",  0xFFFFFF)
        pcall(component.invoke, gpuAddr, "fill", 1, 1, 80, 25, " ")
        pcall(component.invoke, gpuAddr, "set", 2,  4, "FixOS 4.0.2 - Boot Error")
        pcall(component.invoke, gpuAddr, "set", 2,  6, "Error:")
        -- Розбити повідомлення на рядки по 76 символів
        local line, r = 7, msg
        while #r > 0 do
            pcall(component.invoke, gpuAddr, "set", 4, line, r:sub(1, 74))
            r = r:sub(75)
            line = line + 1
            if line > 18 then break end
        end
        pcall(component.invoke, gpuAddr, "set", 2, 20, "Check /crash.log on boot disk.")
        pcall(component.invoke, gpuAddr, "set", 2, 22, "Press any key to reboot.")
    end)

    -- Зберегти crash.log
    pcall(function()
        local bAddr = computer.getBootAddress()
        if bAddr then
            local h = component.invoke(bAddr, "open", "/crash.log", "w")
            if h then
                component.invoke(bAddr, "write", h, "CRASH: " .. msg .. "\n")
                component.invoke(bAddr, "close", h)
            end
        end
    end)

    pcall(computer.beep, 150, 0.5)
    computer.pullSignal(15) -- чекати 15 сек або натискання клавіші
    computer.shutdown(true) -- перезавантажити
end

-- -----------------------------------------------------------------
-- 4. Boot filesystem
-- -----------------------------------------------------------------
put("Mounting boot FS...")

local bootAddr = computer.getBootAddress()
if not bootAddr then
    bsod("computer.getBootAddress() returned nil")
end

-- Перевіряємо що FS відповідає
local fsOk, fsTest = pcall(component.invoke, bootAddr, "exists", "/")
if not fsOk or not fsTest then
    bsod("Boot filesystem not accessible: " .. tostring(bootAddr))
end

-- Локальні виклики FS через component.invoke напряму (без proxy)
local function fsExists(path)
    local ok, r = pcall(component.invoke, bootAddr, "exists", path)
    return ok and r
end

local function fsOpen(path, mode)
    local ok, h = pcall(component.invoke, bootAddr, "open", path, mode or "r")
    if ok and h then return h end
    return nil
end

local function fsRead(h, n)
    local ok, d = pcall(component.invoke, bootAddr, "read", h, n or math.huge)
    if ok then return d end
    return nil
end

local function fsWrite(h, data)
    pcall(component.invoke, bootAddr, "write", h, data)
end

local function fsClose(h)
    pcall(component.invoke, bootAddr, "close", h)
end

local function fsMkdir(path)
    pcall(component.invoke, bootAddr, "makeDirectory", path)
end

-- -----------------------------------------------------------------
-- 5. loadfile / dofile
-- -----------------------------------------------------------------
put("Setting up loader...")

local function myLoadfile(path)
    if not fsExists(path) then
        return nil, "file not found: " .. path
    end

    local h = fsOpen(path, "r")
    if not h then
        return nil, "cannot open: " .. path
    end

    local parts = {}
    while true do
        local chunk = fsRead(h, 4096)
        if not chunk then break end
        parts[#parts + 1] = chunk
    end
    fsClose(h)

    local src = table.concat(parts)
    if #src == 0 then
        return nil, "file is empty: " .. path
    end

    local fn, err = load(src, "=" .. path, "bt", _G)
    if not fn then
        return nil, "compile error in " .. path .. ": " .. tostring(err)
    end

    return fn
end

_G.loadfile = myLoadfile

-- Критична версія для завантаження життєво важливих файлів під час
-- boot (наразі використовується лише неявно — сам init.lua вантажить
-- desktop.lua через myLoadfile() напряму, а не через dofile(), тому
-- цей шлях і так захищений). Лишаємо публічною на випадок, якщо
-- майбутній boot-код захоче явно "падати з BSOD" замість звичайної
-- помилки.
_G.dofileCritical = function(path)
    local fn, err = myLoadfile(path)
    if not fn then
        bsod("dofile(" .. tostring(path) .. "): " .. tostring(err))
        return
    end
    local ok, result = pcall(fn)
    if not ok then
        bsod("runtime error in " .. tostring(path) .. ": " .. tostring(result))
        return
    end
    return result
end

-- FIX (Stability Bug #4): раніше ЦЯ версія dofile() викликала bsod()
-- (=> повний reboot комп'ютера) при БУДЬ-ЯКІЙ помилці — навіть коли її
-- викликали не з boot-послідовності, а з рантайму звичайної програми
-- (notepad.lua, settings.lua, explorer.lua, mycomputer.lua,
-- terminal.lua, browser.lua усі роблять
-- `win._ui = dofile("/system/ui.lua")` при першому draw()).
-- Тимчасовий збій диска чи гонка при читанні файлу під час відкриття
-- ОДНОГО вікна перезавантажувала ВЕСЬ комп'ютер разом з усіма іншими
-- відкритими вікнами.
--
-- Тепер dofile() поводиться як звичайний Lua dofile: помилка
-- пробрасывается вгору звичайним error(), а не bsod'ом. Це безпечно,
-- бо desktop.lua вже й так огортає кожен program.draw/click/tick у
-- pcall (safeCall), тож помилка коректно ізолюється на рівні одного
-- вікна — трохи гірше, ніж повний краш системи.
_G.dofile = function(path)
    local fn, err = myLoadfile(path)
    if not fn then
        error("dofile(" .. tostring(path) .. "): " .. tostring(err), 0)
    end
    return fn()
end

-- -----------------------------------------------------------------
-- 6. require
-- -----------------------------------------------------------------
put("Setting up require...")

local _loaded = {}
_G.package = { loaded = _loaded, path = "/lib/?.lua" }

_G.require = function(name)
    if _loaded[name] ~= nil then
        return _loaded[name]
    end

    local paths = {
        "/lib/"        .. name .. ".lua",
        "/lib/"        .. name:gsub("%.", "/") .. ".lua",
        "/system/lib/" .. name .. ".lua",
    }

    for _, p in ipairs(paths) do
        if fsExists(p) then
            local fn, err = myLoadfile(p)
            if not fn then
                bsod("require('" .. name .. "'): " .. tostring(err))
                return nil
            end
            local ok, val = pcall(fn)
            if not ok then
                bsod("require run('" .. name .. "'): " .. tostring(val))
                return nil
            end
            _loaded[name] = (val ~= nil) and val or true
            return _loaded[name]
        end
    end

    -- Не знайшли -- НЕ викликаємо bsod, повертаємо nil
    -- (деякі модулі опціональні)
    return nil
end

-- -----------------------------------------------------------------
-- 7. component API (розширений wrapper)
-- -----------------------------------------------------------------
put("Building component API...")

-- Зберегти оригінал ПЕРЕД заміною
local _rawComp = component

local newComp = {}
newComp.list    = _rawComp.list
newComp.type    = _rawComp.type
newComp.slot    = _rawComp.slot
newComp.methods = _rawComp.methods
newComp.invoke  = _rawComp.invoke
newComp.doc     = _rawComp.doc

function newComp.proxy(addr)
    if not addr then return nil end
    local t
    local ok, r = pcall(_rawComp.type, addr)
    if ok then t = r end
    if not t then return nil end

    local proxy = { address = addr, type = t }

    local ok2, methods = pcall(_rawComp.methods, addr)
    if ok2 and methods then
        for name in pairs(methods) do
            local n = name -- closure capture
            proxy[n] = function(...)
                return _rawComp.invoke(addr, n, ...)
            end
        end
    end

    return proxy
end

function newComp.get(partial, wantType)
    for addr in _rawComp.list(wantType or "") do
        if addr:sub(1, #partial) == partial then
            return addr
        end
    end
    return nil
end

function newComp.isAvailable(typeName)
    -- list повертає ітератор; перша ітерація дає результат або nil
    return _rawComp.list(typeName)() ~= nil
end

-- FIX (Critical Bug #1): без цього metatable вирази на кшталт
-- `component.internet` або `component.gpu` (як пише звичайний OpenOS-код,
-- і як реально написані browser.lua / settings.lua) завжди повертали
-- nil, бо newComp — це проста таблиця без такого поля. Це ламало
-- Browser і Update Check НАЗАВЖДИ, навіть коли Internet Card
-- встановлена: `local net = component.internet` ставало nil, і
-- `net.request` кидало помилку "attempt to index a nil value" ще ДО
-- виклику pcall (бо аргументи pcall обчислюються заздалегідь).
--
-- Кешуємо результат через rawset, щоб не перебудовувати всі
-- method-closures при кожному зверненні (component.proxy() дорогий:
-- він ітерує component.methods() і створює N замикань).
--
-- ПРИМІТКА про hot-plug: якщо Internet Card / інший компонент
-- від'єднується і підключається "на льоту" під час роботи системи,
-- закешований проксі стане невалідним (виклики почнуть падати з
-- "no such component"). Для типового використання FixOS (стаціонарні
-- компоненти в корпусі комп'ютера) це прийнятний компроміс; якщо
-- потрібна повна підтримка hot-plug — приберіть rawset нижче ціною
-- продуктивності.
setmetatable(newComp, {
    __index = function(t, key)
        local addr = _rawComp.list(key)()
        if not addr then return nil end
        local p = newComp.proxy(addr)
        rawset(t, key, p)
        return p
    end
})

_G.component = newComp

-- -----------------------------------------------------------------
-- 8. os API
-- -----------------------------------------------------------------
put("Building os API...")

_G.os = {
    sleep = sleep,

    time = function()
        return math.floor(computer.uptime())
    end,

    clock = function()
        return computer.uptime()
    end,

    date = function(fmt, t)
        t   = tonumber(t) or computer.uptime()
        fmt = tostring(fmt or "%H:%M:%S")

        local h = math.floor(t / 3600) % 24
        local m = math.floor(t / 60)   % 60
        local s = math.floor(t)        % 60

        if fmt == "*t" then
            return {
                year=2000, month=1, day=1,
                hour=h, min=m, sec=s,
                wday=1, yday=1, isdst=false
            }
        end

        local r = fmt
        r = r:gsub("%%H", string.format("%02d", h))
        r = r:gsub("%%M", string.format("%02d", m))
        r = r:gsub("%%S", string.format("%02d", s))
        return r
    end,

    exit = function()
        computer.shutdown()
    end,
}

-- -----------------------------------------------------------------
-- 9. print (офіційний, після os)
-- -----------------------------------------------------------------
_G.print = function(...)
    local t = {...}
    local parts = {}
    for i = 1, #t do parts[i] = tostring(t[i]) end
    put(table.concat(parts, "\t"))
end

-- -----------------------------------------------------------------
-- 10. Перевірка критичних файлів
-- -----------------------------------------------------------------
put("Checking system files...")

local criticalFiles = {
    "/system/ui.lua",
    "/system/desktop.lua",
    "/system/lang.lua",
}

for _, f in ipairs(criticalFiles) do
    if not fsExists(f) then
        bsod("Missing system file: " .. f ..
             "\nPlease reinstall FixOS using installer.lua")
    end
end

put("All files OK.")

-- -----------------------------------------------------------------
-- 11. Запуск desktop
-- -----------------------------------------------------------------
put("Starting desktop...")
sleep(0.3)

local desktopFn, desktopErr = myLoadfile("/system/desktop.lua")
if not desktopFn then
    bsod("Cannot load desktop.lua:\n" .. tostring(desktopErr))
end

local ok, runErr = pcall(desktopFn)

if not ok then
    -- Зберегти crash.log з повним traceback
    pcall(function()
        local h = fsOpen("/crash.log", "w")
        if h then
            fsWrite(h, "Desktop crash at uptime=" ..
                    tostring(computer.uptime()) .. "\n")
            fsWrite(h, tostring(runErr) .. "\n")
            fsClose(h)
        end
    end)
    bsod("Desktop crashed:\n" .. tostring(runErr))
end

-- Desktop завершився нормально
put("Desktop exited normally.")
sleep(1)
computer.shutdown()