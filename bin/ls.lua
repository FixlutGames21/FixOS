local fs = require("filesystem")
local args = {...}
local path = args[1] or "/"

if not fs.exists(path) then
  print("Path not found: " .. path)
  return
end

if fs.isDirectory(path) then
  local files = {}
  for file in fs.list(path) do
    table.insert(files, file)
  end
  table.sort(files)
  for _, file in ipairs(files) do
    print(file)
  end
else
  print(path)
end
