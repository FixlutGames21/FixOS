local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local http = component.http

local base_url = "https://raw.githubusercontent.com/Fixlut/FixOS/main"

local files = {
  ["/boot/init.lua"] = base_url .. "/boot/init.lua",
  ["/boot/kernel.lua"] = base_url .. "/boot/kernel.lua",
  ["/boot/shell.lua"] = base_url .. "/boot/shell.lua",
  ["/bin/echo.lua"] = base_url .. "/bin/echo.lua",
  ["/bin/ls.lua"] = base_url .. "/bin/ls.lua",
  ["/bin/cls.lua"] = base_url .. "/bin/cls.lua",
  ["/bin/calc.lua"] = base_url .. "/bin/calc.lua",
}

for path, url in pairs(files) do
  fs.makeDirectory(fs.path(path))
  local handle, err = http.get(url)
  if handle then
    local content = handle.readAll()
    handle.close()
    local file = io.open(path,"w")
    file:write(content)
    file:close()
    print("Installed: "..path)
  else
    print("Failed: "..path.." -> "..err)
  end
end

print("Installation finished! Rebooting...")
computer.shutdown(true)
