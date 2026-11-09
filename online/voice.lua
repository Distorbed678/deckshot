-- Voice chat for Steam and LAN, desktop only. The microphone is only opened when the player has
-- turned voice on and is in a session (or is looking at the level meter in Settings).
-- Audio is 16 kHz mono in 40 ms frames, IMA ADPCM (4:1), with the codec state in every packet so a
-- lost packet only costs its own 40 ms. Clients send to the host, and the host forwards to the rest.
local platform = require "core.platform"
local Settings = require "core.settings"
local net = require "online.net"
local active = require "online.active"

local Voice = {
  speaking = {},   -- peer -> time of their last audio
  muted = {},      -- peer -> true
  level = 0,       -- mic level, 0-1
  monitorT = -10,  -- Settings is showing the level meter
  sent = 0, received = 0,
}

local RATE, FRAME, MAX_PACKET = 16000, 640, 700
local OPEN_MIC_HOLD = 0.35
Voice.THRESHOLDS = { 0.01, 0.02, 0.04, 0.08 }
Voice.THRESHOLD_NAMES = { "Very sensitive", "Sensitive", "Normal", "Loud voices only" }

local STEPS = {
  7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107,
  118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963,
  1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894,
  6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
}
local ADJUST = { -1, -1, -1, -1, 2, 4, 6, 8 }
local floor = math.floor

local function clampIndex(i) return i < 0 and 0 or (i > 88 and 88 or i) end
local function clamp16(v) return v < -32768 and -32768 or (v > 32767 and 32767 or v) end

