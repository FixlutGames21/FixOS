local term = require("term")
local event = require("event")
local component = require("component")

term.clear()
local gpu = component.gpu
gpu.setBackground(0x0000AA)
gpu.setForeground(0xFFFFFF)

print("FixOS Text Editor")
io.write("File name: ")
local path = io.read()

if not path or path == "" then
  print("No file specified.")
  print("Press any key to exit.")
  event.pull("key_down")
  return
end

local f, err = io.open(path, "w")
if not f then
  print("Error: " .. tostring(err))
  print("Press any key to exit.")
  event.pull("key_down")
  return
end

print("Type text (end with line containing only '.'):")
print("")

while true do
  local line = io.read()
  if line == "." then break end
  f:write(line .. "\n")
end

f:close()
print("")
print("Saved to: " .. path)
print("Press any key to exit.")
event.pull("key_down")