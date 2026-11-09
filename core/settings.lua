-- Player settings: saved to settings.txt in the LÖVE save folder.
local Bloom = require "gfx.bloom"
local fx = require "gfx.fx"
local Cards = require "game.cards"
local Map = require "game.map"
local platform = require "core.platform"
local sfx = require "gfx.sfx"

local Settings = {}

local FILE = "settings.txt"

Settings.COMMON_RESOLUTIONS = {
  { 960, 540 }, { 1280, 720 }, { 1366, 768 }, { 1600, 900 }, { 1920, 1080 }, { 2560, 1440 }, { 3840, 2160 },
}
Settings.WINDOW_MODES = { "windowed", "borderless", "fullscreen" }
Settings.WINDOW_MODE_NAMES = { windowed = "Windowed", borderless = "Borderless", fullscreen = "Fullscreen" }
Settings.VSYNC_MODES = { { "Off", 0 }, { "On", 1 }, { "Adaptive", -1 } }
Settings.FPS_OPTIONS = { 0, 30, 60, 120, 144, 165, 240, 360 }
Settings.BLOOM_LEVELS = { { "Low", 0.35 }, { "Medium", 0.6 }, { "High", 0.9 } }
Settings.SHAKE_LEVELS = { { "Off", 0 }, { "Low", 0.5 }, { "Full", 1 } }
Settings.PARTICLE_LEVELS = { { "Reduced", 0.5 }, { "Full", 1 } }
Settings.ROUND_OPTIONS = { 3, 5, 7, 10, 15 }
Settings.PICK_FROM = { min = 2, max = 6 }
Settings.PICKS_PER_ROUND = { min = 1, max = 5 }
Settings.START_CARDS = { min = 0, max = 5 }
Settings.DRAFT_EXTRA = { min = 0, max = 3 }
Settings.TEXT_SIZES = { { "Small", 0.9 }, { "Normal", 1 }, { "Large", 1.15 } }
Settings.PICK_TIMER_OPTIONS = { 0, 15, 20, 30, 45, 60, 90, 120 }
Settings.SUB_ROUNDS = { min = 1, max = 5 }
Settings.TEAM_SIZE = { min = 2, max = 3 }
Settings.SUDDEN_TIMES = { 0, 60, 90, 120, 180, 240, 300, 420, 600 } -- seconds; 0 = off
Settings.BARRIER_CLOSE_NAMES = { "Slow (40s)", "Normal (20s)", "Fast (10s)" }
Settings.BARRIER_BOX_NAMES = { "Small", "Medium", "Large" }
Settings.BARRIER_DAMAGE_NAMES = { "Low", "Normal", "High" }
Settings.MAP_VOTE_COUNT = { min = 2, max = 6 }
Settings.MODES = { "elim", "koth", "jugg" }
Settings.MODE_NAMES = { elim = "Elimination", koth = "King of the Hill", jugg = "Juggernaut" }

-- Key bindings. Values are LÖVE key constants or "mouse1".."mouse5".
Settings.BIND_SCHEMES = {
  { id = "p1", name = "Player 1 (local)", group = "keyboard",
    actions = { "left", "right", "up", "down", "fire", "block", "dash", "melee", "discard" } },
  { id = "p2", name = "Player 2 (local)", group = "keyboard",
    actions = { "left", "right", "up", "down", "fire", "block", "dash", "melee", "discard" } },
  { id = "online", name = "Online", group = "online",
    actions = { "left", "right", "jump", "jump2", "down", "fire", "block", "dash", "melee", "discard", "scoreboard", "chat", "voice" } },
}
Settings.ACTION_NAMES = {
  left = "Left", right = "Right", up = "Up / Jump", down = "Down", fire = "Fire", block = "Block",
  jump = "Jump", jump2 = "Jump (alt)", dash = "Dash", scoreboard = "Scoreboard", melee = "Melee (hold)", chat = "Chat", voice = "Push to talk", discard = "Discard",
}
Settings.DEFAULT_BINDS = {
  p1 = { left = "a", right = "d", up = "w", down = "s", fire = "space", block = "lshift", dash = "e", melee = "q", discard = "c" },
  p2 = { left = "left", right = "right", up = "up", down = "down", fire = "rctrl", block = "rshift",
    dash = "/", melee = ".", discard = "," },
  online = { left = "a", right = "d", jump = "space", jump2 = "w", down = "s", fire = "mouse1", block = "mouse2",
    dash = "lshift", melee = "q", discard = "c", scoreboard = "tab", chat = "return", voice = "v" },
}
-- Keys that can't be bound (menu / fullscreen toggle).
Settings.RESERVED_KEYS = { escape = true, f11 = true }

