-- Sound effects, synthesized in code (no audio files needed).
-- Every sound is a list of layers (oscillator or noise with a pitch sweep, envelope and
-- low-pass). If assets/sfx/<name>.ogg (or .wav) exists it is used instead, so real sounds
-- can be dropped in later by name.
-- On the online host, sounds are recorded with the fx events and replayed on clients.
local fx = require "gfx.fx"
local Map = require "game.map"

local sfx = {
  volumes = { master = 0.8, sfx = 1, ui = 0.8, music = 0.7 },
  enabled = true,
}

local RATE = 22050
local POOL = 6          -- voices per sound
local MIN_GAP = 0.03    -- the same sound can't restart faster than this

-- Layer fields: wave (sine/square/saw/tri/noise), dur, f0, f1 (sweep end), vol, attack,
-- decay (envelope power), lp (low-pass 0..1, 1 = off), at (start offset), vib (vibrato Hz).
local function L(t) return t end

-- An arpeggio: one short layer per note.
local function arp(wave, notes, step, dur, vol, lp)
  local out = {}
  for i, f in ipairs(notes) do
    out[#out + 1] = L { wave = wave, dur = dur, f0 = f, vol = vol, at = (i - 1) * step, decay = 1.5, lp = lp }
  end
  return out
end

local function join(...)
  local out = {}
  for _, list in ipairs({ ... }) do
    for _, l in ipairs(list) do out[#out + 1] = l end
  end
  return out
end

-- name -> { layers, ui = true for menu sounds (not recorded, UI volume) }
local DEFS = {
  shoot = { L { wave = "square", dur = 0.09, f0 = 900, f1 = 280, vol = 0.3, lp = 0.5 },
    L { wave = "noise", dur = 0.05, vol = 0.25, lp = 0.5 } },
  shotgun = { L { wave = "noise", dur = 0.2, vol = 0.55, lp = 0.3, decay = 2 },
    L { wave = "square", dur = 0.12, f0 = 300, f1 = 90, vol = 0.3, lp = 0.4 } },
  laser = { L { wave = "saw", dur = 0.25, f0 = 1800, f1 = 500, vol = 0.25, lp = 0.6 },
    L { wave = "sine", dur = 0.2, f0 = 2400, f1 = 1200, vol = 0.2 } },
  impactWood = { L { wave = "noise", dur = 0.07, vol = 0.32, lp = 0.2 },
    L { wave = "tri", dur = 0.06, f0 = 240, f1 = 130, vol = 0.3 } },
  impactMetal = { L { wave = "square", dur = 0.09, f0 = 1500, f1 = 1050, vol = 0.14, lp = 0.7 },
    L { wave = "sine", dur = 0.14, f0 = 2300, f1 = 1900, vol = 0.12 } },
  impactGlass = { L { wave = "sine", dur = 0.06, f0 = 3100, f1 = 3600, vol = 0.15 },
    L { wave = "noise", dur = 0.04, vol = 0.14, lp = 0.8 } },
  hitHeavy = { L { wave = "square", dur = 0.18, f0 = 220, f1 = 55, vol = 0.5, lp = 0.35 },
    L { wave = "noise", dur = 0.14, vol = 0.5, lp = 0.25 } },
  gibs = { L { wave = "noise", dur = 0.22, vol = 0.45, lp = 0.2, decay = 2 },
    L { wave = "sine", dur = 0.2, f0 = 300, f1 = 70, vol = 0.4 } },
  stingerRound = join(arp("square", { 523, 659, 784 }, 0.08, 0.26, 0.17, 0.5), arp("tri", { 262, 330, 392 }, 0.08, 0.3, 0.22)),
  stingerMatchPoint = join(arp("saw", { 440, 440, 659, 880 }, 0.14, 0.32, 0.16, 0.5), arp("tri", { 220, 220, 330, 440 }, 0.14, 0.34, 0.24)),
  bounce = { L { wave = "sine", dur = 0.05, f0 = 1200, f1 = 1700, vol = 0.18 } },
  impact = { L { wave = "noise", dur = 0.06, vol = 0.3, lp = 0.4 },
    L { wave = "square", dur = 0.04, f0 = 400, f1 = 200, vol = 0.15, lp = 0.4 } },
  hit = { L { wave = "square", dur = 0.1, f0 = 320, f1 = 110, vol = 0.4, lp = 0.45 },
    L { wave = "noise", dur = 0.08, vol = 0.35, lp = 0.3 } },
  crit = { L { wave = "square", dur = 0.12, f0 = 900, f1 = 1500, vol = 0.25, lp = 0.6 },
    L { wave = "square", dur = 0.1, f0 = 320, f1 = 110, vol = 0.35, lp = 0.45 },
    L { wave = "noise", dur = 0.1, vol = 0.35, lp = 0.35 } },
  block = { L { wave = "tri", dur = 0.14, f0 = 620, vol = 0.4 },
    L { wave = "sine", dur = 0.16, f0 = 1240, vol = 0.25 } },
  parry = { L { wave = "sine", dur = 0.22, f0 = 1400, f1 = 2100, vol = 0.3 },
    L { wave = "tri", dur = 0.22, f0 = 700, f1 = 1050, vol = 0.3 } },
  reflect = { L { wave = "saw", dur = 0.12, f0 = 500, f1 = 1500, vol = 0.25, lp = 0.5 } },
  empty = { L { wave = "square", dur = 0.025, f0 = 1500, vol = 0.18, lp = 0.6 } },
  reload = { L { wave = "noise", dur = 0.05, vol = 0.25, lp = 0.6 },
    L { wave = "square", dur = 0.04, f0 = 500, vol = 0.15, at = 0.07, lp = 0.5 } },
  reloaded = { L { wave = "square", dur = 0.03, f0 = 700, vol = 0.18, lp = 0.6 },
    L { wave = "square", dur = 0.04, f0 = 1000, vol = 0.18, at = 0.06, lp = 0.6 } },
  jump = { L { wave = "square", dur = 0.1, f0 = 260, f1 = 520, vol = 0.18, lp = 0.4 } },
  doubleJump = { L { wave = "square", dur = 0.11, f0 = 420, f1 = 840, vol = 0.18, lp = 0.4 },
    L { wave = "noise", dur = 0.06, vol = 0.12, lp = 0.6 } },
  wallJump = { L { wave = "noise", dur = 0.06, vol = 0.2, lp = 0.5 },
    L { wave = "square", dur = 0.09, f0 = 300, f1 = 620, vol = 0.16, lp = 0.4 } },
  land = { L { wave = "noise", dur = 0.08, vol = 0.35, lp = 0.2 },
    L { wave = "sine", dur = 0.1, f0 = 130, f1 = 60, vol = 0.35 } },
  dash = { L { wave = "noise", dur = 0.2, vol = 0.35, lp = 0.18, attack = 0.02 },
    L { wave = "saw", dur = 0.15, f0 = 200, f1 = 800, vol = 0.18, lp = 0.3 } },
  dashReady = { L { wave = "sine", dur = 0.06, f0 = 1600, f1 = 2000, vol = 0.12 } },
  meleeLight = { L { wave = "noise", dur = 0.11, vol = 0.35, lp = 0.45, attack = 0.03 },
    L { wave = "sine", dur = 0.08, f0 = 500, f1 = 300, vol = 0.1 } },
  meleeHeavy = { L { wave = "noise", dur = 0.24, vol = 0.5, lp = 0.25, attack = 0.07 },
    L { wave = "saw", dur = 0.22, f0 = 140, f1 = 55, vol = 0.3, lp = 0.25 } },
  meleeCharge = { L { wave = "sine", dur = 0.6, f0 = 180, f1 = 700, vol = 0.16, attack = 0.1, decay = 0.4, vib = 12 } },
  meleeHit = { L { wave = "noise", dur = 0.07, vol = 0.4, lp = 0.3 },
    L { wave = "square", dur = 0.08, f0 = 230, f1 = 110, vol = 0.35, lp = 0.4 } },
  meleeHitHeavy = { L { wave = "noise", dur = 0.16, vol = 0.65, lp = 0.2 },
    L { wave = "sine", dur = 0.22, f0 = 95, f1 = 40, vol = 0.6 },
    L { wave = "square", dur = 0.08, f0 = 180, f1 = 90, vol = 0.25, lp = 0.3 } },
  stun = { L { wave = "tri", dur = 0.35, f0 = 1800, vol = 0.3, vib = 18, decay = 1.2 },
    L { wave = "square", dur = 0.2, f0 = 900, vol = 0.12, lp = 0.5 },
    L { wave = "noise", dur = 0.05, vol = 0.3, lp = 0.5 } },
  edge = { L { wave = "saw", dur = 0.22, f0 = 220, f1 = 80, vol = 0.4, lp = 0.35 },
    L { wave = "noise", dur = 0.12, vol = 0.3, lp = 0.4 } },
  edgeBlock = { L { wave = "tri", dur = 0.16, f0 = 500, f1 = 950, vol = 0.35 } },
  death = { L { wave = "square", dur = 0.45, f0 = 420, f1 = 55, vol = 0.35, lp = 0.4 },
    L { wave = "noise", dur = 0.35, vol = 0.4, lp = 0.25 } },
  revive = { L { wave = "sine", dur = 0.5, f0 = 300, f1 = 1200, vol = 0.3 },
    L { wave = "tri", dur = 0.5, f0 = 600, f1 = 1800, vol = 0.2, at = 0.05 } },
  explosion = { L { wave = "noise", dur = 0.55, vol = 0.85, lp = 0.12, decay = 1.6 },
    L { wave = "sine", dur = 0.4, f0 = 85, f1 = 30, vol = 0.65 } },
  explosionSmall = { L { wave = "noise", dur = 0.25, vol = 0.55, lp = 0.2 },
    L { wave = "sine", dur = 0.2, f0 = 130, f1 = 50, vol = 0.45 } },
  mineArm = { L { wave = "square", dur = 0.04, f0 = 1200, vol = 0.15, lp = 0.6 },
    L { wave = "square", dur = 0.04, f0 = 1600, vol = 0.15, at = 0.06, lp = 0.6 } },
  blackhole = { L { wave = "sine", dur = 0.8, f0 = 70, f1 = 30, vol = 0.5, attack = 0.1, decay = 0.8 },
    L { wave = "saw", dur = 0.7, f0 = 130, f1 = 40, vol = 0.2, lp = 0.08 } },
  beep = { L { wave = "square", dur = 0.12, f0 = 880, vol = 0.22, lp = 0.5 } },
  fight = { L { wave = "square", dur = 0.4, f0 = 440, f1 = 880, vol = 0.25, lp = 0.45 },
    L { wave = "saw", dur = 0.4, f0 = 660, f1 = 1320, vol = 0.18, lp = 0.35 } },
  roundWin = arp("tri", { 523, 659, 784 }, 0.09, 0.18, 0.35),
  matchWin = join(arp("tri", { 523, 659, 784, 1046 }, 0.13, 0.3, 0.35),
    { L { wave = "sine", dur = 0.9, f0 = 1046, vol = 0.25, at = 0.5, decay = 1.2, vib = 6 } }),
  cardDeal = { L { wave = "noise", dur = 0.05, vol = 0.22, lp = 0.7 } },
  cardFlip = { L { wave = "noise", dur = 0.07, vol = 0.22, lp = 0.5 },
    L { wave = "tri", dur = 0.05, f0 = 900, f1 = 1200, vol = 0.15 } },
  revealRare = { L { wave = "sine", dur = 0.25, f0 = 1200, f1 = 1800, vol = 0.22 },
    L { wave = "sine", dur = 0.2, f0 = 1800, f1 = 2400, vol = 0.15, at = 0.05 } },
  revealEpic = join(arp("sine", { 988, 1319, 1568 }, 0.06, 0.2, 0.22),
    { L { wave = "tri", dur = 0.4, f0 = 1976, vol = 0.1, at = 0.15, vib = 9 } }),
  revealLegendary = join(arp("sine", { 1047, 1319, 1568, 2093 }, 0.07, 0.3, 0.24),
    arp("tri", { 2093, 2637, 3136 }, 0.05, 0.25, 0.1),
    { L { wave = "sine", dur = 0.9, f0 = 2093, vol = 0.12, at = 0.3, vib = 7, decay = 1.3 } }),
  cardPick = { L { wave = "tri", dur = 0.12, f0 = 660, f1 = 990, vol = 0.3 },
    L { wave = "sine", dur = 0.18, f0 = 1320, vol = 0.18, at = 0.05 } },
  heartbeat = { L { wave = "sine", dur = 0.12, f0 = 75, f1 = 50, vol = 0.6 },
    L { wave = "sine", dur = 0.1, f0 = 65, f1 = 45, vol = 0.45, at = 0.22 } },
  uiHover = { ui = true, L { wave = "sine", dur = 0.03, f0 = 1400, vol = 0.08 } },
  uiClick = { ui = true, L { wave = "square", dur = 0.045, f0 = 900, f1 = 700, vol = 0.15, lp = 0.5 } },
  uiBack = { ui = true, L { wave = "square", dur = 0.05, f0 = 700, f1 = 480, vol = 0.15, lp = 0.5 } },
}

-- Network ids: the order of this list (sent as a byte). Append new sounds at the end.
sfx.NAMES = {
  "shoot", "shotgun", "laser", "bounce", "impact", "hit", "crit", "block", "parry", "reflect",
  "empty", "reload", "reloaded", "jump", "doubleJump", "wallJump", "land", "dash", "dashReady",
  "meleeLight", "meleeHeavy", "meleeCharge", "meleeHit", "meleeHitHeavy", "stun", "edge", "edgeBlock",
  "death", "revive", "explosion", "explosionSmall", "mineArm", "blackhole", "beep", "fight",
  "roundWin", "matchWin", "cardDeal", "cardFlip", "revealRare", "revealEpic", "revealLegendary",
  "cardPick", "heartbeat", "uiHover", "uiClick", "uiBack",
  "impactWood", "impactMetal", "impactGlass", "hitHeavy", "gibs", "stingerRound", "stingerMatchPoint",
}
sfx.ID = {}
for i, n in ipairs(sfx.NAMES) do sfx.ID[n] = i end

-- Register more sounds (map objects etc.). They get network ids after the built-in ones.
function sfx.define(name, def)
  DEFS[name] = def
  if not sfx.ID[name] then
    sfx.NAMES[#sfx.NAMES + 1] = name
    sfx.ID[name] = #sfx.NAMES
  end
end

---------------------------------------------------------------- synthesis
local sin, floor, random = math.sin, math.floor, math.random
local TAU = math.pi * 2

local function render(def)
  local total = 0
  for _, l in ipairs(def) do total = math.max(total, (l.at or 0) + l.dur) end
  local n = math.max(1, floor(total * RATE))
  local buf = {}
  for i = 1, n do buf[i] = 0 end
  for _, l in ipairs(def) do
    local start = floor((l.at or 0) * RATE)
    local len = floor(l.dur * RATE)
    local f0, f1 = l.f0 or 440, l.f1 or l.f0 or 440
    local ratio = f1 / f0
    local vol, attack, decay = l.vol or 0.3, l.attack or 0.004, l.decay or 2
    local lp, vib = l.lp or 1, l.vib
    local wave = l.wave
    local phase, y = 0, 0
    for i = 0, len - 1 do
      local prog = i / len
      local freq = f0 * ratio ^ prog
      if vib then freq = freq * (1 + 0.03 * sin(i / RATE * vib * TAU)) end
      phase = (phase + freq / RATE) % 1
      local x
      if wave == "sine" then
        x = sin(phase * TAU)
      elseif wave == "square" then
        x = phase < 0.5 and 1 or -1
      elseif wave == "saw" then
        x = phase * 2 - 1
      elseif wave == "tri" then
        x = phase < 0.5 and phase * 4 - 1 or 3 - phase * 4
      else
        x = random() * 2 - 1
      end
      y = y + lp * (x - y)
      local t = i / RATE
      local env = (t < attack) and (t / attack) or (1 - prog) ^ decay
      local k = start + i + 1
      if k <= n then buf[k] = buf[k] + y * env * vol end
    end
  end
  local sd = love.sound.newSoundData(n, RATE, 16, 1)
  for i = 1, n do
    local v = buf[i]
    if v > 1 then v = 1 elseif v < -1 then v = -1 end
    sd:setSample(i - 1, v)
  end
  return sd
end

local sounds = {}   -- name -> { voices = { Source... }, base = Source, ui = bool }
local lastPlay = {}
local queue         -- names still to prebuild

local function build(name)
  local def = DEFS[name]
  if not def or sounds[name] then return sounds[name] end
  local src
  for _, ext in ipairs({ ".ogg", ".wav" }) do
    local path = "assets/sfx/" .. name .. ext
    if love.filesystem.getInfo(path) then
      local ok, s = pcall(love.audio.newSource, path, "static")
      if ok then src = s break end
    end
  end
  if not src then
    local ok, s = pcall(function() return love.audio.newSource(render(def), "static") end)
    if not ok then return nil end
    src = s
  end
  sounds[name] = { voices = { src }, ui = def.ui }
  return sounds[name]
end

function sfx.load()
  if not love.audio then
    sfx.enabled = false
    return
  end
  pcall(love.audio.setDistanceModel, "none")
  queue = {}
  for _, n in ipairs(sfx.NAMES) do queue[#queue + 1] = n end
end

-- Builds a few sounds per frame so start-up stays quick (the web build has no JIT).
function sfx.update()
  if not queue then return end
  local t = love.timer.getTime()
  while #queue > 0 and love.timer.getTime() - t < 0.004 do build(table.remove(queue, 1)) end
  if #queue == 0 then queue = nil end
end

---------------------------------------------------------------- playback
-- x: arena x for stereo pan (nil = centre). volume / pitch: multipliers.
-- noRecord: don't send to online clients (used when replaying).
function sfx.play(name, x, volume, pitch, noRecord)
  if sfx.silent then return end
  if not noRecord and fx.recorder and sfx.ID[name] and not (DEFS[name] and DEFS[name].ui) then
    fx.record({ 5, sfx.ID[name], x or (Map.W / 2), volume or 1, pitch or 1 })
  end
  if not sfx.enabled or not DEFS[name] then return end
  local now = love.timer.getTime()
  if lastPlay[name] and now - lastPlay[name] < MIN_GAP then return end
  lastPlay[name] = now
  local snd = build(name)
  if not snd then return end
  local v = sfx.volumes
  local vol = (volume or 1) * v.master * (snd.ui and v.ui or v.sfx)
  if vol <= 0.001 then return end

  local src
  for _, s in ipairs(snd.voices) do
    if not s:isPlaying() then src = s break end
  end
  if not src then
    if #snd.voices < POOL then
      src = snd.voices[1]:clone()
      snd.voices[#snd.voices + 1] = src
    else
      src = snd.voices[1]
      table.insert(snd.voices, table.remove(snd.voices, 1))
      src:stop()
    end
  end
  src:setVolume(math.min(1, vol))
  if not snd.ui then pcall(src.setFilter, src, sfx.muffle) end
  src:setPitch((pitch or 1) * (0.94 + random() * 0.12))
  local pan = x and math.max(-1, math.min(1, (x / (Map.W / 2) - 1) * 0.7)) or 0
  pcall(src.setPosition, src, pan, 0, 0.6)
  src:play()
end

-- Sound by network id (clients replaying the host's sounds).
function sfx.playId(id, x, volume, pitch)
  local name = sfx.NAMES[id]
  if name then sfx.play(name, x, volume, pitch, true) end
end

function sfx.ui(name)
  sfx.play(name, nil, 1, 1, true)
end

-- Window focus: optionally mute in the background.
function sfx.focus(focused, muteUnfocused)
  if love.audio then love.audio.setVolume((focused or not muteUnfocused) and 1 or 0) end
end

return sfx
