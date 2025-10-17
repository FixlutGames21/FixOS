local term = require("term")
local fs = require("filesystem")
term.clear()
print("FixOS Text Editor")
io.write("File name: ")
local path = io.read()
local f = io.open(path, "w")
print("Type text (end with a single line '.'): ")
while true do
  local line = io.read()
  if line == "." then break end
  f:write(line .. "\n")
end
f:close()
print("Saved.")
term.read()