local defaults = {
  windowMode = "windowed",
  lastFullscreen = "borderless",
  display = 1,
  resolution = "1280x720",
  vsyncMode = 1,
  maxFps = 0,
  bloom = true,
  lighting = love._os ~= "Web", -- dynamic lighting (the browser build starts with it off)
  bloomLevel = 2,
  shake = 3,
  particles = 2,
  showFps = false,
  netStats = false,      -- online: ping, loss, jitter and snapshot rate on screen (F3)
  roundsToWin = 5,
  subRounds = 2,         -- sub-round wins needed for a point
  pickFrom = 5,
  picksPerRound = 1,
  startCards = 1,        -- cards everyone picks before round 1
  draft = false,         -- starting cards are drafted in turn from one shared spread
  draftExtra = 2,        -- spare cards in each spread, beyond one per player
  draftSnake = true,     -- the pick order reverses every draft round
  pickTimer = 45,        -- seconds per pick online (0 = off); local play has no timer
  allowDiscard = true,   -- "discard a card instead" on the pick screen
  hazards = true,        -- map hazards on (breakables always stay)
  suddenDeath = 180,     -- seconds per round before the barrier closes in (0 = off)
  barrierClose = 2,      -- Settings.BARRIER_CLOSE_NAMES
  barrierBox = 2,        -- Settings.BARRIER_BOX_NAMES
  barrierDamage = 2,     -- Settings.BARRIER_DAMAGE_NAMES
  matchMode = "elim",    -- elim / koth / jugg
  mapVote = true,        -- players vote for the next map
  mapVoteCount = 3,      -- maps on the ballot
  cardBans = false,      -- everyone bans a card before the match
  teams = false,         -- 2v2 teams (local setup / host)
  teamSize = 2,          -- with teams on: the most players who can share a colour
  friendlyFire = false,  -- your bullets and blasts can hurt you and your teammates
  localSetup = "p1:1:1;p2:2:2;off:3:1;off:4:2", -- local play slots: kind:colour:team
  playerColor = 1,       -- your colour in online lobbies
  touchControls = "auto", -- auto (on after the first touch) / on / off
  touchLayout = "",      -- custom touch button positions (core/touch.lua)
  touchOpacity = 0.5,
  mobileDefaults = false, -- lighter effects were applied for a touch device
  practiceControls = "p1", -- last choice on the practice / tutorial control picker
  padOnline = false,     -- play online with the first gamepad instead of mouse + keys
  clientToken = "",      -- random id, so a LAN host can give you your slot back after a disconnect
  lobbyVisibility = "public", -- Steam lobbies: public (listed), friends, code (unlisted)
  damageNumbers = true,  -- floating damage numbers
  textSize = 2,          -- 1 small, 2 normal, 3 large (Settings.TEXT_SIZES)
  lastLanAddress = "",   -- the last LAN address you typed
  scoreboardHold = true, -- scoreboard key: hold to show (false = press to toggle)
  settingsVersion = 6,
  checkUpdates = true,   -- look for a new version on the main menu (desktop)
  tutorialOffered = false, -- the first-run tutorial has been offered
  hat = "none",          -- cosmetics (core/cosmetics.lua)
  eyes = "classic",
  mouth = "smile",
  detail = "none",
  playerName = "Player", -- shown to others in LAN games
  volMaster = 8,         -- volumes in steps of 0..10
  volSfx = 10,
  volUi = 8,
  volVoice = 8,
  voiceMode = "off",     -- "off" (no microphone, and you hear nobody), "push" or "open"
  voiceThreshold = 3,    -- open mic: how loud counts as talking (index into Voice.THRESHOLDS)
  voiceDevice = "",      -- microphone name; empty or unknown means the first one
  volMusic = 7,
  muteUnfocused = true,
}
for _, r in ipairs(Cards.RARITIES) do defaults["weight_" .. r.id] = r.weight end

