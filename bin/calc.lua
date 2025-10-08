-- bin/calc.lua
io.write("Expression> ")
local expr = io.read()
if not expr or expr == "" then print("No expression") return end
local f, err = load("return " .. expr)
if not f then
  print("Invalid expression: "..tostring(err))
  return
end
local ok, res = pcall(f)
if ok then print("Result: "..tostring(res)) else print("Error evaluating expression") end
