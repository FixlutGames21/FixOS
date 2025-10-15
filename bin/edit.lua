-- tiny edit: edit <path>
local fs = require("filesystem")
local path = ( ... )
if not path then print("Usage: edit <path>") return end
local f = io.open(path, "r")
local content = ""
if f then content = f:read("*a"); f:close() end
print("Enter content. End with a single line containing only EOF")
local lines = {}
while true do
  local line = io.read()
  if not line or line == "EOF" then break end
  table.insert(lines, line)
end
local out = io.open(path, "w")
out:write(table.concat(lines, "\n"))
out:close()
print("Saved.")
