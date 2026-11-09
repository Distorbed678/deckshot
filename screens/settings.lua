-- Settings, shown as an overlay on top of whatever screen opened it.
-- Tabs: Video, Audio, Controls (key rebinding) and Gameplay (everything about how a match plays;
-- a client in a lobby sees the host's gameplay settings, read-only).
local app = require "core.app"
local ui = require "core.ui"
local Settings = require "core.settings"
local Cards = require "game.cards"
local Map = require "game.map"
local Input = require "core.input"
local active = require "online.active"
local platform = require "core.platform"

local Screen = {}
Screen.__index = Screen

local TABS = { "Video", "Audio", "Controls", "Gameplay" }

function Screen.new(tab)
  local s = setmetatable({ tab = tab or 1, capture = nil, scrolls = {} }, Screen)
  s:syncDisplay()
  return s
end

function Screen:enter()
  ui.focus = self.tab -- the tab buttons are the first widgets
end

-- Back from the editor: the main menu with Settings > Gameplay open.
function Screen.reopen()
  app.switch(require("screens.menu").new())
  app.push(Screen.new(4))
end

local function cycle(i, n, d)
  return (i - 1 + d) % n + 1
end

local function indexOf(list, value)
  for i, v in ipairs(list) do
    if v == value then return i end
  end
  return 1
end

function Screen:close()
  Settings.save()
  local session = active.get()
  if session.isHost and session.inLobby() then
    session.setRounds(Settings.values.roundsToWin)
    session.publishRules(Settings.values)
    local under = app.base()
    if under and under.sendInfo then under:sendInfo() end
  end
  app.pop()
end

function Screen:wheelmoved(_, dy)
  if self.tab == 3 and self.controlsScroll then ui.wheel(self.controlsScroll, dy) end
  if self.tab == 4 and self.scroll then ui.wheel(self.scroll, dy) end
end

function Screen:setTab(t)
  self.tab = t
  self:stopCapture()
  ui.reset()
  ui.focus = t -- the tab buttons are the first widgets
end

function Screen:stopCapture()
  self.capture = nil
  ui.capturing = false
end

function Screen:keypressed(key)
  if self.capture then
    if key ~= "escape" and not Settings.RESERVED_KEYS[key] then
      Settings.bind(self.capture.scheme, self.capture.action, key)
    end
    self:stopCapture()
    return
  end
  if key == "escape" then
    self:close()
  elseif key == "q" then
    self:setTab(cycle(self.tab, #TABS, -1))
  elseif key == "e" then
    self:setTab(cycle(self.tab, #TABS, 1))
  end
end

function Screen:mousepressed(x, y, button)
  if self.capture then
    Settings.bind(self.capture.scheme, self.capture.action, "mouse" .. button)
    self:stopCapture()
  end
end

---------------------------------------------------------------- video
-- Display options are edited as pending values and only take effect on Apply.
local DISPLAY_KEYS = { "windowMode", "display", "resolution", "vsyncMode" }

function Screen:syncDisplay()
  self.display = {}
  for _, k in ipairs(DISPLAY_KEYS) do self.display[k] = Settings.values[k] end
  self.displayEdited = false
end

function Screen:displayChanged()
  if not self.displayEdited then return false end
  for _, k in ipairs(DISPLAY_KEYS) do
    if self.display[k] ~= Settings.values[k] then return true end
  end
  return false
end

function Screen:applyDisplay()
  local v = Settings.values
  for _, k in ipairs(DISPLAY_KEYS) do v[k] = self.display[k] end
  if v.windowMode ~= "windowed" then v.lastFullscreen = v.windowMode end
  Settings.applyWindow() -- runs on the next update, outside of drawing
  Settings.save()
  self.displayEdited = false
end

-- Effects options (bloom, shake, particles, FPS counter): one column.
function Screen:drawGraphics(rx, ry, colW, h, gap)
  local v = Settings.values
  local d
  d = ui.cycler("Bloom", v.bloom and "On" or "Off", rx, ry, colW, h)
  if d ~= 0 then
    v.bloom = not v.bloom
    Settings.applyEffects()
  end
  ry = ry + gap

  d = ui.cycler("Dynamic lighting", v.lighting and "On" or "Off", rx, ry, colW, h)
  if d ~= 0 then v.lighting = not v.lighting end
  ry = ry + gap

  d = ui.cycler("Bloom intensity", Settings.BLOOM_LEVELS[v.bloomLevel][1], rx, ry, colW, h)
  if d ~= 0 then
    v.bloomLevel = cycle(v.bloomLevel, #Settings.BLOOM_LEVELS, d)
    Settings.applyEffects()
  end
  ry = ry + gap

  d = ui.cycler("Screen shake", Settings.SHAKE_LEVELS[v.shake][1], rx, ry, colW, h)
  if d ~= 0 then
    v.shake = cycle(v.shake, #Settings.SHAKE_LEVELS, d)
    Settings.applyEffects()
  end
  ry = ry + gap

  d = ui.cycler("Particles", Settings.PARTICLE_LEVELS[v.particles][1], rx, ry, colW, h)
  if d ~= 0 then
    v.particles = cycle(v.particles, #Settings.PARTICLE_LEVELS, d)
    Settings.applyEffects()
  end
  ry = ry + gap

  d = ui.cycler("Show FPS", v.showFps and "On" or "Off", rx, ry, colW, h)
  if d ~= 0 then
    v.showFps = not v.showFps
    app.showFps = v.showFps
  end
  ry = ry + gap

  d = ui.cycler("Damage numbers", v.damageNumbers and "On" or "Off", rx, ry, colW, h)
  if d ~= 0 then
    v.damageNumbers = not v.damageNumbers
    Settings.applyEffects()
  end
  ry = ry + gap

  d = ui.cycler("Scoreboard key", v.scoreboardHold and "Hold" or "Toggle", rx, ry, colW, h)
  if d ~= 0 then v.scoreboardHold = not v.scoreboardHold end
  ry = ry + gap

  d = ui.cycler("Text size", Settings.TEXT_SIZES[v.textSize][1], rx, ry, colW, h)
  if d ~= 0 then
    v.textSize = math.max(1, math.min(#Settings.TEXT_SIZES, v.textSize + d))
    Settings.applyEffects()
  end
  ry = ry + gap

  if not platform.web then
    d = ui.cycler("Check for updates", v.checkUpdates and "On" or "Off", rx, ry, colW, h)
    if d ~= 0 then v.checkUpdates = not v.checkUpdates end
  end
end

local function volumeText(v)
  return v == 0 and "Off" or (v * 10 .. "%")
end

function Screen:drawAudio(x, y, w)
  local y0 = y
  local v = Settings.values
  local h, gap = 44, 52
  local colW = (w - 30) / 2
  local rows = {
    { "Master volume", "volMaster" }, { "Music volume", "volMusic" }, { "Effects volume", "volSfx" }, { "Menu volume", "volUi" },
  }
  for _, row in ipairs(rows) do
    local d = ui.cycler(row[1], volumeText(v[row[2]]), x, y, colW, h)
    if d ~= 0 then
      v[row[2]] = math.max(0, math.min(10, v[row[2]] + d))
      Settings.applyEffects()
      require("gfx.sfx").play("hit", nil, 1, 1, true)
    end
    y = y + gap
  end
  local d = ui.cycler("Mute in background", v.muteUnfocused and "On" or "Off", x, y, colW, h)
  if d ~= 0 then v.muteUnfocused = not v.muteUnfocused end
  self:drawVoice(x + colW + 30, y0, colW, h, gap)
end

local VOICE_MODES = { "off", "push", "open" }
local VOICE_NAMES = { off = "Off", push = "Push to talk", open = "Open mic" }

-- Voice chat: right-hand column of the Audio tab.
function Screen:drawVoice(x, y, w, h, gap)
  local Voice = require "online.voice"
  local v = Settings.values
  if not Voice.available() then
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.printf("Voice chat needs the desktop version.", x, y + 8, w, "left")
    return
  end
  local idx = indexOf(VOICE_MODES, v.voiceMode)
  local d = ui.cycler("Voice chat", VOICE_NAMES[v.voiceMode] or "Off", x, y, w, h)
  if d ~= 0 then v.voiceMode = VOICE_MODES[cycle(idx, #VOICE_MODES, d)] end
  y = y + gap
  d = ui.cycler("Voice volume", volumeText(v.volVoice), x, y, w, h)
  if d ~= 0 then v.volVoice = math.max(0, math.min(10, v.volVoice + d)) end
  y = y + gap
  local mics = Voice.devices()
  local current = 1
  for i, m in ipairs(mics) do if m:getName() == v.voiceDevice then current = i end end
  d = ui.cycler("Microphone", mics[current] and mics[current]:getName() or "None found", x, y, w, h)
  if d ~= 0 and #mics > 0 then v.voiceDevice = mics[cycle(current, #mics, d)]:getName() end
  y = y + gap
  if v.voiceMode == "open" then
    d = ui.cycler("Open mic level", Voice.THRESHOLD_NAMES[v.voiceThreshold] or "Normal", x, y, w, h)
    if d ~= 0 then v.voiceThreshold = cycle(v.voiceThreshold, #Voice.THRESHOLDS, d) end
  elseif v.voiceMode == "push" then
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.7)
    ui.printFit("Hold " .. Input.keyName(v.binds.online.voice) .. " to talk (or click the right stick)", app.fonts.med, x, y + 10, w, "left")
  end
  y = y + gap
  if v.voiceMode ~= "off" then
    Voice.monitorT = love.timer.getTime() -- keeps the mic open for the meter while this tab is showing
    love.graphics.setColor(1, 1, 1, 0.12)
    love.graphics.rectangle("fill", x, y + 8, w, 14, 4, 4)
    local k = math.min(1, math.sqrt(Voice.level) * 1.6)
    love.graphics.setColor(ui.GOOD)
    love.graphics.rectangle("fill", x, y + 8, w * k, 14, 4, 4)
    if v.voiceMode == "open" then
      local t = math.min(1, math.sqrt(Voice.THRESHOLDS[v.voiceThreshold] or 0.04) * 1.6)
      love.graphics.setColor(1, 1, 1)
      love.graphics.rectangle("fill", x + w * t - 1, y + 4, 2, 22)
    end
  else
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.printf("With voice off, your microphone is never used and you won't hear other players.", x, y + 4, w, "left")
  end
end

-- Browser build: the page owns the window, so only the effects options apply.
function Screen:drawVideoWeb(x, y, w)
  local h, gap = 40, 46
  local colW = (w - 30) / 2
  self:drawGraphics(x, y, colW, h, gap)
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf("You're playing in the browser.\n\nUse the Fullscreen button under the game, or your " ..
    "browser's fullscreen (F11), for a bigger view. Window size, resolution and VSync are set by the browser.",
    x + colW + 30, y + 8, colW, "left")
end

function Screen:drawVideo(x, y, w)
  if platform.web then return self:drawVideoWeb(x, y, w) end
  local v = Settings.values
  local h, gap = 40, 46
  local colW = (w - 30) / 2
  local d

  -- Display (pending until Apply). Follow outside changes such as F11 while nothing is edited.
  if not self.displayEdited then self:syncDisplay() end
  local p = self.display
  local function edited() self.displayEdited = true end

  local lx, ly = x, y
  d = ui.cycler("Window mode", Settings.WINDOW_MODE_NAMES[p.windowMode], lx, ly, colW, h)
  if d ~= 0 then
    local modes = Settings.WINDOW_MODES
    p.windowMode = modes[cycle(indexOf(modes, p.windowMode), #modes, d)]
    edited()
  end
  ly = ly + gap

  local displays = Settings.displayCount()
  local display = Settings.display(p.display)
  local ok, dname = pcall(love.window.getDisplayName, display)
  local dtext = tostring(display)
  if ok and dname and dname ~= "" then
    if #dname > 13 then dname = dname:sub(1, 12) .. ".." end
    dtext = dtext .. ": " .. dname
  end
  d = ui.cycler("Monitor", dtext, lx, ly, colW, h)
  if d ~= 0 and displays > 1 then
    p.display = cycle(display, displays, d)
    edited()
  end
  ly = ly + gap

  local list = Settings.resolutions(p.display, p.resolution)
  local current = 1
  for i, r in ipairs(list) do
    if r.key == p.resolution then current = i end
  end
  local res = list[current]
  local resText = p.windowMode == "borderless" and "Desktop" or (res[1] .. " x " .. res[2])
  d = ui.cycler("Resolution", resText, lx, ly, colW, h)
  if d ~= 0 and p.windowMode ~= "borderless" then
    p.resolution = list[cycle(current, #list, d)].key
    edited()
  end
  ly = ly + gap

  local vi = 1
  for i, m in ipairs(Settings.VSYNC_MODES) do
    if m[2] == p.vsyncMode then vi = i end
  end
  d = ui.cycler("VSync", Settings.VSYNC_MODES[vi][1], lx, ly, colW, h)
  if d ~= 0 then
    p.vsyncMode = Settings.VSYNC_MODES[cycle(vi, #Settings.VSYNC_MODES, d)][2]
    edited()
  end
  ly = ly + gap

  local fpsOpts = Settings.FPS_OPTIONS
  d = ui.cycler("Max FPS", v.maxFps == 0 and "Unlimited" or tostring(v.maxFps), lx, ly, colW, h)
  if d ~= 0 then v.maxFps = fpsOpts[cycle(indexOf(fpsOpts, v.maxFps), #fpsOpts, d)] end
  ly = ly + gap

  local changed = self:displayChanged()
  if ui.button(changed and "Apply Display Changes" or "No Display Changes", lx, ly, colW, h,
    { disabled = not changed, color = changed and ui.ACCENT or nil }) then
    self:applyDisplay()
  end

  self:drawGraphics(x + colW + 30, y, colW, h, gap)

  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.45)
  love.graphics.printf("Window mode, monitor, resolution and VSync change when you press Apply. " ..
    "Unapplied changes are discarded on Back.",
    x, y + 6 * gap + 4, colW, "center")
end

---------------------------------------------------------------- controls
function Screen:drawControls(x, y0, w, viewH)
  local schemes = Settings.BIND_SCHEMES
  self.controlsScroll = self.controlsScroll or { y = 0 }
  local rowsMax = 0
  for _, scheme in ipairs(schemes) do rowsMax = math.max(rowsMax, #scheme.actions) end
  local y = ui.beginScroll(self.controlsScroll, x - 4, y0, w + 8, viewH, 44 + rowsMax * 38 + 104)
  local gapX = 20
  local colW = (w - gapX * (#schemes - 1)) / #schemes
  local h, gap = 34, 38
  local binds = Settings.values.binds

  for c, scheme in ipairs(schemes) do
    local cx = x + (c - 1) * (colW + gapX)
    love.graphics.setFont(app.fonts.title)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.printf(scheme.name, cx, y, colW, "center")
    for r, action in ipairs(scheme.actions) do
      local ry = y + 44 + (r - 1) * gap
      local capturing = self.capture and self.capture.scheme == scheme.id and self.capture.action == action
      local opts = capturing and { color = ui.ACCENT } or nil
      if ui.button("", cx, ry, colW, h, opts) and not self.capture then
        self.capture = { scheme = scheme.id, action = action }
        ui.capturing = true
      end
      local font = app.fonts.med
      love.graphics.setFont(font)
      local ty = ry + (h - font:getHeight()) / 2
      love.graphics.setColor(1, 1, 1, 0.75)
      love.graphics.print(Settings.ACTION_NAMES[action] or action, cx + 16, ty)
      if capturing then
        love.graphics.setColor(ui.ACCENT)
        love.graphics.printf("Press a key...", cx, ty, colW - 16, "right")
      else
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(Input.keyName(binds[scheme.id][action]), cx, ty, colW - 16, "right")
      end
    end
  end

  local rows = 0
  for _, scheme in ipairs(schemes) do rows = math.max(rows, #scheme.actions) end
  local by = y + 44 + rows * gap + 4
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.45)
  love.graphics.printf("Click a binding, then press a key or mouse button (Esc cancels). A key already in use is swapped.",
    x, by, w, "center")
  if ui.button("Reset Controls", x, by + 30, 220, 40, { font = app.fonts.med }) then
    self:stopCapture()
    require("screens.confirm").ask("Reset controls?", "Every key binding goes back to its default.",
      function() Settings.resetBinds() end, { yes = "Reset", danger = true })
  end
  local v = Settings.values
  local modes = { "auto", "on", "off" }
  local names = { auto = "Auto", on = "On", off = "Off" }
  local d = ui.cycler("Touch controls", names[v.touchControls] or "Auto", x + 236, by + 30, 300, 40)
  if d ~= 0 then
    local i = 1
    for k, m in ipairs(modes) do if m == v.touchControls then i = k end end
    v.touchControls = modes[(i - 1 + d) % 3 + 1]
    Settings.applyEffects()
  end
  if ui.button("Touch layout...", x + 552, by + 30, 200, 40, { font = app.fonts.med }) then
    app.push(require("screens.touchlayout").new())
  end
  d = ui.cycler("Gamepad online", v.padOnline and "On" or "Off", x + 768, by + 30, w - 768, 40)
  if d ~= 0 then v.padOnline = not v.padOnline end
  ui.endScroll(self.controlsScroll)
end

---------------------------------------------------------------- gameplay
local function secText(s)
  if s == 0 then return "Off" end
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- The gameplay values to show: this machine's settings, or for a client the host's.
local function viewOfRules(r)
  local v = { roundsToWin = r.roundsToWin, matchMode = r.mode, teams = r.teams, teamSize = r.teamSize, friendlyFire = r.friendlyFire, pickFrom = r.pickFrom,
    picksPerRound = r.picksPerRound, startCards = r.startCards, draft = r.draft, draftExtra = r.draftExtra, draftSnake = r.draftSnake, pickTimer = r.pickTimer, allowDiscard = r.allowDiscard,
    mapVote = r.mapVote, mapVoteCount = r.mapVoteCount, cardBans = r.cardBans, hazards = r.hazards, subRounds = r.subRounds,
    suddenDeath = r.suddenDeath, barrierClose = r.barrierClose, barrierBox = r.barrierBox, barrierDamage = r.barrierDamage }
  for i, x in ipairs(Cards.RARITIES) do v["weight_" .. x.id] = r.weights[i] or 0 end
  return v
end

function Screen:hostRules()
  local session = active.get()
  if session.inLobby() and not session.isHost then return session.hostRules, true end
  return nil, false
end

local function heading(text, x, y, w)
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(ui.ACCENT)
  love.graphics.print(text, x, y)
  love.graphics.setColor(1, 1, 1, 0.12)
  love.graphics.rectangle("fill", x, y + 32, w, 2)
end

function Screen:drawGameplay(x, y, w, viewH)
  local rules, client = self:hostRules()
  if client and not rules then
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.printf("Waiting for the host's settings...", x, y + 120, w, "center")
    return
  end
  local v = client and viewOfRules(rules) or Settings.values
  local h, gap, head = 38, 44, 42
  local colW = (w - 50) / 2
  local contentH = head + (16 + ((v.draft and v.startCards > 0) and 2 or 0)) * gap
  local top = y
  if client then
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(ui.GOLD)
    love.graphics.printf("Host's settings (read-only)", x, y, w, "center")
    top, viewH = y + 28, viewH - 28
  end
  self.scroll = self.scroll or { y = 0 }
  local sy = ui.beginScroll(self.scroll, x - 8, top, w + 16 - 8, viewH, contentH + 12)
  ui.readOnly = client
  local d
  local lx, ly = x, sy
  heading("Match", lx, ly, colW)
  ly = ly + head

  local modeName = Settings.MODE_NAMES[v.matchMode] or "Elimination"
  d = ui.cycler("Mode", modeName, lx, ly, colW, h)
  if d ~= 0 then v.matchMode = Settings.MODES[cycle(indexOf(Settings.MODES, v.matchMode), #Settings.MODES, d)] end
  ly = ly + gap
  d = ui.cycler("Teams", v.teams and "Teams" or "Free-for-all", lx, ly, colW, h)
  if d ~= 0 then v.teams = not v.teams end
  ly = ly + gap
  if v.teams then
    local ts = Settings.TEAM_SIZE
    d = ui.cycler("Max team size", tostring(v.teamSize or ts.min), lx, ly, colW, h)
    if d ~= 0 then v.teamSize = ts.min + cycle((v.teamSize or ts.min) - ts.min + 1, ts.max - ts.min + 1, d) - 1 end
    ly = ly + gap
  end
  d = ui.cycler("Friendly fire", v.friendlyFire and "On" or "Off", lx, ly, colW, h)
  if d ~= 0 then v.friendlyFire = not v.friendlyFire end
  ly = ly + gap
  d = ui.cycler("Rounds to win", tostring(v.roundsToWin), lx, ly, colW, h)
  if d ~= 0 then
    local opts = Settings.ROUND_OPTIONS
    v.roundsToWin = opts[cycle(indexOf(opts, v.roundsToWin), #opts, d)]
  end
  ly = ly + gap
  local sr = Settings.SUB_ROUNDS
  d = ui.cycler("Wins per point", tostring(v.subRounds), lx, ly, colW, h)
  if d ~= 0 then v.subRounds = sr.min + cycle(v.subRounds - sr.min + 1, sr.max - sr.min + 1, d) - 1 end
  ly = ly + gap
  local pf = Settings.PICK_FROM
  d = ui.cycler("Cards to choose from", tostring(v.pickFrom), lx, ly, colW, h)
  if d ~= 0 then v.pickFrom = pf.min + cycle(v.pickFrom - pf.min + 1, pf.max - pf.min + 1, d) - 1 end
  ly = ly + gap
  local pr = Settings.PICKS_PER_ROUND
  d = ui.cycler("Picks per round", tostring(v.picksPerRound), lx, ly, colW, h)
  if d ~= 0 then v.picksPerRound = pr.min + cycle(v.picksPerRound - pr.min + 1, pr.max - pr.min + 1, d) - 1 end
  ly = ly + gap
  local sc = Settings.START_CARDS
  d = ui.cycler("Starting cards", v.startCards == 0 and "None" or tostring(v.startCards), lx, ly, colW, h)
  if d ~= 0 then v.startCards = sc.min + cycle(v.startCards - sc.min + 1, sc.max - sc.min + 1, d) - 1 end
  ly = ly + gap
  -- Draft: the starting cards come from one shared spread, picked in turn.
  local noStart = v.startCards == 0
  d = ui.cycler("Draft starting cards", v.draft and "On" or "Off", lx, ly, colW, h, { disabled = noStart })
  if d ~= 0 then v.draft = not v.draft end
  ly = ly + gap
  if v.draft and not noStart then
    local de = Settings.DRAFT_EXTRA
    d = ui.cycler("Draft spare cards", tostring(v.draftExtra or 0), lx, ly, colW, h)
    if d ~= 0 then v.draftExtra = de.min + cycle((v.draftExtra or 0) - de.min + 1, de.max - de.min + 1, d) - 1 end
    ly = ly + gap
    d = ui.cycler("Draft order", v.draftSnake and "Snake" or "Same each round", lx, ly, colW, h)
    if d ~= 0 then v.draftSnake = not v.draftSnake end
    ly = ly + gap
  end
  local timers = Settings.PICK_TIMER_OPTIONS
  d = ui.cycler("Pick timer (online)", v.pickTimer == 0 and "Off" or (v.pickTimer .. "s"), lx, ly, colW, h)
  if d ~= 0 then v.pickTimer = timers[cycle(indexOf(timers, v.pickTimer), #timers, d)] end
  ly = ly + gap
  d = ui.cycler("Allow discarding", v.allowDiscard and "On" or "Off", lx, ly, colW, h)
  if d ~= 0 then v.allowDiscard = not v.allowDiscard end
  ly = ly + gap
  d = ui.cycler("Map vote", v.mapVote and "On" or "Off", lx, ly, colW, h)
  if d ~= 0 then v.mapVote = not v.mapVote end
  ly = ly + gap
  local mv = Settings.MAP_VOTE_COUNT
  d = ui.cycler("Maps in the vote", tostring(v.mapVoteCount), lx, ly, colW, h, { disabled = not v.mapVote })
  if d ~= 0 then v.mapVoteCount = mv.min + cycle(v.mapVoteCount - mv.min + 1, mv.max - mv.min + 1, d) - 1 end
  ly = ly + gap
  d = ui.cycler("Card bans", v.cardBans and "On" or "Off", lx, ly, colW, h)
  if d ~= 0 then v.cardBans = not v.cardBans end
  ly = ly + gap
  d = ui.cycler("Map hazards", v.hazards and "On" or "Off", lx, ly, colW, h)
  if d ~= 0 then v.hazards = not v.hazards end

  local rx, ry = x + colW + 34, sy
  heading("Sudden death", rx, ry, colW)
  ry = ry + head
  local times = Settings.SUDDEN_TIMES
  d = ui.cycler("Timer", secText(v.suddenDeath), rx, ry, colW, h)
  if d ~= 0 then v.suddenDeath = times[cycle(indexOf(times, v.suddenDeath), #times, d)] end
  ry = ry + gap
  local off = v.suddenDeath == 0
  local rows = { { "Closing speed", "barrierClose", Settings.BARRIER_CLOSE_NAMES }, { "Final box size", "barrierBox", Settings.BARRIER_BOX_NAMES },
    { "Barrier damage", "barrierDamage", Settings.BARRIER_DAMAGE_NAMES } }
  for _, row in ipairs(rows) do
    d = ui.cycler(row[1], row[3][v[row[2]]] or row[3][2], rx, ry, colW, h, { disabled = off })
    if d ~= 0 then v[row[2]] = cycle(v[row[2]], #row[3], d) end
    ry = ry + gap
  end
  ry = ry + 2
  heading("Rarity chances", rx, ry, colW)
  ry = ry + head
  for _, r in ipairs(Cards.RARITIES) do
    local key = "weight_" .. r.id
    d = ui.cycler(r.name, v[key] .. "%", rx, ry, colW, h, { noEnter = true })
    love.graphics.setColor(r.color)
    love.graphics.rectangle("fill", rx + 6, ry + 10, 4, h - 20, 2, 2)
    if d ~= 0 then Settings.setWeight(r.id, v[key] + d) end
    ry = ry + gap
  end
  ry = ry + 2
  heading("Content", rx, ry, colW)
  ry = ry + head
  local hw = (colW - 10) / 2
  if ui.button("Card Library", rx, ry, hw, h, { font = app.fonts.med, viewOnly = true }) then
    app.push(require("screens.library").new(client and rules or nil))
  end
  local enabledMaps = Settings.enabledMapCount()
  if ui.button(client and "Map Pool" or ("Map Pool (" .. enabledMaps .. "/" .. #Map.list .. ")"), rx + hw + 10, ry, hw, h, { font = app.fonts.med, viewOnly = true }) then
    app.push(require("screens.maps").new(client and rules or nil))
  end
  ry = ry + gap
  local session = active.get()
  if ui.button("Editor", rx, ry, hw, h, { font = app.fonts.med, disabled = session.inLobby() }) then
    Settings.save()
    app.switch(require("screens.editor_hub").new())
    ui.readOnly = false
    ui.endScroll(self.scroll)
    return
  end
  if ui.button("Reset All", rx + hw + 10, ry, hw, h, { font = app.fonts.med }) then
    require("screens.confirm").ask("Reset gameplay settings?", "Every setting on this page goes back to its default.",
      function() Settings.resetGameplay() end, { yes = "Reset", danger = true })
  end
  ui.readOnly = false
  ui.endScroll(self.scroll)
end

---------------------------------------------------------------- draw
function Screen:draw()
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local pw, ph = 1060, 660
  local px, py = (app.W - pw) / 2, (app.H - ph) / 2
  ui.panel(px, py, pw, ph)
  love.graphics.setFont(app.fonts.big)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("SETTINGS", px, py + 12, pw, "center")

  -- Tabs
  local tw, th = 200, 44
  local tx = px + (pw - (#TABS * tw + (#TABS - 1) * 12)) / 2
  for i, name in ipairs(TABS) do
    local active = i == self.tab
    if ui.button(name, tx + (i - 1) * (tw + 12), py + 74, tw, th,
      { color = active and ui.ACCENT or nil, font = app.fonts.button }) and not active then
      self:setTab(i)
    end
    if active then
      love.graphics.setColor(ui.ACCENT)
      love.graphics.rectangle("fill", tx + (i - 1) * (tw + 12) + 30, py + 74 + th + 4, tw - 60, 3, 1, 1)
    end
  end
  local cx, cy, cw = px + 40, py + 134, pw - 80
  local viewH = ph - 134 - 76
  if self.tab == 1 then
    self:drawVideo(cx, cy, cw)
  elseif self.tab == 2 then
    self:drawAudio(cx, cy, cw)
  elseif self.tab == 3 then
    self:drawControls(cx, cy, cw, viewH)
  else
    self:drawGameplay(cx, cy, cw, viewH)
  end

  if ui.button("Back", px + pw / 2 - 110, py + ph - 64, 220, 46) then self:close() end
end

return Screen
