-- The game's version and the notes shown under "What's new" on the main menu.
-- Desktop builds also check GitHub for a newer release (in a background thread, using curl).
local platform = require "core.platform"

local Version = {
  VERSION = "0.7.0",
  REPO = "Distorbed678/deckshot",
  NOTES = {
    "100 new cards: block and parry, dash, melee, gadgets, bounce, status effects and risk builds, plus new statuses: burn, shock, freeze and bleed.",
    "50 new maps, half of them simple physics arenas, and two new backdrops: sky islands and caverns.",
    "Fights are faster: three hits kill at the start. Bigger hits fire bigger bullets.",
    "Card rebalance: commons are one modest stat, effects cost a little reload or block time, and nine weak cards are gone.",
    "Homing only works inside a cone ahead of the bullet (shown at your gun). Joystick bullets fly to your cursor.",
    "Reworked Turret Buddy (floating turrets), Stillness (charge ring and a beam shot), Thunderhead (forked lightning) and black holes (never hurt you).",
    "Every card says what extra copies do.",
    "Replays: a timeline along the bottom with round, death and card markers; click to jump.",
    "Card editor: test against a dummy or a bot, search the stats, pick your test controls in Settings > Controls.",
    "Hold down to drop through thin platforms. Every jump on every map is comfortably reachable.",
    "Fixed: the Steam invite button (it now works without the Steam overlay), lasers passing through things, weights you couldn't touch, stretched limbs at spawn, the cut-off scoreboard, maps off the grid and floating grounds.",
    "Platforms on spinning arms can stay level (Carousel, Clockwork).",
    "Jumping: a tap is always a full jump, falling is less heavy, and holding down no longer makes you fall faster.",
    "Platforms that were just out of reach on 22 maps have been moved so every one can be reached with a normal jump.",
    "Ropes and everything they hold move smoothly on high refresh rate screens and online, and jitter less when you land on them.",
    "Online: you no longer clip into platforms hanging from ropes.",
    "Arms and legs no longer stretch out when they catch on the scenery.",
    "Fixed: on the card pick screen, your character's arm reaches the card you're on again, and its legs no longer fold up.",
    "A cleaner win screen.",
    "Online: a typing bubble shows over anyone writing in the chat.",
    "No more screen shake.",
    "Fixed: chat messages showing up black, and the tutorial's last steps, which asked for things the arena no longer has.",
    "Play with friends anywhere, for free: the LAN lobby has an Internet tab with two kinds of invite link.",
    "Direct link: friends open the game's web page with your room code and connect to you peer-to-peer.",
    "Tunnel link: one button sets up a Cloudflare tunnel for you (a one-time download), for connections the direct link can't reach.",
    "Invite links take friends straight to the join screen.",
    "Fixed: the Video settings tab scrolls, so its options no longer run under the Back button.",
    "A whole new deck: 116 new cards, built around one strong upside and a small cost, with many more block cards.",
    "50 new maps: clean arenas, moving platforms, breakable lattices, hanging structures, stacked towers and hazard rooms.",
    "Ramps: blocks can be sloped (Edit Object > Ramp). You never slide on them, and ten of the new maps are built around them.",
    "New card effects: drilling and steered bullets, tethers, delayed bombs, a buzzsaw block, auras, and Stacked Deck.",
    "Draft start (Settings > Gameplay, off by default): starting cards are picked in turn from one shared spread.",
    "Two new block materials: ice (you keep sliding) and sticky (slows you, weakens jumps, stops bullets bouncing).",
    "16 melee and movement cards, including Hill Runner for ramps.",
    "Online: other players move more smoothly on uneven connections, and late or lost packets no longer cause rewinds or missing effects.",
    "Online: your own muzzle flash and shot sound play the moment you fire.",
    "Network stats on screen with F3 (or Settings > Video): ping, loss, jitter and snapshot rate.",
    "Less stutter: ropes, lights and interface boxes no longer create garbage every frame.",
    "The old cards and maps are kept in the repo's legacy folder.",
    "Bots walk ramps and no longer freeze in a standoff across an obstacle.",
    "Fixed: spaces can be typed in chat and other text boxes in the browser version.",
    "Touch: pushing the move stick up no longer jumps, so use the Jump button.",
    "Touch: the pause button is now in the top right corner.",
    "Phones: sharper picture, full colour in the browser, and the pause button no longer covers the round timer.",
    "Fixed: keyboard outlines showing on touch screens, and an empty tutorial panel during the countdown.",
    "The browser version is sharp on phones and scaled displays.",
    "Browser players can join your game from outside your network through a free https tunnel. See the README.",
    "Teams are picked by colour now: the same colour is the same team, and the host sets the max team size.",
    "Friendly fire works in every mode and lets your own bullets and blasts hurt you.",
    "Voice chat for Steam and LAN. It's off until you turn it on in Settings > Audio.",
    "Synergies are gone. Cards combine on their own: explosive bullets explode at every bounce, poison spreads through blasts.",
    "Local Play has a new lobby-style screen.",
    "Practice and the tutorial let you choose keyboard, mouse or gamepad controls.",
    "The center of a black hole now hurts anyone inside it.",
    "Fixed: saws are full blades again. Linux: the taskbar shows Deckshot's icon.",
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
