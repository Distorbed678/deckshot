-- Music: three looping stems in assets/music. A relaxed menu loop, a driving match loop, and an
-- extra layer that fades in during sudden death.

local Music = { intensity = 0, muffle = 0 }

local order = { "menu", "match", "sudden" }
local stems = {}
local current

local function loadNext()
  for _, name in ipairs(order) do
    if not stems[name] then
      local ok, src = pcall(love.audio.newSource, "assets/music/" .. name .. ".ogg", "static")
      if ok then
        src:setLooping(true)
        src:setVolume(0)
        stems[name] = { src = src, vol = 0 }
      else
        stems[name] = { vol = 0 }
      end
      return
    end
  end
end

-- How much of the music has been built (0-1), for the loading bar.
function Music.progress()
  local done = 0
  for _, name in ipairs(order) do
    if stems[name] then done = done + 1 end
  end
  return done / #order
end

function Music.play(name)
  Music.wanted = name
end

function Music.setMuffle(k)
  Music.muffle = k
end

function Music.setIntensity(k)
  Music.intensity = k
end

local function setFilter(src, k)
  if k <= 0.01 then
    pcall(src.setFilter, src)
  else
    pcall(src.setFilter, src, { type = "lowpass", volume = 1 - k * 0.2, highgain = 1 - k * 0.92 })
  end
end

function Music.update(dt)
  local sfx = require "gfx.sfx"
  if sfx.silent or not love.audio or not sfx.enabled then return end
  loadNext()
  if current ~= Music.wanted and stems.sudden and stems.sudden.src then
    current = Music.wanted
    -- Match and sudden stems start together so they stay in time.
    if current == "match" then
      stems.match.src:seek(0)
      stems.sudden.src:seek(0)
      stems.match.src:play()
      stems.sudden.src:play()
    elseif current == "menu" then
      stems.menu.src:play()
    end
  end
  local v = sfx.volumes
  local base = v.master * v.music * 0.55
  local function fade(s, target)
    if not s or not s.src then return end
    s.vol = s.vol + (target - s.vol) * math.min(1, dt * 3)
    s.src:setVolume(math.max(0, s.vol))
    setFilter(s.src, Music.muffle)
    if target == 0 and s.vol < 0.002 and s.src:isPlaying() then s.src:stop() end
  end
  fade(stems.menu, current == "menu" and base or 0)
  fade(stems.match, current == "match" and base or 0)
  fade(stems.sudden, current == "match" and base * Music.intensity or 0)
end

return Music
