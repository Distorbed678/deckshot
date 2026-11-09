-- The Edit Object popup: every setting of the selected objects. Changes apply to all selected
-- objects of the same type. Rows are shown or hidden by what the object currently is.
local app = require "core.app"
local ui = require "core.ui"
local Map = require "game.map"
local Objects = require "game.objects"

local Popup = {}
Popup.__index = Popup
Popup.noPadHints = true

local YESNO = { false, true }
local DIRS4 = { "up", "down", "left", "right" }
local function when(key) return function(o) return o[key] end end

local WH = { { "w", "Width", 12, 4, Map.W + 200 }, { "h", "Height", 12, 4, Map.H } }
local CYCLE = { { "off", "Off time", 0.1, 0, 10 }, { "warn", "Warn", 0.1, 0, 3 }, { "on", "On time", 0.1, 0, 10 },
  { "phase", "Offset", 0.1, 0, 10 } }

-- The Physics toggle and what can hold an object up.
local HOLD = {
  { "physics", "Physics", options = YESNO },
  { "anchored", "Anchored", options = YESNO },
  { "anchorType", "Anchor type", options = { "fixed", "hinge" }, show = when("anchored") },
  { "hinge", "Hinge point", options = { "center", "top", "bottom", "left", "right" },
    show = function(o) return o.anchored and o.anchorType == "hinge" and o.w end },
  { "anchorHp", "Anchor HP (0 = forever)", 5, 0, 500, show = function(o) return o.anchored or o.parent end },
  { "attach", "Attached with", options = { "rigid", "hinge" }, show = when("parent") },
}