local function copyBinds(src)
  local t = {}
  for scheme, b in pairs(src) do
    t[scheme] = {}
    for k, v in pairs(b) do t[scheme][k] = v end
  end
  return t
end

Settings.values = {}
for k, v in pairs(defaults) do Settings.values[k] = v end
Settings.values.binds = copyBinds(Settings.DEFAULT_BINDS)
Settings.values.cards = {} -- card id -> { rarity = id or nil, disabled = bool }
Settings.values.maps = {}  -- map id -> true when the map is turned off

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function validBinding(b)
  if type(b) ~= "string" or b == "" or Settings.RESERVED_KEYS[b] then return false end
  local n = b:match("^mouse(%d)$")
  if n then return tonumber(n) >= 1 and tonumber(n) <= 5 end
  return (pcall(love.keyboard.isDown, b))
end

-- The game used to be called "Rounds Clone" (save identity "rounds_clone"). On the first run
-- under the new name, copy the old settings file over once. The old folder is left alone.
function Settings.migrateOldSave()
  if love.filesystem.getInfo(FILE) then return end
  local dir = love.filesystem.getSaveDirectory()
  local oldDir = dir and dir:gsub("deckshot$", "rounds_clone")
  if not oldDir or oldDir == dir then return end
  local f = io.open(oldDir .. "/" .. FILE, "rb")
  if not f then return end
  local data = f:read("*a")
  f:close()
  if data and #data > 0 then love.filesystem.write(FILE, data) end
end

