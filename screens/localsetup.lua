-- Local Play setup, laid out like the online lobby: up to 4 players, each on a keyboard scheme, a
-- gamepad, touch or a bot. Your colour is your team when teams are on.
local app = require "core.app"
local ui = require "core.ui"
local Settings = require "core.settings"
local World = require "game.world"
local Input = require "core.input"
local Bot = require "game.bot"
local Cosmetics = require "core.cosmetics"

local Setup = {}
Setup.__index = Setup

-- What a seat can be played with (not counting bots, which have their own buttons).
local function devices()
  local list = { "p1", "p2" }
  if require("core.touch").enabled then list[#list + 1] = "touch" end
  for i = 1, #Input.pads() do list[#list + 1] = "pad" .. i end
  return list
end

local function kinds()
  local list = devices()
  for i = 1, 3 do list[#list + 1] = "bot" .. i end
  return list
end

local function kindName(k)
  if k == "p1" then return "Keyboard (P1 keys)" end
  if k == "p2" then return "Keyboard (P2 keys)" end
  if k == "touch" then return "Touch screen" end
  local pad = k:match("^pad(%d)$")
  if pad then
    local j = Input.pads()[tonumber(pad)]
    return "Gamepad " .. pad .. (j and "" or " (unplugged)")
  end
  local bot = k:match("^bot(%d)$")
  if bot then return "Bot - " .. Bot.NAMES[tonumber(bot)] end
  return k
end

local function seatName(i, s)
  local bot = s.kind:match("^bot(%d)$")
  if bot then return "Bot (" .. Bot.NAMES[tonumber(bot)] .. ")" end
  return "Player " .. i
end

function Setup.parse(text)
  local slots = {}
  for part in (text or ""):gmatch("[^;]+") do
    local kind, color = part:match("^([%w]+):(%d+):%d+$")
    if kind then slots[#slots + 1] = { kind = kind, color = tonumber(color) } end
  end
  for i = #slots + 1, 4 do slots[i] = { kind = i <= 2 and ("p" .. i) or "off", color = i } end
  return slots
end

function Setup.encode(slots)
  local parts = {}
  for _, s in ipairs(slots) do parts[#parts + 1] = s.kind .. ":" .. s.color .. ":" .. s.color end
  return table.concat(parts, ";")
end

function Setup.new()
  local slots = Setup.parse(Settings.values.localSetup)
  -- On a touch device, start with you (touch) against a bot.
  if require("core.touch").enabled then
    local hasTouch = false
    for _, s in ipairs(slots) do if s.kind == "touch" then hasTouch = true end end
    if not hasTouch then
      slots[1].kind = "touch"
      if slots[2].kind == "p2" or slots[2].kind == "off" then slots[2].kind = "bot2" end
    end
  end
  return setmetatable({ slots = slots, selected = 1, figs = {} }, Setup)
end

function Setup:saveSlots()
  Settings.values.localSetup = Setup.encode(self.slots)
  Settings.save()
end

function Setup:back()
  self:saveSlots()
  app.switch(require("screens.localmenu").new())
end

function Setup:keypressed(key)
  if key == "escape" then self:back() end
end

local function colorLimit()
  local v = Settings.values
  return v.teams and (v.teamSize or 2) or 1
end

-- How many other seats use each colour, and the colours that are full.
function Setup:colorUse(except)
  local count, full, limit = {}, {}, colorLimit()
  for i, o in ipairs(self.slots) do
    if i ~= except and o.kind ~= "off" then
      count[o.color] = (count[o.color] or 0) + 1
      if count[o.color] >= limit then full[o.color] = true end
    end
  end
  return count, full
end

-- Without teams nobody shares a colour: a saved setup from a teams match gets sorted out here.
function Setup:fixColors()
  if Settings.values.teams then return end
  local used = {}
  for _, s in ipairs(self.slots) do
    if s.kind ~= "off" then
      if used[s.color] then
        for c = 1, #World.PALETTE do
          if not used[c] then s.color = c break end
        end
      end
      used[s.color] = true
    end
  end
end

-- Problems that stop the match from starting.
function Setup:problem()
  local active, used, count, sides, limit = {}, {}, {}, 0, colorLimit()
  for _, s in ipairs(self.slots) do
    if s.kind ~= "off" then
      active[#active + 1] = s
      if not s.kind:match("^bot") then
        if used[s.kind] then return "Two players can't share " .. kindName(s.kind) end
        used[s.kind] = true
      end
      local pad = s.kind:match("^pad(%d)$")
      if pad and not Input.pads()[tonumber(pad)] then return "Gamepad " .. pad .. " isn't plugged in" end
      if not count[s.color] then sides = sides + 1 end
      count[s.color] = (count[s.color] or 0) + 1
      if Settings.values.teams and count[s.color] > limit then return World.teamName(s.color) .. " has too many players" end
    end
  end
  if #active < 2 then return "Add at least 2 players" end
  if Settings.values.teams and sides < 2 then return "Everyone is on one team" end
  return nil
end

function Setup:start()
  if self:problem() then return end
  local v = Settings.values
  self:saveSlots()
  local setup = {}
  for _, s in ipairs(self.slots) do
    if s.kind ~= "off" then setup[#setup + 1] = { kind = s.kind, color = s.color, team = s.color } end
  end
  app.instant()
  app.switch(require("screens.match").newLocal(v.roundsToWin, { setup = setup, teams = v.teams, loading = true }))
end

-- Seat the next player with this kind, in a free colour.
function Setup:add(kind)
  for i, s in ipairs(self.slots) do
    if s.kind == "off" then
      local _, full = self:colorUse(i)
      for k = 1, #World.PALETTE do
        local c = (i - 1 + k - 1) % #World.PALETTE + 1
        if not full[c] then s.color = c break end
      end
      s.kind = kind
      self.selected = i
      return
    end
  end
end

function Setup:inUse(kind)
  for _, s in ipairs(self.slots) do if s.kind == kind then return true end end
  return false
end

function Setup:drawRow(i, s, lx, ry, lw)
  local on = s.kind ~= "off"
  local mx, my = app.mouse()
  love.graphics.setColor(ui.WIDGET)
  love.graphics.rectangle("fill", lx + 16, ry, lw - 32, 50, 10, 10)
  if not on then
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.print("Empty seat", lx + 78, ry + 14)
    return
  end
  local c = World.PALETTE[s.color] or World.COLORS[i]
  if i == self.selected then
    love.graphics.setColor(c)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", lx + 16, ry, lw - 32, 50, 10, 10)
  end
  if ui.click and mx >= lx + 16 and mx <= lx + 330 and my >= ry and my <= ry + 50 then
    self.selected = i
    ui.click = nil
  end
  local fig = self.figs[i]
  if not fig then
    fig = { r = 12, slot = i, facing = 1 }
    self.figs[i] = fig
  end
  local hat, eyes, mouth, detail
  if i == 1 and not s.kind:match("^bot") then hat, eyes, mouth, detail = Cosmetics.mine() end
  fig.x, fig.y, fig.color, fig.hat, fig.eyes, fig.mouth, fig.detail = lx + 46, ry + 18, c, hat, eyes, mouth, detail
  fig.aimX = math.cos(love.timer.getTime() * 0.7 + i) * 0.9
  fig.aimY = math.sin(love.timer.getTime() * 0.5 + i) * 0.4
  require("game.body").drawFigure(fig, love.timer.getDelta())
  love.graphics.setColor(1, 1, 1)
  ui.printFit(seatName(i, s), app.fonts.med, lx + 78, ry + 4, 170, "left")
  love.graphics.setColor(c)
  local tag = Settings.values.teams and World.teamName(s.color) or World.PALETTE_NAMES[s.color]
  ui.printFit(tag, app.fonts.tiny, lx + 78, ry + 29, 170, "left")
  if ui.button(kindName(s.kind), lx + 262, ry + 8, 218, 34, { font = app.fonts.small }) then
    local list, idx = kinds(), 1
    for k, kk in ipairs(list) do if kk == s.kind then idx = k end end
    s.kind = list[idx % #list + 1]
    self.selected = i
  end
  if ui.button("x", lx + lw - 58, ry + 10, 34, 30, { font = app.fonts.small, back = true }) then
    s.kind = "off"
    if self.selected == i then
      for k, o in ipairs(self.slots) do if o.kind ~= "off" then self.selected = k break end end
    end
  end
end

function Setup:drawColors(lx, y)
  local s = self.slots[self.selected]
  if not s or s.kind == "off" then return end
  local _, full = self:colorUse(self.selected)
  local mx, my = app.mouse()
  for k, col in ipairs(World.PALETTE) do
    local x = lx + 4 + (k - 1) * 46
    local over = mx >= x and mx <= x + 38 and my >= y and my <= y + 32
    love.graphics.setColor(col[1], col[2], col[3], full[k] and 0.2 or 1)
    love.graphics.rectangle("fill", x, y, 38, 32, 6, 6)
    if k == s.color or (over and not full[k]) then
      love.graphics.setColor(1, 1, 1)
      love.graphics.setLineWidth(3)
      love.graphics.rectangle("line", x - 2, y - 2, 42, 36, 7, 7)
    end
    if ui.click and over and not full[k] then
      s.color = k
      ui.click = nil
    end
  end
end

function Setup:drawAdd(by)
  local seats = 0
  for _, s in ipairs(self.slots) do if s.kind ~= "off" then seats = seats + 1 end end
  local full = seats >= 4
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.print("Add a bot", 54, by + 12)
  for k, name in ipairs(Bot.NAMES) do
    if ui.button("+ " .. name, 136 + (k - 1) * 162, by, 156, 42, { font = app.fonts.small, disabled = full }) then
      self:add("bot" .. k)
    end
  end
  by = by + 50
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.print("Add a player", 54, by + 12)
  local x = 136
  for _, kind in ipairs(devices()) do
    if x < 620 - 112 then
      local label = kind == "p1" and "+ Keys 1" or kind == "p2" and "+ Keys 2" or kind == "touch" and "+ Touch" or ("+ Pad " .. kind:sub(4))
      if ui.button(label, x, by, 112, 42, { font = app.fonts.small, disabled = full or self:inUse(kind) }) then
        self:add(kind)
      end
      x = x + 118
    end
  end
end

function Setup:drawRules(rx, ry, rw, rh)
  local v = Settings.values
  ui.panel(rx, ry, rw, rh)
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Match", rx + 20, ry + 10)
  local rows = {
    { "Mode", Settings.MODE_NAMES[v.matchMode] or "Elimination" },
    { "Teams", v.teams and ("Teams of up to " .. (v.teamSize or 2)) or "Free-for-all" },
    { "Friendly fire", v.friendlyFire and "On" or "Off" },
    { "Rounds to win", tostring(v.roundsToWin) },
    { "Wins per point", tostring(v.subRounds) },
    { "Cards to choose from", tostring(v.pickFrom) },
    { "Picks per round", tostring(v.picksPerRound) },
    { "Starting cards", v.startCards == 0 and "None" or tostring(v.startCards) },
  }
  local y = ry + 58
  for _, row in ipairs(rows) do
    love.graphics.setColor(1, 0.8, 0.35)
    ui.printFit(row[1], app.fonts.med, rx + 24, y, rw / 2 - 30, "left")
    love.graphics.setColor(1, 1, 1, 0.85)
    ui.printFit(row[2], app.fonts.med, rx + rw / 2, y, rw / 2 - 24, "right")
    y = y + 40
  end
  love.graphics.setColor(1, 1, 1, 0.5)
  local hint = v.teams and "Players with the same colour are on the same team." or "Choose a seat, then click a colour."
  ui.printFit(hint, app.fonts.small, rx + 20, ry + rh - 36, rw - 40, "center")
end

function Setup:draw()
  self:fixColors()
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  app.centered("LOCAL PLAY", app.fonts.big, 18)

  local lx, ly, lw, lh = 50, 72, 570, 322
  ui.panel(lx, ly, lw, lh)
  local seats = 0
  for _, s in ipairs(self.slots) do if s.kind ~= "off" then seats = seats + 1 end end
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Players  " .. seats .. " / 4", lx + 20, ly + 10)
  for i, s in ipairs(self.slots) do self:drawRow(i, s, lx, ly + 50 + (i - 1) * 56, lw) end
  self:drawColors(lx, ly + lh + 12)
  self:drawAdd(456)
  self:drawRules(660, 72, 570, 476)

  local problem = self:problem()
  if problem then app.centered(problem, app.fonts.med, 572, ui.BAD) end
  local y = 620
  if ui.button("Start Match", 50, y, 370, 54, { disabled = problem ~= nil, color = ui.GOOD }) then self:start() end
  if ui.button("Settings", 440, y, 390, 54) then app.push(require("screens.settings").new(4)) end
  if ui.button("Back", 850, y, 380, 54, { back = true }) then self:back() end
end

return Setup
