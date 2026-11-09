-- Sound effects: ogg files in assets/sfx, one per name in assets/sfx/sounds.txt.
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

-- assets/sfx/sounds.txt lists every sound, one per line, optionally followed by "ui". A sound's
-- line number is its network id, so only ever add new lines at the end.
sfx.NAMES, sfx.ID = {}, {}
local UI_SOUND = {}
do
  local text = love.filesystem.read("assets/sfx/sounds.txt") or ""
  for line in text:gmatch("[^\r\n]+") do
    local name, flag = line:match("^(%S+)%s*(%S*)")
    if name then
      sfx.NAMES[#sfx.NAMES + 1] = name
      sfx.ID[name] = #sfx.NAMES
      if flag == "ui" then UI_SOUND[name] = true end
    end
  end
end

local sounds = {}
local lastPlay = {}
local queue = {}
local random = math.random

local function build(name)
  if sounds[name] or not sfx.ID[name] then return sounds[name] end
  local ok, src = pcall(love.audio.newSource, "assets/sfx/" .. name .. ".ogg", "static")
  if not ok then return nil end
  sounds[name] = { voices = { src }, ui = UI_SOUND[name] }
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

-- How much of the sound set has been built (0-1), for the loading bar.
function sfx.progress()
  if not queue then return 1 end
  local total = #sfx.NAMES
  return math.max(0, math.min(1, 1 - #queue / total))
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
  if not noRecord and fx.recorder and sfx.ID[name] and not UI_SOUND[name] then
    fx.record({ 5, sfx.ID[name], x or (Map.W / 2), volume or 1, pitch or 1 })
  end
  if not sfx.enabled or not sfx.ID[name] then return end
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

require("game.events").handle("sfx", sfx)

return sfx
