-------------------------------------------------------
-- FixOS Installer PRO MAX v4 (with safe EEPROM flash)
-- by Fixlut 💿
-------------------------------------------------------
local component = require("component")
local term = require("term")
local fs = require("filesystem")
local shell = require("shell")
local computer = require("computer")

local gpu = component.isAvailable("gpu") and component.gpu or nil
local inet = component.isAvailable("internet") and component.internet or nil
local hasEEPROM = component.isAvailable("eeprom")

-- UI helpers
local function center(text)
  if not gpu then print(text) return end
  local w = ({gpu.getResolution()})[1]
  term.setCursor(math.max(1, (w - #text) // 2), select(2, term.getCursor()))
  print(text)
end

local function banner()
  term.clear()
  print("====================================")
  center("🚀  FIXOS INSTALLER  PRO  MAX v4  🚀")
  print("====================================")
  print()
end

local function bar(i, total)
  local p = math.floor((i / total) * 100)
  local filled = string.rep("█", p // 5)
  local empty = string.rep(" ", 20 - (p // 5))
  term.write(string.format("\r[%s%s] %d%%", filled, empty, p))
end

-- Start
banner()
print("Checking components...\n")

if not inet then
  io.stderr:write("❗ Warning: Internet card not found or disabled. Installer will try local fallback.\n")
end

-- Basic net test (best effort)
local function netOK()
  if not inet then return false end
  local ok, handle = pcall(inet.request, "http://example.com")
  if ok and handle then handle.close() return true end
  return false
end

if not netOK() then
  print("⚠️  HTTP test failed — continuing with fallback options.")
end

-- Files we want to pull (add/remove as needed)
local baseURL = "http://raw.githack.com/FixlutGames21/FixOS/main/"
local files = {
  "boot/init.lua",
  "boot/system.lua",
  "bin/shell.lua",
  "bin/ls.lua",
  "bin/edit.lua"
}

-- Download/install files
print("Installing FixOS...\n")
local total = #files
for i, path in ipairs(files) do
  local url = baseURL .. path
  local dest = "/" .. path
  fs.makeDirectory(fs.path(dest))

  local content = nil
  if netOK() then
    local ok, handle = pcall(inet.request, url)
    if ok and handle then
      content = ""
      for chunk in handle do content = content .. chunk end
      handle.close()
    end
  end

  -- fallback: local disk
  if (not content or content == "") and fs.exists("/disk/FixOS/" .. path) then
    local f = io.open("/disk/FixOS/" .. path, "r")
    content = f:read("*a")
    f:close()
  end

  if not content or content:match("^%s*<") then
    io.stderr:write("\n❌  Failed to obtain valid Lua for: " .. path .. "\n")
    io.stderr:write("   Check network or put files in /disk/FixOS/\n")
    return
  end

  local f = io.open(dest, "w")
  if f then f:write(content) f:close() end
  bar(i, total)
  os.sleep(0.05)
end

print("\n\n✅  FixOS files installed successfully!")

-- Create autorun
print("💾  Creating /autorun.lua ...")
local autorun = io.open("/autorun.lua", "w")
autorun:write([[
term.clear()
print("====================================")
print("        🪟 Welcome to FixOS 🪟       ")
print("====================================")
os.sleep(1)
shell.execute("/bin/shell.lua")
]])
autorun:close()
print("💾  autorun created.")

-- EEPROM flash routine (optional, safe)
if hasEEPROM then
  print("\n🛡️  EEPROM detected. You can optionally flash a custom BIOS (WARNING: risky).")
  io.write("Do you want to flash EEPROM with FixOS BIOS image? (y/n): ")
  local ans = io.read()
  if ans == "y" then
    -- BACKUP current EEPROM
    local ok, current = pcall(function()
      return component.eeprom.get()
    end)
    if not ok then
      io.stderr:write("❌  Cannot read EEPROM for backup. Aborting flash.\n")
    else
      -- save backup
      local bfile = "/eeprom_backup.lua"
      local bf = io.open(bfile, "w")
      if bf then
        bf:write(current)
        bf:close()
        print("🔒  EEPROM backup saved to: " .. bfile)
      else
        io.stderr:write("❌  Failed to write EEPROM backup file. Aborting.\n")
      end

      -- Obtain new EEPROM image (try network then local)
      local eepromData = nil
      local eurl = baseURL .. "eeprom.img"
      if netOK() then
        local ok2, handle = pcall(inet.request, eurl)
        if ok2 and handle then
          eepromData = ""
          for chunk in handle do eepromData = eepromData .. chunk end
          handle.close()
        end
      end
      if (not eepromData or eepromData == "") and fs.exists("/disk/FixOS/eeprom.img") then
        local ef = io.open("/disk/FixOS/eeprom.img","r")
        eepromData = ef:read("*a")
        ef:close()
      end

      if not eepromData or eepromData:match("^%s*<") then
        io.stderr:write("❌  Cannot obtain valid EEPROM image. Aborting flash.\n")
      else
        print("\n!!! VERY IMPORTANT !!!")
        print("Writing to EEPROM will overwrite current BIOS. This may prevent booting.")
        print("If you want to proceed, type exactly: FORMAT EEPROM")
        io.write("> ")
        local confirm = io.read()
        if confirm == "FORMAT EEPROM" then
          -- attempt write
          local ok3, err = pcall(function() component.eeprom.set(eepromData) end)
          if ok3 then
            print("✅  EEPROM flashed successfully.")
            -- create restore helper
            local restore = io.open("/eeprom_restore.lua","w")
            restore:write([[
local component = require("component")
local f = io.open("/eeprom_backup.lua","r")
if not f then print("No backup found") return end
local data = f:read("*a")
f:close()
component.eeprom.set(data)
print("EEPROM restored from /eeprom_backup.lua")
]])
            restore:close()
            print("🔁  Created /eeprom_restore.lua to restore backup if needed.")
          else
            io.stderr:write("❌  EEPROM write failed: " .. tostring(err) .. "\n")
            io.stderr:write("You can restore backup with /eeprom_restore.lua (if exists) manually.\n")
          end
        else
          print("Aborted EEPROM flash.")
        end
      end
    end
  else
    print("Skipped EEPROM flash.")
  end
else
  print("\nℹ️  No EEPROM component detected; skipping EEPROM section.")
end

-- Final prompt
print("\nAll done. Reboot recommended.")
local choice
repeat
  io.write("Reboot now? (y/n): ")
  choice = io.read()
until choice == "y" or choice == "n"

if choice == "y" then
  print("Rebooting...")
  os.sleep(1)
  computer.shutdown(true)
end
