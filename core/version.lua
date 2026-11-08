-- The game's version and the notes shown under "What's new" on the main menu.
-- Desktop builds also check GitHub for a newer release (in a background thread, using curl).
local platform = require "core.platform"

local Version = {
  VERSION = "0.5.0",
  REPO = "Distorbed678/deckshot",
  NOTES = {
    "Rounds Clone is now Deckshot.",
    "New movement: coyote time, jump buffering, apex hang, fast fall, dash, wall jumps, one-way platforms.",
    "Melee: tap for a light hit, hold for a heavy lunge. Blocking a melee stuns the attacker.",
    "The arena edges hurt and throw you back in instead of killing you.",
    "55 new maps with saws, spikes, lasers, crushers, fans, conveyors, crates, barrels, ropes and more.",
    "150 cards (56 new), 40 synergies, and editors for maps, cards and synergies with share codes.",
    "Bots, gamepads, Teams (2v2), player colours and a local setup screen.",
    "Touch controls for phones and tablets; phones join LAN games by scanning a QR code.",
    "Online: smoother movement (prediction), spectating late joiners, reconnecting, Steam lobby browser.",
    "Sounds, particles, damage numbers, kill feed, scoreboard, codex, practice range and more.",
  },
  latest = nil, -- newer release tag found online, if any
}

local CHECK = [[
local channel, repo = ...
local ok, f = pcall(io.popen, "curl -s -m 6 -H \"Accept: application/vnd.github+json\" https://api.github.com/repos/" .. repo .. "/releases/latest")
if ok and f then
  local body = f:read("*a") or ""
  f:close()
  channel:push(body:match('"tag_name"%s*:%s*"v?([%d%.]+)"') or "")
else
  channel:push("")
end
]]

local function newer(a, b) -- is version a newer than b?
  local pa, pb = {}, {}
  for n in a:gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
  for n in b:gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
  for i = 1, math.max(#pa, #pb) do
    if (pa[i] or 0) ~= (pb[i] or 0) then return (pa[i] or 0) > (pb[i] or 0) end
  end
  return false
end

function Version.checkForUpdate()
  if platform.web or Version.thread or not love.thread then return end
  local ok = pcall(function()
    Version.channel = love.thread.newChannel()
    Version.thread = love.thread.newThread(CHECK)
    Version.thread:start(Version.channel, Version.REPO)
  end)
  if not ok then Version.thread = nil end
end

function Version.update()
  local ch = Version.channel
  if not ch then return end
  local tag = ch:pop()
  if tag then
    Version.channel = nil
    if tag ~= "" and newer(tag, Version.VERSION) then Version.latest = tag end
  end
end

return Version
