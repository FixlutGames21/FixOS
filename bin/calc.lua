print("Simple FixOS Calculator")
io.write("Enter expression: ")
local exp = io.read()
local func, err = load("return "..exp)
if func then
  local ok, res = pcall(func)
  if ok then print("Result:", res) else print("Error in calculation") end
else
  print("Invalid expression")
end
