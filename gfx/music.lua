-- Original synthesized synthwave, generated in the game like the sound effects. Three stems:
-- a relaxed menu loop, a driving match loop, and an extra layer that fades in during sudden death.
-- Stems are built a little at a time so start-up stays quick (the web build has no JIT).
local platform = require "core.platform"

local Music = { intensity = 0, muffle = 0 }

local RATE = platform.web and 11025 or 22050
local BARS = platform.web and 4 or 8
local BPM = 118
local STEP = 60 / BPM / 4
local LEN = math.floor(BARS * 16 * STEP * RATE)

-- Chord roots (MIDI) per bar: a minor, F, C, G.
local CHORDS = { { 57, 60, 64 }, { 53, 57, 60 }, { 60, 64, 67 }, { 55, 59, 62 } }

local function freq(n) return 440 * 2 ^ ((n - 69) / 12) end

local function addNote(buf, startT, dur, f, vol, wave, attack, release)
  local a, b = math.floor(startT * RATE), math.floor((startT + dur) * RATE)
  local inc = f / RATE
  local phase = 0
  local at, rel = attack * RATE, release * RATE
  for i = a, b - 1 do
    local n = i - a
    local env = 1
    if n < at then env = n / at elseif b - i < rel then env = (b - i) / rel end
    local s
    if wave == "saw" then s = 2 * (phase % 1) - 1
    elseif wave == "square" then s = (phase % 1) < 0.5 and 0.7 or -0.7
    else s = 1 - 4 * math.abs((phase % 1) - 0.5) end
    local j = i % LEN + 1
    buf[j] = buf[j] + s * env * vol
    phase = phase + inc
  end
end

local function addKick(buf, t, vol)
  local a = math.floor(t * RATE)
  local n = math.floor(0.16 * RATE)
  local phase = 0
  for i = 0, n - 1 do
    local k = i / n
    phase = phase + (45 + 110 * (1 - k) ^ 3) / RATE
    local j = (a + i) % LEN + 1
    buf[j] = buf[j] + math.sin(phase * 2 * math.pi) * (1 - k) ^ 2 * vol
  end
end

local function addNoise(buf, t, dur, vol, rng)
  local a = math.floor(t * RATE)
  local n = math.floor(dur * RATE)
  local last = 0
  for i = 0, n - 1 do
    local k = 1 - i / n
    local w = rng:random() * 2 - 1
    local s = w - last -- a simple high-pass, so it sounds like a hat or snare
    last = w
    local j = (a + i) % LEN + 1
    buf[j] = buf[j] + s * k * k * vol
  end
end

local function bars(fn)
  for bar = 0, BARS - 1 do
    fn(bar, bar * 16 * STEP, CHORDS[bar % #CHORDS + 1])
  end
end

local BUILD = {
  menu = function(buf, pause)
    bars(function(bar, t, ch)
      for _, n in ipairs(ch) do
        addNote(buf, t, 16 * STEP, freq(n), 0.08, "tri", 0.25, 0.35)
        addNote(buf, t, 16 * STEP, freq(n) * 1.005, 0.05, "saw", 0.4, 0.4)
      end
      pause()
      addNote(buf, t, 16 * STEP, freq(ch[1] - 24), 0.2, "tri", 0.05, 0.2)
      local pat = { 1, 2, 3, 2, 3, 2, 1, 2 }
      for s = 0, 7 do
        addNote(buf, t + s * 2 * STEP, 2 * STEP, freq(ch[pat[s + 1]] + 12), 0.07, "tri", 0.01, 0.15)
      end
      if bar % 2 == 0 then addKick(buf, t, 0.3) end
      pause()
    end)
  end,
  match = function(buf, pause, rng)
    bars(function(_, t, ch)
      for s = 0, 15 do
        local n = ch[1] - 24
        addNote(buf, t + s * STEP, STEP * 0.85, freq(s % 4 == 3 and n + 12 or n), 0.2, "saw", 0.004, 0.03)
      end
      pause()
      for s = 0, 15 do
        local pick = ch[(s % 3) + 1] + (s % 8 >= 4 and 24 or 12)
        addNote(buf, t + s * STEP, STEP * 0.8, freq(pick), 0.075, "square", 0.004, 0.05)
      end
      pause()
      for s = 0, 15 do
        if s % 4 == 0 then addKick(buf, t + s * STEP, 0.5) end
        if s % 8 == 4 then addNoise(buf, t + s * STEP, 0.14, 0.26, rng) end
        addNoise(buf, t + s * STEP, 0.03, s % 2 == 1 and 0.11 or 0.06, rng)
      end
      for _, n in ipairs(ch) do addNote(buf, t, 16 * STEP, freq(n), 0.045, "saw", 0.1, 0.1) end
      pause()
    end)
  end,
  sudden = function(buf, pause, rng)
    bars(function(_, t, ch)
      for s = 0, 15 do
        addNote(buf, t + s * STEP, STEP * 0.6, freq(ch[(s % 3) + 1] + 24 + (s % 2) * 12), 0.08, "saw", 0.003, 0.03)
      end
      pause()
      for s = 0, 15 do
        if s % 2 == 0 then addKick(buf, t + s * STEP, 0.25) end
        addNoise(buf, t + s * STEP, 0.05, 0.1, rng)
      end
      addNote(buf, t, 16 * STEP, freq(ch[1] + 12), 0.05, "square", 0.5, 0.1)
      pause()
    end)
  end,
}

local stems = {}
local order = { "menu", "match", "sudden" }
local worker
local current

local function buildAll()
  local deadline = love.timer.getTime() + 0.004
  local function pause()
    if love.timer.getTime() > deadline then
      coroutine.yield()
      deadline = love.timer.getTime() + 0.004
    end
  end
  local rng = love.math.newRandomGenerator(4242)
  for _, name in ipairs(order) do
    local buf = {}
    for i = 1, LEN do buf[i] = 0 end
    pause()
    BUILD[name](buf, pause, rng)
    local peak = 0.001
    for i = 1, LEN do
      if buf[i] > peak then peak = buf[i] elseif -buf[i] > peak then peak = -buf[i] end
    end
    local sd = love.sound.newSoundData(LEN, RATE, 16, 1)
    local gain = 0.9 / peak
    for i = 1, LEN do
      sd:setSample(i - 1, buf[i] * gain)
      if i % 20000 == 0 then pause() end
    end
    local src = love.audio.newSource(sd, "static")
    src:setLooping(true)
    src:setVolume(0)
    stems[name] = { src = src, vol = 0 }
    pause()
  end
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
  if not worker and not stems.sudden then worker = coroutine.create(buildAll) end
  if worker then
    local ok, err = coroutine.resume(worker)
    if not ok then
      worker, stems.sudden = nil, { src = nil, vol = 0 }
      print("music: " .. tostring(err))
    elseif coroutine.status(worker) == "dead" then
      worker = nil
    end
  end
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
