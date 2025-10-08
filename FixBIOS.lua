local component = require("component")
local eeprom = component.eeprom

local bios = [[
local component = component
local computer = computer
local fs = component.proxy(component.list("filesystem")())
local bootPaths = {"/boot/fixos.lua", "/init.lua", "/os/init.lua"}

local function boot()
  for _, path in ipairs(bootPaths) do
    if fs.exists(path) then
      local f = io.open(path, "r")
      local code = f:read("*a")
      f:close()
      local ok, err = load(code, "="..path)
      if not ok then
        error("FixBIOS: Failed to load "..path..": "..tostring(err))
      end
      ok()
      return
    end
  end
  io.stderr:write("\nFixBIOS ERROR:\n  FixOS not found!\n  Insert system disk.\n")
end

boot()
]]

-- Записуємо BIOS у EEPROM
eeprom.set(bios)
eeprom.setLabel("FixBIOS")
print("✅ FixBIOS записано в EEPROM. Перезапусти комп і насолоджуйся FixOS!")
