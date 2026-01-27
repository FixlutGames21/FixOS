local term = require("term")
local component = require("component")
local event = require("event")

term.clear()
local gpu = component.gpu
gpu.setBackground(0x0000AA)
gpu.setForeground(0xFFFFFF)

print("FixOS 2000 Calculator")
print("Enter expression (e.g. 2+2):")
print("")

local exp = io.read()

if exp and exp:match("^[0-9+%-%*/%. ()]+$") then
  local func, err = load("return " .. exp)
  if func then 
    local success, result = pcall(func)
    if success then
      print("= " .. tostring(result))
    else
      print("Error: " .. tostring(result))
    end
  else 
    print("Error: " .. tostring(err))
  end
else
  print("Error: Invalid expression")
  print("Use only: 0-9 + - * / . ( )")
end

print("")
print("Press any key to exit.")
event.pull("key_down")