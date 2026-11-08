-- The game's version and the notes shown under "What's new" on the main menu.
-- Desktop builds also check GitHub for a newer release (in a background thread, using curl).
local platform = require "core.platform"

local Version = {
  VERSION = "0.6.0",
  REPO = "Distorbed678/deckshot",
  NOTES = {
    "Every card has its own art now.",
    "Rare, epic and legendary cards shimmer, and flash with a bigger sound when they turn over.",
    "Match Recap at the end of a match: everyone's stats, builds and awards, saved as an image.",
    "Controller button icons in menus, card picks, the tutorial and How to Play (Xbox, PlayStation or Nintendo).",
    "Fixed: text overlapping on very wordy cards when five cards are dealt.",
    "Players are solid now, so you can stand on each other.",
    "Your weapon changes with your stats.",
    "Dashes always go where you aim, and heavy melee is a short step you can charge on the move.",
    "Card and map selection use only your keys, with a new Discard key.",
    "Win 2 sub-rounds on the same map to take a point (the host can change how many). Losers then pick a card.",
    "New card screen: your character aims at the cards as you choose them with the keys.",
    "New in-round display with points and sub-round progress top left and cards top right.",
    "Noodle arms and legs that really hold you up, tuck when you jump, and a recoil kick when you fire.",
    "Explosions are smoke, fire and debris now.",
    "44 achievements unlock about 60 hats, eyes, mouths and details. Your face reacts as you play.",
    "Chat bubbles appear above players during matches, with name tags online.",
    "Maps are 20% bigger, and all 55 have new platforms, hazards and breakables.",
    "New mode: King of the Hill, in free-for-all or teams.",
    "Every round has a timer. When it ends, a red barrier closes in from all four sides.",
    "Map voting and card bans, both host options.",
    "Chat in online and LAN lobbies and during matches.",
    "Clients can open Settings in a lobby and see the host's rules and custom content.",
    "Hats and faces to earn on the new Customize screen.",
    "Original music, a new look and font, a logo, a versus intro and a winner's podium.",
    "Characters are livelier and burst into chunks when they die. New impact sounds and tension audio.",
    "Characters now have springy arms and legs, a pistol, and a block circle in their off hand.",
    "Muzzle flash and sparks on every shot. Blocking at an edge throws you back in much harder.",
    "18 maps have no ground, so you can fall to the bottom. Every other map's ground reaches the bottom.",
    "Bullets drop more. Thunder God strikes much sooner.",
    "Rarity chances always total 100%, and 51 cards moved to a better rarity.",
    "Card Library replaces the Codex and Card Pool. Match settings all live in Settings > Gameplay.",
    "Practice moved under Local Play, with a card menu sorted by rarity that shows what each card does.",
    "A short tutorial, and one-click updates on Windows and Linux.",
    "Fixed: What's New clicking the buttons behind it, and overlapping text across the menus.",
  },
  latest = nil,  -- newer release version found online, if any
  release = nil, -- details of that release: { version, notes, assets = { name -> { url, size, sha256 } } }
  API = nil,     -- overrides the GitHub URL (tests)
}

local CHECK = [[
local channel, url = ...
local ok, f = pcall(io.popen, 'curl -s -L -m 8 -H "Accept: application/vnd.github+json" "' .. url .. '"')
if ok and f then
  local body = f:read("*a") or ""
  f:close()
  channel:push(body)
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
Version.newer = newer

function Version.checkForUpdate()
  if platform.web or Version.thread or not love.thread then return end
  local ok = pcall(function()
    Version.channel = love.thread.newChannel()
    Version.thread = love.thread.newThread(CHECK)
    Version.thread:start(Version.channel, Version.API or ("https://api.github.com/repos/" .. Version.REPO .. "/releases/latest"))
  end)
  if not ok then Version.thread = nil end
end

local function unescape(s)
  return (s:gsub("\\r", ""):gsub("\\n", "\n"):gsub('\\"', '"'):gsub("\\\\", "\\"))
end

-- Pulls what we need out of GitHub's release JSON.
function Version.parseRelease(body)
  local tag = body:match('"tag_name"%s*:%s*"v?([%d%.]+)"')
  if not tag then return nil end
  local text = unescape(body:match('"body"%s*:%s*"(.-[^\\])"') or "")
  local release = { version = tag, notes = (text:gsub("\n## Downloads.*$", "")), assets = {} }
  for _, name in ipairs({ "Deckshot-x86_64.AppImage", "Deckshot-windows-x64.zip" }) do
    local esc = name:gsub("%p", "%%%0")
    local size, url = body:match('"name"%s*:%s*"' .. esc .. '".-"size"%s*:%s*(%d+).-"browser_download_url"%s*:%s*"([^"]+)"')
    local sha
    for hash, file in text:gmatch("(%x+)%s+([%w%-_%.]+)") do
      if file == name and #hash == 64 then sha = hash:lower() end
    end
    if url and sha then release.assets[name] = { url = url, size = tonumber(size), sha256 = sha } end
  end
  return release
end

function Version.update()
  local ch = Version.channel
  if not ch then return end
  local body = ch:pop()
  if body then
    Version.channel = nil
    local release = body ~= "" and Version.parseRelease(body)
    if release and newer(release.version, Version.VERSION) then
      Version.latest, Version.release = release.version, release
    end
  end
end

return Version
