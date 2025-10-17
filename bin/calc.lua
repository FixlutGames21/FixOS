local term = require("term")
term.clear()
print("FixOS 2000 Calculator")
print("Enter expression (e.g. 2+2):")
local exp = io.read()
local result, err = load("return " .. exp)
if result then print("= " .. result()) else print("Error: " .. err) end
print("Press Enter to exit.")
term.read()
