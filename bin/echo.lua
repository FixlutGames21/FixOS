local args = {...}
if #args > 0 then
  print(table.concat(args, " "))
else
  print("")
end