local function list(...)
  local out = {}
  for _, t in ipairs({ ... }) do
    for _, r in ipairs(t) do out[#out + 1] = r end
  end
  return out
end

local function onConveyor(o) return o.conveyor end

local ROWS = {
  block = list({
    { "material", "Material", options = Objects.MATERIAL_LIST },
  }, WH, {
    { "hp", "HP (0 = unbreakable)", 10, 0, 2000 },
    { "onBreak", "On break", options = { "none", "explode", "gas", "pickup" }, show = function(o) return (o.hp or 0) > 0 end },
    { "radius", "Blast radius", 10, 30, 400, show = function(o) return o.onBreak == "explode" or o.onBreak == "gas" end },
    { "damage", "Blast damage", 5, 0, 300, show = function(o) return o.onBreak == "explode" end },
    { "drop", "Drop chance", 0.01, 0, 1, show = function(o) return o.onBreak == "pickup" end },
    { "oneway", "One-way", options = YESNO },
    { "crumble", "Crumbles", options = YESNO },
    { "delay", "Crumble delay", 0.1, 0.1, 5, show = when("crumble") },
    { "back", "Returns after", 0.5, 0.5, 20, show = when("crumble") },
    { "conveyor", "Conveyor", options = YESNO },
    { "speed", "Belt speed", 20, -600, 600, show = onConveyor },
  }, HOLD),
  saw = list({ { "r", "Radius", 2, 10, 90 }, { "damage", "Damage", 5, 0, 200 } }, HOLD),
  spikes = list(WH, { { "dir", "Points", options = DIRS4 }, { "damage", "Damage", 5, 0, 200 },
    { "on", "Out time", 0.1, 0, 10 }, { "off", "In time", 0.1, 0, 10 }, { "warn", "Warn", 0.1, 0, 3 },
    { "phase", "Offset", 0.1, 0, 10 } }, HOLD),
  laser = list({ { "dir", "Points", options = DIRS4 }, { "damage", "Damage", 5, 0, 200 } }, CYCLE, HOLD),
  crusher = list(WH, { { "travel", "Drop distance", 12, 12, 900 }, { "wait", "Wait", 0.1, 0.2, 10 },
    { "phase", "Offset", 0.1, 0, 10 }, { "damage", "Damage", 5, 0, 200 } }),
  flame = list({ { "dir", "Points", options = DIRS4 }, { "length", "Length", 10, 40, 800 }, { "damage", "Damage", 2, 0, 100 } }, CYCLE, HOLD),
  liquid = list(WH, { { "damage", "Damage", 5, 0, 200 }, { "buoyant", "Buoyancy", options = YESNO },
    { "density", "Density", 0.1, 0.1, 5, show = when("buoyant") },
    { "poison", "Poison", options = YESNO }, { "burn", "Burn", options = YESNO }, { "frost", "Frost", options = YESNO },
    { "bounce", "Bullets bounce", options = YESNO } }),
  turret = list({ { "hp", "HP", 10, 10, 500 }, { "rate", "Fire every", 0.1, 0.3, 10 }, { "damage", "Damage", 5, 0, 200 },
    { "phase", "Offset", 0.1, 0, 10 } }, HOLD),
  arm = { { "length", "Length", 10, 30, 800 }, { "count", "Sides", 1, 1, 2 }, { "spin", "Spin", 0.2, -8, 8 },
    { "force", "Force", 0.25, 0.25, 20 }, { "phase", "Start angle", 0.2, 0, 6.2 } },
  rail = { { "speed", "Speed", 10, 0, 800 }, { "force", "Force", 0.25, 0.25, 20 }, { "loop", "Loop", options = YESNO } },
  pad = { { "w", "Width", 12, 24, 300 }, { "power", "Power", 50, 400, 3000 } },
  fan = list(WH, { { "dir", "Blows", options = DIRS4 }, { "force", "Force", 200, 200, 8000 } }),
  rope = { { "segHp", "Segment HP", 5, 5, 500 }, { "slack", "Slack", 0.05, 1, 2 }, { "level", "Keep held thing level", options = YESNO },
    { "pin2", "Far end pinned", options = YESNO } },
  weight = list({ { "r", "Size", 2, 10, 60 }, { "damage", "Damage", 5, 0, 300 } }, HOLD),
}
Popup.ROWS = ROWS
local COLORED = { block = true, liquid = true }

local SWATCHES = { "#3A8BE0", "#59D934", "#E0413A", "#F2A922", "#9A5BE0", "#2AD1C9", "#F2F2F2", "#333844",
  "#8A5A2B", "#E06AB0", "#B0E03A", "#FF7A1A" }

local function fmtVal(v)
  if type(v) == "boolean" then return v and "Yes" or "No" end
  if type(v) == "number" then
    if v == math.floor(v) then return tostring(v) end
    return (string.format("%.2f", v):gsub("0$", ""))
  end
  if v == nil then return "-" end
  return tostring(v)
end

-- editor: the map editor; items: selected objects (same type as the first).
function Popup.open(editor, items)
  app.push(setmetatable({ editor = editor, items = items, scroll = { y = 0 } }, Popup))
end

function Popup:keypressed(key)
  if key == "escape" or key == "e" or key == "return" then app.pop() end
end

function Popup:mousepressed(x, y, button)
  if button == 1 and (x < 300 or x > 980 or y < 34 or y > 686) then app.pop() end
end

function Popup:wheelmoved(_, dy)
  ui.wheel(self.scroll, dy)
end

function Popup:apply(key, value)
  local e = self.editor
  e:push()
  for _, o in ipairs(self.items) do
    if value == false and (key == "oneway" or key == "crumble" or key == "conveyor" or key == "anchored") then
      o[key] = nil
    else
      o[key] = value
    end
    if key == "material" and (o.hp or 0) > 0 then o.hp = Objects.MATERIALS[value].hp end
    if key == "anchored" and value == true and not o.anchorType then o.anchorType = "fixed" end
    if key == "conveyor" and value == true and not o.speed then o.speed = 160 end
    if key == "onBreak" and value == "pickup" and not o.drop then o.drop = 0.08 end
    if key == "onBreak" and value == "explode" and not o.radius then o.radius, o.damage = 110, 55 end
    if key == "onBreak" and value == "gas" and not o.radius then o.radius = 110 end
  end
  e:touch()
end

-- Colour of the selection: pick a swatch, tune R / G / B, or share a channel.
function Popup:drawColor(x, y, w, o)
  local e = self.editor
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.print("Colour", x, y)
  y = y + 22
  local size = 30
  if ui.button("", x, y, size, size, { font = app.fonts.tiny }) then self:apply("color", nil) end
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.line(x + 8, y + 22, x + 22, y + 8)
  for i, c in ipairs(SWATCHES) do
    local sx = x + i * (size + 5)
    if ui.button("", sx, y, size, size, { font = app.fonts.tiny }) then self:apply("color", c) end
    local r, g, b = Objects.colorOf(c)
    love.graphics.setColor(r, g, b)
    love.graphics.rectangle("fill", sx + 5, y + 5, size - 10, size - 10, 3, 3)
  end
  y = y + size + 8
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.print("Shared channels", x, y + 6)
  local map = e.map
  map.channels = map.channels or {}
  for n = 1, 8 do
    local sx = x + 130 + (n - 1) * (size + 5)
    local label = (o.color == "ch" .. n) and "*" or tostring(n)
    if ui.button(label, sx, y, size, size, { font = app.fonts.tiny, color = o.color == "ch" .. n and ui.ACCENT or nil }) then
      if not map.channels[n] then map.channels[n] = SWATCHES[n] end
      self:apply("color", "ch" .. n)
    end
    local r, g, b = Objects.colorOf(map.channels[n] or "")
    if r then
      love.graphics.setColor(r, g, b)
      love.graphics.rectangle("fill", sx + 4, y + size - 8, size - 8, 4)
    end
  end
  y = y + size + 8
  local channel = type(o.color) == "string" and o.color:match("^ch(%d+)$")
  local current = channel and map.channels[tonumber(channel)] or o.color
  local r, g, b = Objects.colorOf(current)
  if r then
    local vals = { math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5) }
    for i, name in ipairs({ "Red", "Green", "Blue" }) do
      local d = ui.cycler(name, tostring(vals[i]), x + (i - 1) * ((w + 8) / 3), y, (w - 16) / 3, 30)
      if d ~= 0 then
        vals[i] = math.max(0, math.min(255, vals[i] + d * 15))
        local hex = string.format("#%02X%02X%02X", vals[1], vals[2], vals[3])
        if channel then
          e:push()
          map.channels[tonumber(channel)] = hex
          e:touch()
        else
          self:apply("color", hex)
        end
      end
    end
    y = y + 38
  end
  return y