function Settings.load()
  pcall(Settings.migrateOldSave)
  if not love.filesystem.getInfo(FILE) then return end
  local v = Settings.values
  v.settingsVersion = 1 -- files written before versioning have no settingsVersion line
  local legacyVsync, legacyRes, legacyBarrierOff
  for line in love.filesystem.lines(FILE) do
    local scheme, action, b = line:match("^bind%.([%w_]+)%.([%w_]+)=(.*)$")
    local cardId, cardVal = line:match("^card%.([%w_]+)=(.*)$")
    local mapId, mapVal = line:match("^map%.([%w_]+)=(.*)$")
    local k, val = line:match("^([%w_]+)=(.*)$")
    if scheme then
      if v.binds[scheme] and Settings.DEFAULT_BINDS[scheme][action] and validBinding(b) then
        v.binds[scheme][action] = b
      end
    elseif mapId then
      if Map.byId[mapId] and mapVal == "off" then v.maps[mapId] = true end
    elseif cardId then
      if Cards.byId[cardId] then
        local rarity, state = cardVal:match("^(%w*),(%w+)$")
        local entry = {}
        if rarity and Cards.rarity[rarity] then entry.rarity = rarity end
        entry.disabled = state == "off"
        v.cards[cardId] = entry
      end
    elseif k == "face" then
      v.eyes = val -- older saves had one "face" slot
    elseif k == "barrier" then
      legacyBarrierOff = val == "false"
    elseif k == "vsync" then
      legacyVsync = val
    elseif k == "resolution" and tonumber(val) then
      legacyRes = tonumber(val)
    elseif k and defaults[k] ~= nil then
      local d = defaults[k]
      if type(d) == "boolean" then
        v[k] = (val == "true")
      elseif type(d) == "number" then
        v[k] = tonumber(val) or d
      else
        v[k] = val
      end
    end
  end

  -- v0.4 and older: 3 cards per hand was the default; the new default is 5.
  if v.clientToken == "" then
    v.clientToken = string.format("%08x%08x", love.math.random(0, 0x7fffffff), love.math.random(0, 0x7fffffff))
  end
  if (v.settingsVersion or 1) < 2 then
    if v.pickFrom == 3 then v.pickFrom = 5 end
    v.settingsVersion = 2
  end
  if v.settingsVersion < 3 then
    -- v0.5.1: rarity chances are percentages with new defaults; the barrier became a timer.
    local old = { 46, 30, 15, 6, 3 }
    local isOld = true
    for i, r in ipairs(Cards.RARITIES) do
      if v["weight_" .. r.id] ~= old[i] then isOld = false end
    end
    if isOld then
      for _, r in ipairs(Cards.RARITIES) do v["weight_" .. r.id] = defaults["weight_" .. r.id] end
    end
    if legacyBarrierOff then v.suddenDeath = 0 end
    v.settingsVersion = 3
  end
  if v.settingsVersion < 5 then
    -- A development build briefly moved the default to 3 (settings version 4).
    if v.settingsVersion == 4 and v.roundsToWin == 3 then v.roundsToWin = 5 end
    v.settingsVersion = 5
  end
  if v.settingsVersion < 6 then
    if v.binds.online.melee == "f" then v.binds.online.melee = "q" end -- the new default
    v.settingsVersion = 6
  end

  -- Older settings files: vsync=true/false and resolution=<index>.
  if legacyVsync then v.vsyncMode = legacyVsync == "false" and 0 or 1 end
  if legacyRes then
    local old = { "1280x720", "1600x900", "1920x1080", "2560x1440" }
    v.resolution = old[legacyRes] or defaults.resolution
  end

  if not Settings.parseResolution(v.resolution) then v.resolution = defaults.resolution end
  if v.vsyncMode ~= 0 and v.vsyncMode ~= 1 and v.vsyncMode ~= -1 then v.vsyncMode = 1 end
  v.maxFps = math.max(0, math.floor(v.maxFps))
  v.display = math.max(1, math.floor(v.display))
  v.bloomLevel = clamp(v.bloomLevel, 1, #Settings.BLOOM_LEVELS)
  v.shake = clamp(v.shake, 1, #Settings.SHAKE_LEVELS)
  v.particles = clamp(v.particles, 1, #Settings.PARTICLE_LEVELS)
  v.pickFrom = clamp(math.floor(v.pickFrom), Settings.PICK_FROM.min, Settings.PICK_FROM.max)
  v.picksPerRound = clamp(math.floor(v.picksPerRound), Settings.PICKS_PER_ROUND.min, Settings.PICKS_PER_ROUND.max)
  v.startCards = clamp(math.floor(v.startCards), Settings.START_CARDS.min, Settings.START_CARDS.max)
  v.draftExtra = clamp(math.floor(tonumber(v.draftExtra) or 2), Settings.DRAFT_EXTRA.min, Settings.DRAFT_EXTRA.max)
  v.textSize = clamp(math.floor(v.textSize), 1, #Settings.TEXT_SIZES)
  v.pickTimer = clamp(math.floor(v.pickTimer), 0, 255)
  for _, r in ipairs(Cards.RARITIES) do
    local key = "weight_" .. r.id
    v[key] = clamp(math.floor(v[key]), 0, 1000)
  end
  Settings.normalizeWeights()
  v.barrierClose = clamp(math.floor(v.barrierClose), 1, 3)
  v.barrierBox = clamp(math.floor(v.barrierBox), 1, 3)
  v.barrierDamage = clamp(math.floor(v.barrierDamage), 1, 3)
  v.subRounds = clamp(math.floor(v.subRounds), Settings.SUB_ROUNDS.min, Settings.SUB_ROUNDS.max)
  v.teamSize = clamp(math.floor(tonumber(v.teamSize) or 2), Settings.TEAM_SIZE.min, Settings.TEAM_SIZE.max)
  v.mapVoteCount = clamp(math.floor(v.mapVoteCount), Settings.MAP_VOTE_COUNT.min, Settings.MAP_VOTE_COUNT.max)
  v.volMusic = clamp(math.floor(v.volMusic), 0, 10)
  if not Settings.MODE_NAMES[v.matchMode] then v.matchMode = "elim" end
  if not Settings.WINDOW_MODE_NAMES[v.windowMode] then v.windowMode = "windowed" end
  if v.lastFullscreen ~= "borderless" and v.lastFullscreen ~= "fullscreen" then v.lastFullscreen = "borderless" end
end

function Settings.save()
  local v = Settings.values
  local lines = {}
  for k in pairs(defaults) do
    lines[#lines + 1] = k .. "=" .. tostring(v[k])
  end
  for scheme, b in pairs(v.binds) do
    for action, key in pairs(b) do
      lines[#lines + 1] = "bind." .. scheme .. "." .. action .. "=" .. key
    end
  end
  for id in pairs(v.maps) do
    lines[#lines + 1] = "map." .. id .. "=off"
  end
  for id, e in pairs(v.cards) do
    if e.rarity or e.disabled then
      lines[#lines + 1] = "card." .. id .. "=" .. (e.rarity or "") .. "," .. (e.disabled and "off" or "on")
    end
  end
  table.sort(lines)
  love.filesystem.write(FILE, table.concat(lines, "\n") .. "\n")
end

---------------------------------------------------------------- bindings
-- In place: input states keep references to these tables.
function Settings.resetBinds()
  for scheme, b in pairs(Settings.DEFAULT_BINDS) do
    for action, key in pairs(b) do Settings.values.binds[scheme][action] = key end
  end
end

local function schemeById(id)
  for _, s in ipairs(Settings.BIND_SCHEMES) do
    if s.id == id then return s end
  end
end

-- Bind `key` to scheme.action. If another action in the same group (P1 + P2 share
-- the keyboard) already uses it, that action takes over the old key instead.
function Settings.bind(schemeId, action, key)
  if not validBinding(key) then return false end
  local binds = Settings.values.binds
  local old = binds[schemeId][action]
  local group = schemeById(schemeId).group
  for _, s in ipairs(Settings.BIND_SCHEMES) do
    if s.group == group then
      for _, a in ipairs(s.actions) do
        if binds[s.id][a] == key and not (s.id == schemeId and a == action) then
          binds[s.id][a] = old
        end
      end
    end
  end
  binds[schemeId][action] = key
  return true
end

---------------------------------------------------------------- cards
function Settings.cardEntry(card)
  return Settings.values.cards[card.id] or {}
end

function Settings.cardRarity(card)
  return Settings.cardEntry(card).rarity or card.baseRarity
end

function Settings.cardEnabled(card)
  return not Settings.cardEntry(card).disabled
end

function Settings.setCard(card, rarity, enabled)
  local e = { disabled = not enabled }
  if rarity ~= card.baseRarity then e.rarity = rarity end
  if e.rarity or e.disabled then
    Settings.values.cards[card.id] = e
  else
    Settings.values.cards[card.id] = nil
  end
end

-- Rarity chances are whole percentages that always total exactly 100.
-- Distributes `total` over list items in proportion to their `w`, largest remainders first.
local function apportion(items, total)
  local sum = 0
  for _, it in ipairs(items) do sum = sum + it.w end
  if sum <= 0 then
    for _, it in ipairs(items) do it.w = 1 end
    sum = #items
  end
  local left = total
  for _, it in ipairs(items) do
    local exact = it.w / sum * total
    it.value = math.floor(exact)
    it.rem = exact - it.value
    left = left - it.value
  end
  local order = {}
  for i, it in ipairs(items) do order[i] = it end
  table.sort(order, function(a, b)
    if a.rem ~= b.rem then return a.rem > b.rem end
    return a.index < b.index
  end)
  for i = 1, left do order[i].value = order[i].value + 1 end
end

function Settings.normalizeWeights()
  local v = Settings.values
  local items = {}
  for i, r in ipairs(Cards.RARITIES) do items[i] = { key = "weight_" .. r.id, w = v["weight_" .. r.id], index = i } end
  apportion(items, 100)
  for _, it in ipairs(items) do v[it.key] = it.value end
end

-- Sets one rarity's chance; the others change in proportion so the total stays 100.
function Settings.setWeight(rarityId, value)
  local v = Settings.values
  value = clamp(math.floor(value), 0, 100)
  local items = {}
  for i, r in ipairs(Cards.RARITIES) do
    if r.id ~= rarityId then items[#items + 1] = { key = "weight_" .. r.id, w = v["weight_" .. r.id], index = i } end
  end
  apportion(items, 100 - value)
  for _, it in ipairs(items) do v[it.key] = it.value end
  v["weight_" .. rarityId] = value
end

function Settings.resetGameplay()
  local v = Settings.values
  v.roundsToWin = defaults.roundsToWin
  v.subRounds = defaults.subRounds
  v.matchMode, v.teams, v.friendlyFire, v.teamSize = defaults.matchMode, defaults.teams, defaults.friendlyFire, defaults.teamSize
  v.suddenDeath, v.barrierClose = defaults.suddenDeath, defaults.barrierClose
  v.barrierBox, v.barrierDamage = defaults.barrierBox, defaults.barrierDamage
  v.mapVote, v.mapVoteCount, v.cardBans = defaults.mapVote, defaults.mapVoteCount, defaults.cardBans
  v.pickFrom = defaults.pickFrom
  v.picksPerRound = defaults.picksPerRound
  v.startCards = defaults.startCards
  v.draft, v.draftExtra, v.draftSnake = defaults.draft, defaults.draftExtra, defaults.draftSnake
  v.pickTimer = defaults.pickTimer
  v.allowDiscard = defaults.allowDiscard
  v.hazards = defaults.hazards
  for _, r in ipairs(Cards.RARITIES) do v["weight_" .. r.id] = defaults["weight_" .. r.id] end
  v.cards = {}
  v.maps = {}
end

---------------------------------------------------------------- maps
function Settings.mapEnabled(map)
  return not Settings.values.maps[map.id]
end

function Settings.setMap(map, enabled)
  Settings.values.maps[map.id] = (not enabled) or nil
end

function Settings.enabledMapCount()
  local n = 0
  for _, m in ipairs(Map.list) do
    if Settings.mapEnabled(m) then n = n + 1 end
  end
  return n
end

-- The gameplay rules (cards, picks, rarity weights and the map pool) described by these settings.
-- online: the pick timer only applies to online matches.
function Settings.cardRules(online)
  local v = Settings.values
  local rules = { pickFrom = v.pickFrom, picksPerRound = v.picksPerRound, weights = {}, rarity = {}, disabled = {},
    startCards = v.startCards, pickTimer = online and v.pickTimer or 0, allowDiscard = v.allowDiscard,
    draft = v.draft, draftExtra = v.draftExtra, draftSnake = v.draftSnake,
    hazards = v.hazards,
    teams = v.teams, teamSize = v.teamSize, friendlyFire = v.friendlyFire, roundsToWin = v.roundsToWin,
    suddenDeath = v.suddenDeath, barrierClose = v.barrierClose, barrierBox = v.barrierBox,
    barrierDamage = v.barrierDamage, mode = v.matchMode, mapVote = v.mapVote, mapVoteCount = v.mapVoteCount,
    cardBans = v.cardBans, subRounds = v.subRounds }
  for i, r in ipairs(Cards.RARITIES) do rules.weights[i] = v["weight_" .. r.id] end
  for _, c in ipairs(Cards.list) do
    rules.rarity[c.index] = Settings.cardRarity(c)
    rules.disabled[c.index] = not Settings.cardEnabled(c) or nil
  end
  rules.maps = {} -- disabled map indices (only the host's world uses these)
  for _, m in ipairs(Map.list) do
    if not Settings.mapEnabled(m) then rules.maps[m.index] = true end
  end
  return rules
end

---------------------------------------------------------------- window
function Settings.parseResolution(s)
  local w, h = tostring(s):match("^(%d+)x(%d+)$")
  if not w then return nil end
  return tonumber(w), tonumber(h)
end

function Settings.displayCount()
  local ok, n = pcall(love.window.getDisplayCount)
  return ok and n or 1
end

-- The monitor to use (clamped to the monitors that exist). `index` defaults to the saved setting.
function Settings.display(index)
  return math.max(1, math.min(index or Settings.values.display, Settings.displayCount()))
end

-- Window sizes for a display (default: the saved one), largest last.
-- Always contains `current` (default: the saved resolution).
function Settings.resolutions(displayIndex, current)
  local display = Settings.display(displayIndex)
  current = current or Settings.values.resolution
  local dw, dh = love.window.getDesktopDimensions(display)
  local seen, list = {}, {}
  local function add(w, h)
    local key = w .. "x" .. h
    if not seen[key] and w >= 640 and h >= 360 and w <= dw and h <= dh then
      seen[key] = true
      list[#list + 1] = { w, h, key = key }
    end
  end
  for _, r in ipairs(Settings.COMMON_RESOLUTIONS) do add(r[1], r[2]) end
  local ok, modes = pcall(love.window.getFullscreenModes, display)
  if ok and modes then
    for _, m in ipairs(modes) do add(m.width, m.height) end
  end
  local cw, ch = Settings.parseResolution(current)
  if cw and not seen[current] then
    seen[current] = true
    list[#list + 1] = { cw, ch, key = current }
  end
  table.sort(list, function(a, b)
    if a[1] * a[2] ~= b[1] * b[2] then return a[1] * a[2] < b[1] * b[2] end
    return a[1] < b[1]
  end)
  return list
end

-- Effects that don't touch the window.
function Settings.applyEffects()
  local v = Settings.values
  local Touch = require "core.touch"
  Touch.setLayout(v.touchLayout, v.touchOpacity)
  if v.touchControls == "on" then Touch.enabled = true elseif v.touchControls == "off" then Touch.enabled = false end
  Bloom.enabled = v.bloom
  Bloom.intensity = Settings.BLOOM_LEVELS[v.bloomLevel][2]
  fx.shakeScale = Settings.SHAKE_LEVELS[v.shake][2]
  fx.particleScale = Settings.PARTICLE_LEVELS[v.particles][2]
  fx.showNumbers = v.damageNumbers
  local app = package.loaded["core.app"]
  local ts = Settings.TEXT_SIZES[v.textSize] or Settings.TEXT_SIZES[2]
  if app and app.textScale ~= ts[2] then
    app.textScale = ts[2]
    app.renderScale = nil -- rebuild the fonts on the next frame
  end
  sfx.volumes.master = clamp(v.volMaster, 0, 10) / 10
  sfx.volumes.sfx = clamp(v.volSfx, 0, 10) / 10
  sfx.volumes.ui = clamp(v.volUi, 0, 10) / 10
  sfx.volumes.music = clamp(v.volMusic, 0, 10) / 10
end

-- love.window.setMode can't run while a canvas is active (e.g. from a screen's draw, where
-- the UI reacts to clicks). In that case the change is applied on the next Settings.update().
Settings.windowPending = false

function Settings.update()
  if Settings.windowPending then Settings.applyWindow() end
end

function Settings.applyWindow()
  if platform.web then return end -- the web page owns the canvas size and fullscreen
  if love.graphics.getCanvas() then
    Settings.windowPending = true
    return
  end
  Settings.windowPending = false
  local v = Settings.values
  local w, h = Settings.parseResolution(v.resolution)
  local display = Settings.display()
  local flags = {
    vsync = v.vsyncMode,
    resizable = true,
    minwidth = 640,
    minheight = 360,
    display = display,
  }
  if v.windowMode == "fullscreen" then
    flags.fullscreen = true
    flags.fullscreentype = "exclusive"
  elseif v.windowMode == "borderless" then
    flags.fullscreen = true
    flags.fullscreentype = "desktop"
    w, h = 0, 0
  else
    flags.fullscreen = false
    -- Don't open a window bigger than the desktop.
    local dw, dh = love.window.getDesktopDimensions(display)
    if w > dw or h > dh then w, h = math.floor(dw * 0.9), math.floor(dh * 0.9) end
  end
  local ok = pcall(love.window.setMode, w, h, flags)
  if not ok then
    -- Unsupported mode (e.g. exclusive fullscreen at that size): fall back to windowed.
    flags.fullscreen = false
    pcall(love.window.setMode, 1280, 720, flags)
  end
end

-- F11 / Alt+Enter: windowed <-> the last fullscreen mode used.
function Settings.toggleFullscreen()
  local v = Settings.values
  if v.windowMode == "windowed" then
    v.windowMode = v.lastFullscreen
  else
    v.lastFullscreen = v.windowMode
    v.windowMode = "windowed"
  end
  Settings.applyWindow()
  Settings.save()
end

function Settings.apply()
  Settings.applyEffects()
  Settings.applyWindow()
  Cards.applyRules(Settings.cardRules())
end

return Settings
