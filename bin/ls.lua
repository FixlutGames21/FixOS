-- simple ls
local fs = require("filesystem")
local args = { ... }
local path = args[1] or "."
for name in fs.list(path) do
  print(name)
end