end

function Popup:draw()
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local x, y, w, h = 310, 40, 660, 640
  ui.panel(x, y, w, h)
  local o = self.items[1]
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1)
  local title = (self.editor.NAMES[o.type] or o.type) .. (#self.items > 1 and ("  x" .. #self.items) or "")
  love.graphics.printf(title, x, y + 10, w, "center")
  if ui.button("Done", x + w - 110, y + h - 46, 96, 36, { font = app.fonts.med }) then
    app.pop()
    return
  end
  if o.parent and ui.button("Detach", x + 14, y + h - 46, 96, 36, { font = app.fonts.med }) then
    self:apply("parent", nil)
  end
  local rows = {}
  for _, row in ipairs(ROWS[o.type] or {}) do
    if not row.show or row.show(o) then rows[#rows + 1] = row end
  end
  local rowH = 34
  local colorH = COLORED[o.type] and 150 or 0
  local viewY, viewH = y + 56, h - 110
  local cols = 2
  local contentH = math.ceil(#rows / cols) * rowH + colorH
  ui.beginScroll(self.scroll, x + 10, viewY, w - 20, viewH, contentH)
  local top = viewY - (self.scroll.y or 0)
  local colW = (w - 44) / 2
  for i, row in ipairs(rows) do
    local cx = x + 14 + ((i - 1) % cols) * (colW + 10)
    local cy = top + math.floor((i - 1) / cols) * rowH
    local key, val = row[1], o[row[1]]
    if val == nil and row.options then val = row.options[1] end
    local d = ui.cycler(row[2], fmtVal(val), cx, cy, colW, 30)
    if d ~= 0 then
      if row.options then
        local idx = 1
        for k, opt in ipairs(row.options) do if opt == val then idx = k end end
        self:apply(key, row.options[(idx - 1 + d) % #row.options + 1])
      else
        local v = (tonumber(val) or 0) + d * row[3]
        v = math.max(row[4], math.min(row[5], v))
        v = math.floor(v / row[3] + 0.5) * row[3]
        if row[3] < 1 then v = math.floor(v * 100 + 0.5) / 100 end
        self:apply(key, v)
      end
    end
  end
  if colorH > 0 then
    self:drawColor(x + 14, top + math.ceil(#rows / cols) * rowH + 6, w - 44, o)
  end
  ui.endScroll(self.scroll)
end

return Popup
