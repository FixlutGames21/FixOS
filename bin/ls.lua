local fs = require("filesystem")
for file in fs.list("/") do
  print(file)
end
