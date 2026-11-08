-- Local Play setup: 2-4 players, each on a keyboard scheme, a gamepad or a bot; colours; teams.
local app = require "core.app"
local ui = require "core.ui"
local Settings = require "core.settings"
local World = require "game.world"
local Input = require "core.input"
local Bot = require "game.bot"

local Setup = {}
Setup.__index = Setup

local function kinds()
  local list = { "off", "p1", "p2" }
  if require("core.touch").enabled then list[#list + 1] = "touch" end
  for i = 1, #Input.pads() do list[#list + 1] = "pad" .. i end
  for i = 1, 3 do list[#list + 1] = "bot" .. i end
  return list
end

local function kindName(k)
  if k == "off" then return "Off" end
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

function Setup.parse(text)
  local slots = {}
  for part in (text or ""):gmatch("[^;]+") do
    local kind, color, team = part:match("^([%w]+):(%d+):(%d+)$")
    if kind then slots[#slots + 1] = { kind = kind, color = tonumber(color), team = tonumber(team) } end
  end
  for i = #slots + 1, 4 do slots[i] = { kind = i <= 2 and ("p" .. i) or "off", color = i, team = (i - 1) % 2 + 1 } end
  return slots
end

function Setup.encode(slots)
  local parts = {}
  for _, s in ipairs(slots) do parts[#parts + 1] = s.kind .. ":" .. s.color .. ":" .. s.team end
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
  return setmetatable({ slots = slots }, Setup)
end

function Setup:keypressed(key)
  if key == "escape" then app.switch(require("screens.localmenu").new()) end
end

-- Problems that stop the match from starting.
function Setup:problem()
  local active, used, teams = {}, {}, { 0, 0 }
  for _, s in ipairs(self.slots) do
    if s.kind ~= "off" then
      active[#active + 1] = s
      if not s.kind:match("^bot") then
        if used[s.kind] then return "Two players can't share " .. kindName(s.kind) end
        used[s.kind] = true
      end
      teams[s.team] = teams[s.team] + 1
      local pad = s.kind:match("^pad(%d)$")
      if pad and not Input.pads()[tonumber(pad)] then return "Gamepad " .. pad .. " isn't plugged in" end
    end
  end
  if #active < 2 then return "Add at least 2 players" end
  if Settings.values.teams and (teams[1] == 0 or teams[2] == 0) then return "Both teams need a player" end
  return nil
end

function Setup:start()
  if self:problem() then return end
  local v = Settings.values
  v.localSetup = Setup.encode(self.slots)
  Settings.save()
  local setup = {}
  for _, s in ipairs(self.slots) do
    if s.kind ~= "off" then setup[#setup + 1] = { kind = s.kind, color = s.color, team = s.team } end
  end
  app.switch(require("screens.match").newLocal(v.roundsToWin, { setup = setup, teams = v.teams }))
end

-- Next colour not used by another active slot.
function Setup:nextColor(i, d)
  local s = self.slots[i]
  local taken = {}
  for k, o in ipairs(self.slots) do if k ~= i and o.kind ~= "off" then taken[o.color] = true end end
  local c = s.color
  for _ = 1, #World.PALETTE do
    c = (c - 1 + d) % #World.PALETTE + 1
    if not taken[c] then return c end
  end
  return s.color
end

function Setup:draw()
  local v = Settings.values
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  app.centered("LOCAL PLAY", app.fonts.big, 30)

  local x = 160
  local y = 170
  local d
  local mode = Settings.MODE_NAMES[v.matchMode] or "Elimination"
  app.centered(mode .. (v.teams and ", Teams" or ", Free-for-all") .. ", first to " .. v.roundsToWin, app.fonts.title, 104, { 1, 1, 1, 0.8 })

  local list = kinds()
  for i, s in ipairs(self.slots) do
    local on = s.kind ~= "off"
    local color = v.teams and World.PALETTE[World.TEAM_COLORS[s.team][1]] or World.PALETTE[s.color]
    love.graphics.setColor(color[1], color[2], color[3], on and 1 or 0.25)
    love.graphics.circle("fill", x - 40, y + 22, 18)
    love.graphics.setFont(app.fonts.title)
    love.graphics.setColor(1, 1, 1, on and 0.9 or 0.4)
    love.graphics.print(tostring(i), x - 110, y + 8)
    d = ui.cycler("Player " .. i, kindName(s.kind), x, y, 520, 44)
    if d ~= 0 then
      local idx = 1
      for k, kk in ipairs(list) do if kk == s.kind then idx = k end end
      s.kind = list[(idx - 1 + d) % #list + 1]
      if s.kind ~= "off" then s.color = self:nextColor(i, 0) == s.color and s.color or self:nextColor(i, 1) end
    end
    if on then
      if v.teams then
        d = ui.cycler("Team", World.TEAM_NAMES[s.team], x + 540, y, 420, 44)
        if d ~= 0 then s.team = 3 - s.team end
      else
        d = ui.cycler("Colour", World.PALETTE_NAMES[s.color], x + 540, y, 420, 44)
        if d ~= 0 then s.color = self:nextColor(i, d) end
      end
    end
    y = y + 58
  end

  local problem = self:problem()
  if problem then app.centered(problem, app.fonts.med, 568, { 1, 0.55, 0.45 }) end
  if ui.button("Start", app.W / 2 - 470, 630, 300, 54, { disabled = problem ~= nil, color = ui.GOOD }) then self:start() end
  if ui.button("Settings", app.W / 2 - 150, 630, 300, 54) then app.push(require("screens.settings").new(4)) end
  if ui.button("Back", app.W / 2 + 170, 630, 300, 54, { back = true }) then
    Settings.values.localSetup = Setup.encode(self.slots)
    Settings.save()
    app.switch(require("screens.localmenu").new())
  end
end

return Setup