-- samples[1..FRAME] (integers) -> packet: first predictor (2 bytes), step index, then 4 bits per sample.
function Voice.encode(samples)
  local pred, index = samples[1], 0
  local u = pred + 32768
  local out = { string.char(u % 256, floor(u / 256), index) }
  local hold
  for n = 1, FRAME do
    local diff = samples[n] - pred
    local step = STEPS[index + 1]
    local code = 0
    if diff < 0 then code, diff = 8, -diff end
    local vp = floor(step / 8)
    if diff >= step then code, diff, vp = code + 4, diff - step, vp + step end
    local half = floor(step / 2)
    if diff >= half then code, diff, vp = code + 2, diff - half, vp + half end
    local quarter = floor(step / 4)
    if diff >= quarter then code, vp = code + 1, vp + quarter end
    pred = clamp16(code >= 8 and pred - vp or pred + vp)
    index = clampIndex(index + ADJUST[code % 8 + 1])
    if hold then
      out[#out + 1] = string.char(hold + code * 16)
      hold = nil
    else
      hold = code
    end
  end
  if hold then out[#out + 1] = string.char(hold) end
  return table.concat(out)
end

-- packet -> list of FRAME integers, or nil if it's the wrong size.
function Voice.decode(data, first)
  first = first or 1
  if #data - first + 1 ~= 3 + FRAME / 2 then return nil end
  local lo, hi, index = data:byte(first, first + 2)
  local pred = lo + hi * 256 - 32768
  index = clampIndex(index)
  local out = {}
  for n = 1, FRAME do
    local b = data:byte(first + 3 + floor((n - 1) / 2))
    local code = n % 2 == 1 and b % 16 or floor(b / 16)
    local step = STEPS[index + 1]
    local vp = floor(step / 8)
    local mag = code % 8
    if mag >= 4 then vp = vp + step end
    if mag % 4 >= 2 then vp = vp + floor(step / 2) end
    if mag % 2 == 1 then vp = vp + floor(step / 4) end
    pred = clamp16(code >= 8 and pred - vp or pred + vp)
    index = clampIndex(index + ADJUST[mag + 1])
    out[n] = pred
  end
  return out
end

---------------------------------------------------------------- session helpers
local function sessionNow()
  local ok, s = pcall(active.get)
  if not ok or not s then return nil end
  if s.kind == "lan" then return s.active and s or nil end
  if s.inLobby and s.inLobby() then return s end
  return nil
end

local function forward(session, data, except)
  for _, m in ipairs(session.members) do
    if m.id ~= session.myId() and m.id ~= except and not (session.isWebPeer and session.isWebPeer(m.id)) then
      session.transport:send(m.id, data, false)
    end
  end
end

---------------------------------------------------------------- playback
local players = {}

local function play(peer, samples)
  local v = Settings.values
  local p = players[peer]
  if not p then
    local ok, src = pcall(love.audio.newQueueableSource, RATE, 16, 1, 8)
    if not ok then return end
    p = { src = src, data = love.sound.newSoundData(FRAME, RATE, 16, 1), waiting = 0 }
    players[peer] = p
  end
  if p.src:getFreeBufferCount() == 0 then return end -- too far behind: drop rather than lag
  for i = 1, FRAME do p.data:setSample(i - 1, samples[i] / 32768) end
  p.src:setVolume((v.volMaster or 10) / 10 * (v.volVoice or 8) / 10)
  p.src:queue(p.data)
  if not p.src:isPlaying() then
    p.waiting = p.waiting + 1
    if p.waiting >= 2 then -- a little buffered, to ride out uneven arrival
      p.src:play()
      p.waiting = 0
    end
  end
end

local function stopPlayback()
  for peer, p in pairs(players) do
    p.src:stop()
    players[peer] = nil
  end
end

-- A VOICE message arrived (lobby or match network loop).
function Voice.receive(session, msg)
  if platform.web then return end
  local ok, speaker, first = pcall(net.decodeVoice, msg.data)
  if not ok or #msg.data - first + 1 > MAX_PACKET then return end
  if session.isHost then
    speaker = msg.from
    local known = false
    for _, m in ipairs(session.members) do if m.id == speaker then known = true end end
    if not known then return end
    forward(session, net.encodeVoice(speaker, msg.data:sub(first)), speaker)
  elseif msg.from ~= session.hostId then
    return
  end
  Voice.speaking[speaker] = love.timer.getTime()
  Voice.received = Voice.received + 1
  if Settings.values.voiceMode == "off" or Voice.muted[speaker] then return end
  local samples = Voice.decode(msg.data, first)
  if samples then play(speaker, samples) end
end

---------------------------------------------------------------- microphone
local mic, micName
local buffer, bufferN = {}, 0
local lastLoud = -10

function Voice.available()
  return not platform.web and love.audio ~= nil and love.audio.getRecordingDevices ~= nil
end

function Voice.devices()
  if not Voice.available() then return {} end
  local ok, list = pcall(love.audio.getRecordingDevices)
  return ok and list or {}
end

local function stopMic()
  if mic then pcall(mic.stop, mic) end
  mic, micName, bufferN = nil, nil, 0
  Voice.level = 0
end

local function startMic()
  local want = Settings.values.voiceDevice
  if mic and micName == want then return end
  stopMic()
  local list = Voice.devices()
  local chosen = list[1]
  for _, d in ipairs(list) do
    if d:getName() == want then chosen = d end
  end
  if chosen and chosen:start(FRAME * 8, RATE, 16, 1) then mic, micName = chosen, want end
end

function Voice.pushHeld()
  local Input = require "core.input"
  if Input.isDown(Settings.values.binds.online.voice) then return true end
  for _, j in ipairs(Input.pads()) do
    if j:isGamepadDown("rightstick") then return true end
  end
  return false
end

-- One full frame from the microphone (or a test's samples).
function Voice.frame(samples, session)
  local v = Settings.values
  local sum = 0
  for i = 1, FRAME do sum = sum + samples[i] * samples[i] end
  local rms = math.sqrt(sum / FRAME) / 32768
  Voice.level = math.max(rms, Voice.level * 0.8)
  if not session then return end
  local now = love.timer.getTime()
  local talking
  if v.voiceMode == "push" then
    talking = Voice.pushHeld() and not require("core.ui").textWasActive
  else
    if rms >= (Voice.THRESHOLDS[v.voiceThreshold] or 0.04) then lastLoud = now end
    talking = now - lastLoud < OPEN_MIC_HOLD
  end
  if not talking then return end
  local me = session.myId()
  Voice.speaking[me] = now
  Voice.sent = Voice.sent + 1
  local data = net.encodeVoice(session.isHost and me or "", Voice.encode(samples))
  if session.isHost then forward(session, data) else session.transport:send(session.hostId, data, false) end
end

function Voice.update()
  if not Voice.available() then return end
  local v = Settings.values
  local session = sessionNow()
  if not session then
    if next(players) then stopPlayback() end
  end
  local monitoring = love.timer.getTime() - Voice.monitorT < 0.3
  if v.voiceMode == "off" or not (session or monitoring) then
    if mic then stopMic() end
    if v.voiceMode == "off" and next(players) then stopPlayback() end
    return
  end
  startMic()
  if not mic then return end
  local n = mic:getSampleCount()
  if n <= 0 then return end
  local data = mic:getData()
  if not data then return end
  for i = 0, data:getSampleCount() - 1 do
    bufferN = bufferN + 1
    buffer[bufferN] = floor(data:getSample(i) * 32767)
    if bufferN == FRAME then
      Voice.frame(buffer, session)
      bufferN = 0
    end
  end
end

function Voice.isSpeaking(peer)
  return peer ~= nil and love.timer.getTime() - (Voice.speaking[peer] or -10) < 0.25
end

-- A little speaker with sound waves, centred on (x, y).
function Voice.drawIcon(x, y, color)
  love.graphics.setColor(color or { 0.5, 1, 0.6 })
  love.graphics.rectangle("fill", x - 6, y - 2, 3, 4)
  love.graphics.polygon("fill", x - 3, y - 2, x + 1, y - 5, x + 1, y + 5, x - 3, y + 2)
  love.graphics.setLineWidth(1.5)
  love.graphics.arc("line", "open", x + 1, y, 4, -0.8, 0.8)
  love.graphics.arc("line", "open", x + 1, y, 7, -0.8, 0.8)
end

return Voice
