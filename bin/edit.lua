-- bin/edit.lua
-- Very simple single-line editor or write file content
local fs = require("filesystem")
local path = ...
if not path or path == "" then
  print("Usage: edit <path>")
  return
end
print("Editing:", path)
print("Enter text. Finish with a single line containing only :wq")
local lines = {}
while true do
  local l = io.read()
  if not l then break end
  if l == ":wq" then break end
  table.insert(lines, l)
end
local ok, err = pcall(function()
  fs.makeDirectory(fs.path(path))
  local f = io.open(path, "w")
  f:write(table.concat(lines, "\n"))
  f:close()
end)
if not ok then print("Save error: "..tostring(err)) else print("Saved "..path) end
