-- Player settings: saved to settings.txt in the LÖVE save folder.
local Bloom = require "gfx.bloom"
local fx = require "gfx.fx"
local Cards = require "game.cards"
local Map = require "game.map"
local platform = require "core.platform"

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

-- Key bindings. Values are LÖVE key constants or "mouse1".."mouse5".
Settings.BIND_SCHEMES = {
  { id = "p1", name = "Player 1 (local)", group = "keyboard",
    actions = { "left", "right", "up", "down", "fire", "block", "dash", "melee" } },
  { id = "p2", name = "Player 2 (local)", group = "keyboard",
    actions = { "left", "right", "up", "down", "fire", "block", "dash", "melee" } },
  { id = "online", name = "Online", group = "online",
    actions = { "left", "right", "jump", "jump2", "down", "fire", "block", "dash", "melee" } },
}
Settings.ACTION_NAMES = {
  left = "Left", right = "Right", up = "Up / Jump", down = "Down", fire = "Fire", block = "Block",
  jump = "Jump", jump2 = "Jump (alt)", dash = "Dash", melee = "Melee (hold: heavy)",
}
Settings.DEFAULT_BINDS = {
  p1 = { left = "a", right = "d", up = "w", down = "s", fire = "space", block = "lshift", dash = "e", melee = "q" },
  p2 = { left = "left", right = "right", up = "up", down = "down", fire = "rctrl", block = "rshift",
    dash = "/", melee = "." },
  online = { left = "a", right = "d", jump = "space", jump2 = "w", down = "s", fire = "mouse1", block = "mouse2",
    dash = "lshift", melee = "f" },
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
  bloomLevel = 2,
  shake = 3,
  particles = 2,
  showFps = false,
  roundsToWin = 5,
  pickFrom = 3,
  picksPerRound = 1,
  playerName = "Player", -- shown to others in LAN games
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
  local legacyVsync, legacyRes
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
  for _, r in ipairs(Cards.RARITIES) do
    local key = "weight_" .. r.id
    v[key] = clamp(math.floor(v[key]), 0, 1000)
  end
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

function Settings.resetGameplay()
  local v = Settings.values
  v.roundsToWin = defaults.roundsToWin
  v.pickFrom = defaults.pickFrom
  v.picksPerRound = defaults.picksPerRound
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
function Settings.cardRules()
  local v = Settings.values
  local rules = { pickFrom = v.pickFrom, picksPerRound = v.picksPerRound, weights = {}, rarity = {}, disabled = {} }
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
  Bloom.enabled = v.bloom
  Bloom.intensity = Settings.BLOOM_LEVELS[v.bloomLevel][2]
  fx.shakeScale = Settings.SHAKE_LEVELS[v.shake][2]
  fx.particleScale = Settings.PARTICLE_LEVELS[v.particles][2]
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
