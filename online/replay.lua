-- Saved matches. A replay is the stream a spectator would receive: setup messages and snapshots.
-- Watching one is the normal client view fed from a file instead of the network, so it always
-- shows exactly what happened, without having to re-simulate anything.
local Replay = { DIR = "replays/" }

local PROTOCOL = function() return require("online.session").PROTOCOL end
local MAX_BYTES = 80 * 1024 * 1024

function Replay.recorder()
  return { clock = 0, entries = {}, bytes = 0 }
end

function Replay.add(rec, data)
  if rec.bytes > MAX_BYTES then return end
  rec.entries[#rec.entries + 1] = love.data.pack("string", "<ds4", rec.clock, data)
  rec.bytes = rec.bytes + #data
end

function Replay.save(rec, title)
  love.filesystem.createDirectory(Replay.DIR)
  local body = love.data.compress("string", "zlib", table.concat(rec.entries), 6)
  local name = os.date("%Y-%m-%d_%H-%M-%S") .. ".dsr"
  local head = love.data.pack("string", "<s1s1", PROTOCOL(), title or "Match")
  local ok = love.filesystem.write(Replay.DIR .. name, head .. body)
  return ok and name or nil
end

function Replay.list()
  local out = {}
  for _, f in ipairs(love.filesystem.getDirectoryItems(Replay.DIR)) do
    if f:match("%.dsr$") then out[#out + 1] = f end
  end
  table.sort(out, function(a, b) return a > b end)
  return out
end

-- Opens a saved match; returns a transport to hand to the client match, or nil and a reason.
function Replay.open(file)
  local raw = love.filesystem.read(Replay.DIR .. file)
  if not raw then return nil, "Couldn't read that replay" end
  local ok, proto, title, pos = pcall(love.data.unpack, "<s1s1", raw)
  if not ok then return nil, "That replay is damaged" end
  if proto ~= PROTOCOL() then return nil, "That replay is from a different version of the game" end
  local good, body = pcall(love.data.decompress, "string", "zlib", raw:sub(pos))
  if not good then return nil, "That replay is damaged" end
  local entries, p = {}, 1
  while p <= #body do
    local t, data
    t, data, p = love.data.unpack("<ds4", body, p)
    entries[#entries + 1] = { t = t, data = data }
  end
  local T = { entries = entries, index = 1, clock = 0, speed = 1, paused = false, title = title }
  T.duration = #entries > 0 and entries[#entries].t or 0
  T.markers = Replay.markers(entries)
  function T:send() end
  function T:advance(dt)
    if not self.paused then self.clock = self.clock + dt * self.speed end
  end
  function T:receive()
    local out = {}
    while self.index <= #self.entries and self.entries[self.index].t <= self.clock do
      out[#out + 1] = { from = "H", data = self.entries[self.index].data }
      self.index = self.index + 1
    end
    return out
  end
  function T:finished() return self.index > #self.entries end
  return T
end

-- Timeline markers, read from the stream once: round starts (snapshot state turns to countdown),
-- deaths (KILL messages) and card picks (ROSTER messages, whoever has one more card).
-- Each is { t, kind = "round"|"death"|"pick", round = n, victim, killer, cause, slot, card }.
function Replay.markers(entries)
  local net = require "online.net"
  local Snap = require "online.snapshot"
  local out, lastState, rounds, counts = {}, nil, 0, {}
  for _, e in ipairs(entries) do
    local kind = e.data:byte(1)
    if kind == net.MSG.SNAPSHOT then
      local ok, state = pcall(Snap.peekState, e.data)
      if ok then
        if state == "countdown" and lastState ~= "countdown" then
          rounds = rounds + 1
          out[#out + 1] = { t = e.t, kind = "round", round = rounds }
        end
        lastState = state
      end
    elseif kind == net.MSG.KILL then
      local ok, victim, killer, cause = pcall(net.decodeKill, e.data)
      if ok then out[#out + 1] = { t = e.t, kind = "death", victim = victim, killer = killer, cause = cause } end
    elseif kind == net.MSG.ROSTER then
      local ok, list = pcall(net.decodeRoster, e.data)
      if ok then
        for slot, r in ipairs(list) do
          local n = #r.cards
          if counts[slot] and n == counts[slot] + 1 then
            out[#out + 1] = { t = e.t, kind = "pick", slot = slot, card = r.cards[n] }
          end
          counts[slot] = n
        end
      end
    end
  end
  return out
end

-- Saving a replay as a video needs ffmpeg installed on this computer. Video only, no sound.
function Replay.hasFfmpeg()
  if Replay.ffmpegFound == nil then
    local p = io.popen("ffmpeg -version", "r")
    local out = p and p:read("*l") or nil
    if p then p:close() end
    Replay.ffmpegFound = out ~= nil and out:find("ffmpeg", 1, true) ~= nil
  end
  return Replay.ffmpegFound
end

function Replay.startVideo(name, w, h)
  love.filesystem.createDirectory("videos")
  local path = love.filesystem.getSaveDirectory() .. "/videos/" .. name:gsub("%.dsr$", "") .. ".mp4"
  local cmd = string.format('ffmpeg -y -loglevel error -f rawvideo -pix_fmt rgba -s %dx%d -r 30 -i - -an -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -c:v libx264 -pix_fmt yuv420p -crf 20 "%s"', w, h, path)
  local pipe = io.popen(cmd, love.system.getOS() == "Windows" and "wb" or "w")
  return pipe and { pipe = pipe, path = path } or nil
end

return Replay
