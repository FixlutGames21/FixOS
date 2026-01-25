local fs = require("filesystem")
local args = {...}
local path = args[1] or "/"

if not fs.exists(path) then
  print("Path not found: " .. path)
  return
end

if fs.isDirectory(path) then
  for file in fs.list(path) do
    print(file)
  end
else
  print(path)
end