-- boot/shell.lua
local term = require("term")
local fs = require("filesystem")

local function splitWords(s)
  local t = {}
  for word in s:gmatch("%S+") do table.insert(t, word) end
  return t
end

term.clear()
print("Welcome to FixOS shell. Type 'help'")

while true do
  io.write("FixOS> ")
  local line = io.read()
  if not line then break end
  line = line:gsub("^%s+",""):gsub("%s+$","")
  if line == "" then goto continue end

  local parts = splitWords(line)
  local cmd = parts[1]
  local args = {}
  for i=2,#parts do table.insert(args, parts[i]) end

  if cmd == "exit" then
    print("Bye.")
    break
  elseif cmd == "help" then
    print("Commands: help, exit, ls, echo, edit, cls, calc")
    goto continue
  end

  local binpath = "/bin/" .. cmd .. ".lua"
  if fs.exists(binpath) then
    local f, err = loadfile(binpath)
    if not f then
      print("Failed to load "..cmd..": "..tostring(err))
    else
      -- provide args in global arg table and also pass as varargs
      _G.arg = args
      local ok, res = pcall(f, table.unpack(args))
      if not ok then print("Error running "..cmd..": "..tostring(res)) end
      _G.arg = nil
    end
  else
    print("Command not found: "..cmd)
  end

  ::continue::
end
