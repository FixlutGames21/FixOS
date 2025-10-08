-- bin/ls.lua
local fs = require("filesystem")
local path = ...
if not path or path == "" then path = "/" end
for entry in fs.list(path) do
  print(entry)
end
