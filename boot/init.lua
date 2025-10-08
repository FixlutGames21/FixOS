-- boot/init.lua
local term = require("term")
term.clear()
print("FixOS init: starting kernel...")
local k, err = loadfile("/boot/kernel.lua")
if not k then
  print("Kernel missing or corrupted: "..tostring(err))
  return
end
k()
