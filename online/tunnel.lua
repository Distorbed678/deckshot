-- A free Cloudflare quick tunnel to the LAN host, started by the game (desktop only).
-- It gives the host's browser page a public https address, so friends anywhere can open it.
-- cloudflared is used from the PATH if it's installed; otherwise a pinned version is downloaded
-- once into the save folder and checked against its SHA-256 before it is ever run.
--   Tunnel.start(port)  Tunnel.update()  Tunnel.stop()
--   Tunnel.state: "off" | "downloading" | "starting" | "ready" | "failed";  Tunnel.url, .error, .progress
local platform = require "core.platform"

local Tunnel = { state = "off" }

local VERSION = "2026.10.7"
local BASE = "https://github.com/cloudflare/cloudflared/releases/download/" .. VERSION .. "/"
local BUILDS = {
  Linux = { file = "cloudflared-linux-amd64", save = "cloudflared", size = 40274445,
    sha256 = "1f99fb518b83dec2ba8d870a7cc991d82a77e6196295a3d2754ba17ab9f91872" },
  Windows = { file = "cloudflared-windows-amd64.exe", save = "cloudflared.exe", size = 55390512,
    sha256 = "2493dbc168923bb3e59e5e7716f71deced92992eea9acd6e9d74f84ac7751343" },
}
local START_TIMEOUT = 45

-- Runs in a thread: downloads (if asked), then runs cloudflared and reports what it prints.
local WORKER = [[
require "love.data"
local ch, windows, url, dest, sha, command = ...
local function quote(s) return '"' .. s .. '"' end
if url then
  local part = dest .. ".part"
  os.remove(part)
  local cmd = "curl -L --fail -s -o " .. quote(part) .. " " .. quote(url)
  local ok = os.execute(windows and (quote(cmd)) or cmd)
  local f = io.open(part, "rb")
  local data = f and f:read("*a")
  if f then f:close() end
  if not data or #data == 0 then
    os.remove(part)
    ch:push({ "failed", "The download failed. Check your internet connection." })
    return
  end
  local hex = love.data.encode("string", "hex", love.data.hash("sha256", data))
  data = nil
  if hex ~= sha then
    os.remove(part)
    ch:push({ "failed", "The download didn't match its checksum, so it was thrown away." })
    return
  end
  os.remove(dest)
  if not os.rename(part, dest) then
    ch:push({ "failed", "Couldn't save cloudflared." })
    return
  end
  if not windows then os.execute("chmod +x " .. quote(dest)) end
end
ch:push({ "starting" })
local pipe = io.popen(command, "r")
if not pipe then
  ch:push({ "failed", "Couldn't start cloudflared." })
  return
end
local last = ""
for line in pipe:lines() do
  local pid = line:match("^PID:(%d+)")
  if pid then ch:push({ "pid", tonumber(pid) }) end
  local found = line:match("https://[%w%-]+%.trycloudflare%.com")
  if found then ch:push({ "url", found }) end
  if line:find("ERR", 1, true) or line:find("error", 1, true) then last = line end
end
pipe:close()
ch:push({ "exit", last })
]]

local function quote(s) return '"' .. s .. '"' end

-- Is cloudflared already installed on this machine?
local function onPath(windows)
  local cmd = windows and "where cloudflared >nul 2>&1" or "command -v cloudflared >/dev/null 2>&1"
  local ok = os.execute(cmd)
  return ok == true or ok == 0
end

function Tunnel.available()
  if platform.web or not love.thread then return false end
  local os_ = love.system.getOS()
  if not BUILDS[os_] then return false end
  return (jit and jit.arch == "x64") or onPath(os_ == "Windows")
end

-- How big the one-time download is (MB), or nil when cloudflared is already here.
function Tunnel.downloadSize()
  local os_ = love.system.getOS()
  local build = BUILDS[os_]
  if not build then return nil end
  if onPath(os_ == "Windows") or love.filesystem.getInfo(build.save) then return nil end
  return math.floor(build.size / 1e6 + 0.5)
end

