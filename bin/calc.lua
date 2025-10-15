-- tiny calc: calc <expr> e.g. calc 2+2*3
local args = { ... }
local expr = table.concat(args, " ")
local ok, res = pcall(load("return " .. expr))
if ok then
  local ok2, val = pcall(res)
  if ok2 then print(val) else print("runtime error") end
else
  print("bad expression")
end
