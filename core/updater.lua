-- Installs a new release on the packaged desktop builds. The download is checked against the
-- SHA-256 published with the release before anything is replaced, so a failed or corrupted
-- download leaves the current game alone.
--   Linux:   the AppImage is downloaded next to itself, then swapped in with an atomic rename.
--   Windows: a running exe can't overwrite itself, so a small script waits for the game to exit,
--            copies the new files over it and starts it again.
-- Anything else (running from source, a .love, the browser, a folder we can't write to) gets a
-- notice with the download page instead.
local platform = require "core.platform"

local Updater = { state = "idle", progress = 0 }

local APPIMAGE, ZIP = "Deckshot-x86_64.AppImage", "Deckshot-windows-x64.zip"

local WORKER = [[
require "love.data"
require "love.filesystem"
local channel, url, dest, sha, extractTo = ...
local function finish(ok, message) channel:push({ ok = ok, message = message }) end
local code = os.execute('curl -L -s -S -f -m 1800 -o "' .. dest .. '" "' .. url .. '"')
if code ~= 0 and code ~= true then return finish(false, "The download failed") end
local f = io.open(dest, "rb")
if not f then return finish(false, "The download is missing") end
local data = f:read("*a")
f:close()
local got = love.data.encode("string", "hex", love.data.hash("sha256", data)):lower()
data = nil
collectgarbage()
if got ~= sha then
  os.remove(dest)
  return finish(false, "The download was damaged (checksum mismatch)")
end
if extractTo then
  local x = os.execute('tar -xf "' .. dest .. '" -C "' .. extractTo .. '"')
  if x ~= 0 and x ~= true then return finish(false, "Couldn't unpack the update") end
end
finish(true)
]]

local function writable(dir)
  local path = dir .. "/.deckshot_update_test"
  local f = io.open(path, "wb")
  if not f then return false end
  f:close()
  os.remove(path)
  return true
end

-- What this copy of the game can do: "appimage", "windows", or nil (notice only).
function Updater.kind()
  if Updater.kindOverride ~= nil then return Updater.kindOverride or nil end
  if platform.web or not love.filesystem.isFused() then return nil end
  local osName = love.system.getOS()
  if osName == "Linux" then
    local path = os.getenv("APPIMAGE")
    if path and path ~= "" and writable(path:match("^(.*)/[^/]*$") or ".") then return "appimage" end
  elseif osName == "Windows" then
    if writable(love.filesystem.getSourceBaseDirectory()) then return "windows" end
  end
  return nil
end

-- The release asset for this platform, or nil.
function Updater.asset(release)
  local kind = Updater.kind()
  return release and release.assets[kind == "windows" and ZIP or APPIMAGE]
end

local function toWindows(p) return (p:gsub("/", "\\")) end

function Updater.start(release)
  local kind = Updater.kind()
  local asset = Updater.asset(release)
  if not kind or not asset then
    Updater.state, Updater.error = "failed", "This copy of the game can't update itself."
    return
  end
  local dest, extractTo
  if kind == "appimage" then
    Updater.target = Updater.targetOverride or os.getenv("APPIMAGE")
    dest = Updater.target .. ".new"
  else
    local base = love.filesystem.getSaveDirectory() .. "/update"
    love.filesystem.remove("update")
    love.filesystem.createDirectory("update")
    love.filesystem.createDirectory("update/files")
    dest, extractTo = base .. "/" .. ZIP, base .. "/files"
    Updater.base = base
  end
  Updater.dest, Updater.size, Updater.kindRunning = dest, asset.size, kind
  Updater.channel = love.thread.newChannel()
  Updater.thread = love.thread.newThread(WORKER)
  Updater.thread:start(Updater.channel, asset.url, dest, asset.sha256, extractTo)
  Updater.state, Updater.progress = "downloading", 0
end

local function install()
  if Updater.kindRunning == "appimage" then
    local target = Updater.target
    os.execute('chmod +x "' .. Updater.dest .. '"')
    local ok, err = os.rename(Updater.dest, target)
    if not ok then
      Updater.state, Updater.error = "failed", "Couldn't replace the game: " .. tostring(err)
      os.remove(Updater.dest)
      return
    end
    if Updater.noRestart then
      Updater.state = "done"
      return
    end
    -- Clear what the running AppImage set, or the new one would start with the old libraries.
    os.execute('env -u LD_LIBRARY_PATH -u LD_PRELOAD -u APPDIR -u APPIMAGE -u ARGV0 -u OWD nohup "' .. target .. '" >/dev/null 2>&1 &')
    love.event.quit()
  else
    local base = toWindows(Updater.base)
    local game = toWindows(love.filesystem.getSourceBaseDirectory())
    local script = base .. "\\apply.cmd"
    local lines = {
      "@echo off", "set tries=0", ":again",
      "timeout /t 1 /nobreak >nul",
      'robocopy "' .. base .. '\\files\\Deckshot" "' .. game .. '" /E /R:0 /W:0 /NFL /NDL /NJH /NJS >nul',
      "if %errorlevel% lss 8 goto done",
      "set /a tries+=1", "if %tries% lss 30 goto again",
      ":done", 'start "" "' .. game .. '\\Deckshot.exe"',
      'rmdir /s /q "' .. base .. '\\files"', 'del "' .. base .. "\\" .. ZIP .. '"', '(goto) 2>nul & del "%~f0"',
    }
    local f = io.open(script, "wb")
    if not f then
      Updater.state, Updater.error = "failed", "Couldn't write the update script"
      return
    end
    f:write(table.concat(lines, "\r\n") .. "\r\n")
    f:close()
    os.execute('start "" /min cmd /c "' .. script .. '"')
    love.event.quit()
  end
end

function Updater.update()
  if Updater.state ~= "downloading" then return end
  local f = Updater.dest and io.open(Updater.dest, "rb")
  if f then
    local size = f:seek("end")
    f:close()
    if Updater.size and Updater.size > 0 then Updater.progress = math.min(1, size / Updater.size) end
  end
  local err = Updater.thread:getError()
  if err then
    Updater.state, Updater.error = "failed", err
    return
  end
  local msg = Updater.channel:pop()
  if not msg then return end
  if not msg.ok then
    Updater.state, Updater.error = "failed", msg.message
    return
  end
  Updater.progress = 1
  Updater.state = "installing"
  install()
end

return Updater