function Tunnel.start(port)
  if Tunnel.state == "downloading" or Tunnel.state == "starting" or Tunnel.state == "ready" then return end
  Tunnel.url, Tunnel.error, Tunnel.pid, Tunnel.progress = nil, nil, nil, 0
  local os_ = love.system.getOS()
  local build = BUILDS[os_]
  if platform.web or not build then
    Tunnel.state, Tunnel.error = "failed", "Tunnels need the Windows or Linux version of the game."
    return
  end
  local windows = os_ == "Windows"
  local bin, url, dest
  if onPath(windows) then
    bin = "cloudflared"
  else
    dest = love.filesystem.getSaveDirectory() .. "/" .. build.save
    if windows then dest = dest:gsub("/", "\\") end
    bin = dest
    if not love.filesystem.getInfo(build.save) then
      if not (jit and jit.arch == "x64") then
        Tunnel.state, Tunnel.error = "failed", "Install cloudflared yourself on this kind of computer, then try again."
        return
      end
      love.filesystem.createDirectory("") -- make sure the save folder exists
      url = BASE .. build.file
    end
  end
  local args = " tunnel --no-autoupdate --url http://localhost:" .. port .. " 2>&1"
  local command
  if windows then
    command = quote(quote(bin) .. args)
  else
    -- The shell prints its process id, then becomes cloudflared, so we know what to stop later.
    command = "sh -c 'echo PID:$$; exec " .. quote(bin) .. args .. "'"
  end
  Tunnel.windows = windows
  Tunnel.part = url and (build.save .. ".part") or nil
  Tunnel.size = build.size
  Tunnel.channel = love.thread.newChannel()
  Tunnel.thread = love.thread.newThread(WORKER)
  Tunnel.thread:start(Tunnel.channel, windows, url, dest, build.sha256, command)
  Tunnel.state = url and "downloading" or "starting"
  Tunnel.since = love.timer.getTime()
end

function Tunnel.update()
  if Tunnel.state == "off" or not Tunnel.channel then return end
  if Tunnel.state == "downloading" and Tunnel.part then
    local info = love.filesystem.getInfo(Tunnel.part)
    Tunnel.progress = info and math.min(1, (info.size or 0) / Tunnel.size) or Tunnel.progress
  end
  while true do
    local msg = Tunnel.channel:pop()
    if not msg then break end
    local kind, value = msg[1], msg[2]
    if kind == "starting" then
      if Tunnel.state == "downloading" then Tunnel.state, Tunnel.since = "starting", love.timer.getTime() end
    elseif kind == "pid" then
      Tunnel.pid = value
    elseif kind == "url" then
      if Tunnel.state ~= "off" then Tunnel.state, Tunnel.url = "ready", value end
    elseif kind == "failed" then
      Tunnel.state, Tunnel.error = "failed", value
    elseif kind == "exit" then
      if Tunnel.state ~= "off" and Tunnel.state ~= "failed" then
        Tunnel.state = "failed"
        Tunnel.error = Tunnel.url and "The tunnel closed." or "cloudflared stopped before it gave a link."
      end
      Tunnel.url = nil
    end
  end
  if Tunnel.state == "starting" and love.timer.getTime() - Tunnel.since > START_TIMEOUT then
    Tunnel.stop()
    Tunnel.state, Tunnel.error = "failed", "Cloudflare didn't answer in time. Try again in a moment."
  end
  local err = Tunnel.thread and Tunnel.thread:getError()
  if err and Tunnel.state ~= "failed" and Tunnel.state ~= "off" then Tunnel.state, Tunnel.error = "failed", "The tunnel helper stopped." end
end

function Tunnel.stop()
  if Tunnel.state == "off" then return end
  -- Pick up the process id if it arrived but hasn't been read yet.
  if Tunnel.channel then
    while true do
      local msg = Tunnel.channel:pop()
      if not msg then break end
      if msg[1] == "pid" then Tunnel.pid = msg[2] end
    end
  end
  if Tunnel.windows then
    os.execute("taskkill /F /IM cloudflared.exe >nul 2>&1")
  elseif Tunnel.pid then
    os.execute("kill " .. Tunnel.pid .. " >/dev/null 2>&1")
  end
  Tunnel.state, Tunnel.url, Tunnel.pid, Tunnel.error = "off", nil, nil, nil
end

return Tunnel
