-- boot/kernel.lua
local term = require("term")
local fs = require("filesystem")
term.clear()
print("FixOS kernel loaded.")
-- start shell
local s, err = loadfile("/boot/shell.lua")
if not s then
  print("No shell found: "..tostring(err))
  return
end
s()
