-- Settings, shown as an overlay on top of whatever screen opened it.
-- Tabs: Video, Controls (key rebinding) and Gameplay (card rules; the host's are used online).
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

function Screen.new()
  local s = setmetatable({ tab = 1, capture = nil }, Screen)
  s:syncDisplay()
  return s
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
  if session.isHost and session.inLobby() then session.publishRules(Settings.values) end
  app.pop()
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
end

local function volumeText(v)
  return v == 0 and "Off" or (v * 10 .. "%")
end

function Screen:drawAudio(x, y, w)
  local v = Settings.values
  local h, gap = 44, 52
  local colW = (w - 30) / 2
  local rows = {
    { "Master volume", "volMaster" }, { "Effects volume", "volSfx" }, { "Menu volume", "volUi" },
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
end

-- Browser build: the page owns the window, so only the effects options apply.
function Screen:drawVideoWeb(x, y, w)
  local h, gap = 44, 52
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
  local h, gap = 44, 52
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
  love.graphics.printf("Window mode, monitor, resolution and VSync change when you press Apply " ..
    "(unapplied changes are discarded on Back).\nF11 or Alt+Enter toggles fullscreen at any time.",
    x, y + 6 * gap + 12, w, "center")
end

---------------------------------------------------------------- controls
function Screen:drawControls(x, y, w)
  local schemes = Settings.BIND_SCHEMES
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
      local ry = y + 36 + (r - 1) * gap
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
  local by = y + 36 + rows * gap + 4
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.45)
  love.graphics.printf(
    "Click a binding, then press a key or mouse button (Esc cancels). A key already in use is swapped.\n" ..
    "Local players share the keyboard. Online play always aims with the mouse.",
    x, by, w, "center")
  if ui.button("Reset Controls", x, by + 44, 220, 40, { font = app.fonts.med }) then
    self:stopCapture()
    Settings.resetBinds()
  end
  local v = Settings.values
  local modes = { "auto", "on", "off" }
  local names = { auto = "Auto", on = "On", off = "Off" }
  local d = ui.cycler("Touch controls", names[v.touchControls] or "Auto", x + 236, by + 44, 300, 40)
  if d ~= 0 then
    local i = 1
    for k, m in ipairs(modes) do if m == v.touchControls then i = k end end
    v.touchControls = modes[(i - 1 + d) % 3 + 1]
    Settings.applyEffects()
  end
  if ui.button("Touch layout...", x + 552, by + 44, 200, 40, { font = app.fonts.med }) then
    app.push(require("screens.touchlayout").new())
  end
  d = ui.cycler("Gamepad online", v.padOnline and "On" or "Off", x + 768, by + 44, w - 768, 40)
  if d ~= 0 then v.padOnline = not v.padOnline end
end

---------------------------------------------------------------- gameplay
local function weightStep(wt, d)
  if d > 0 then
    wt = wt < 10 and wt + 1 or wt + 5
  else
    wt = wt <= 10 and wt - 1 or wt - 5
  end
  return math.max(0, math.min(100, wt))
end

function Screen:drawGameplay(x, y, w)
  local v = Settings.values
  local h, gap = 38, 44
  local colW = (w - 30) / 2
  local d

  local lx, ly = x, y
  d = ui.cycler("Rounds to win (local)", tostring(v.roundsToWin), lx, ly, colW, h)
  if d ~= 0 then
    local opts = Settings.ROUND_OPTIONS
    v.roundsToWin = opts[cycle(indexOf(opts, v.roundsToWin), #opts, d)]
  end
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

  local timers = Settings.PICK_TIMER_OPTIONS
  d = ui.cycler("Pick timer (online)", v.pickTimer == 0 and "Off" or (v.pickTimer .. "s"), lx, ly, colW, h)
  if d ~= 0 then v.pickTimer = timers[cycle(indexOf(timers, v.pickTimer), #timers, d)] end
  ly = ly + gap

  d = ui.cycler("Allow discarding", v.allowDiscard and "On" or "Off", lx, ly, colW, h)
  if d ~= 0 then v.allowDiscard = not v.allowDiscard end
  ly = ly + gap

  local enabled = 0
  for _, c in ipairs(Cards.list) do
    if Settings.cardEnabled(c) then enabled = enabled + 1 end
  end
  if ui.button("Card Pool...  (" .. enabled .. " / " .. #Cards.list .. " enabled)", lx, ly, colW, h) then
    app.push(require("screens.cards").new())
  end
  ly = ly + gap

  if ui.button("Map Pool...  (" .. Settings.enabledMapCount() .. " / " .. #Map.list .. " enabled)", lx, ly, colW, h) then
    app.push(require("screens.maps").new())
  end
  ly = ly + gap

  if ui.button("Synergies...", lx, ly, colW / 2 - 4, h) then app.push(require("screens.synergies").new()) end
  if ui.button("Reset", lx + colW / 2 + 4, ly, colW / 2 - 4, h) then Settings.resetGameplay() end

  -- Rarity chances, then arena rules
  local rx, ry = x + colW + 30, y
  local total = 0
  for _, r in ipairs(Cards.RARITIES) do total = total + v["weight_" .. r.id] end
  for _, r in ipairs(Cards.RARITIES) do
    local key = "weight_" .. r.id
    local wt = v[key]
    local pct = total > 0 and wt / total * 100 or 0
    local text = string.format(pct < 10 and pct > 0 and "%d  (%.1f%%)" or "%d  (%d%%)", wt,
      pct < 10 and pct > 0 and pct or math.floor(pct + 0.5))
    d = ui.cycler(r.name .. " chance", text, rx, ry, colW, h)
    love.graphics.setColor(r.color)
    love.graphics.rectangle("fill", rx + 6, ry + 10, 4, h - 20, 2, 2)
    if d ~= 0 then v[key] = weightStep(wt, d) end
    ry = ry + gap
  end
  d = ui.cycler("Map hazards", v.hazards and "On" or "Off", rx, ry, colW, h)
  if d ~= 0 then v.hazards = not v.hazards end
  ry = ry + gap
  d = ui.cycler("Sudden-death barrier", v.barrier and "On" or "Off", rx, ry, colW, h)
  if d ~= 0 then v.barrier = not v.barrier end
  ry = ry + gap

  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.45)
  love.graphics.printf(
    "Online matches use the host's gameplay settings. Changes apply from the next match.\n" ..
    "A rarity's chance is its weight out of the total. Rarities with no enabled cards are skipped.",
    x, y + 9 * gap + 8, w, "center")
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
  love.graphics.printf("SETTINGS", px, py + 18, pw, "center")

  -- Tabs
  local tw, th = 200, 44
  local tx = px + (pw - (#TABS * tw + (#TABS - 1) * 12)) / 2
  for i, name in ipairs(TABS) do
    local active = i == self.tab
    if ui.button(name, tx + (i - 1) * (tw + 12), py + 70, tw, th,
      { color = active and ui.ACCENT or nil, font = app.fonts.button }) and not active then
      self:setTab(i)
    end
    if active then
      love.graphics.setColor(ui.ACCENT)
      love.graphics.rectangle("fill", tx + (i - 1) * (tw + 12) + 30, py + 70 + th + 4, tw - 60, 3, 1, 1)
    end
  end
  love.graphics.setFont(app.fonts.tiny)
  love.graphics.setColor(1, 1, 1, 0.35)
  love.graphics.print("Q / E", tx + #TABS * (tw + 12), py + 84)

  local cx, cy, cw = px + 40, py + 140, pw - 80
  if self.tab == 1 then
    self:drawVideo(cx, cy, cw)
  elseif self.tab == 2 then
    self:drawAudio(cx, cy, cw)
  elseif self.tab == 3 then
    self:drawControls(cx, cy, cw)
  else
    self:drawGameplay(cx, cy, cw)
  end

  if ui.button("Back", px + pw / 2 - 110, py + ph - 64, 220, 46) then self:close() end
end

return Screen
