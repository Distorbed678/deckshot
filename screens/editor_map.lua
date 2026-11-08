-- Map editor. The arena is shown at 62.5% in the middle; tools on the left, the selected
-- item's properties on the right, messages along the bottom.
--   Mouse: place / select / drag (corner handles resize). Right click: cancel / finish a path.
--   Keys: 1-8 tools, G grid, M mirror, Del delete, Ctrl+D duplicate, Ctrl+Z / Ctrl+Y undo / redo,
--         arrows nudge, Ctrl+S save, Esc back.
local app = require "core.app"
local ui = require "core.ui"
local Map = require "game.map"
local Objects = require "game.objects"
local sfx = require "gfx.sfx"

local Editor = {}
Editor.__index = Editor

local SCALE = 960 / Map.W
local OX, OY = 150, 58               -- where the arena is drawn
local AW, AH = Map.W, Map.H
local GRID, FINE = 24, 6
local MAX_UNDO = 100

local TOOLS = {
  { id = "select", name = "Select" }, { id = "block", name = "Block" }, { id = "oneway", name = "One-way" },
  { id = "spawn", name = "Spawns" }, { id = "rope", name = "Rope" }, { id = "path", name = "Path" },
}
local OBJ_TYPES = {
  "saw", "spikes", "laser", "crusher", "flame", "acid", "turret", "arm", "conveyor", "pad", "fan",
  "crumble", "platform", "crate", "glass", "barrel", "gas", "wall", "plank", "weight",
}
local OBJ_NAMES = {
  saw = "Saw", spikes = "Spikes", laser = "Laser", crusher = "Crusher", flame = "Flame jet", acid = "Acid",
  turret = "Turret", arm = "Blade arm", conveyor = "Conveyor", pad = "Pad", fan = "Fan",
  crumble = "Crumbling", platform = "Mover", crate = "Crate", glass = "Glass", barrel = "Barrel",
  gas = "Gas can", wall = "Break wall", plank = "Plank", weight = "Weight", rope = "Rope",
}

-- Editable properties per object type: { key, label, step, min, max } or options = { ... }.
local DIRS4 = { "up", "down", "left", "right" }
local CYCLE = { { "off", "Off time", 0.1, 0, 10 }, { "warn", "Warn", 0.1, 0, 3 }, { "on", "On time", 0.1, 0, 10 },
  { "phase", "Offset", 0.1, 0, 10 } }
local function props(list, extra)
  local out = {}
  for _, p in ipairs(list) do out[#out + 1] = p end
  for _, p in ipairs(extra or {}) do out[#out + 1] = p end
  return out
end
local WH = { { "w", "Width", 10, 10, Map.W }, { "h", "Height", 2, 4, Map.H } }
local PROPS = {
  saw = { { "r", "Radius", 2, 10, 90 }, { "speed", "Speed", 20, 0, 800 }, { "damage", "Damage", 5, 0, 200 } },
  spikes = props(WH, { { "dir", "Points", options = DIRS4 }, { "damage", "Damage", 5, 0, 200 },
    { "on", "Out time", 0.1, 0, 10 }, { "off", "In time", 0.1, 0, 10 }, { "warn", "Warn", 0.1, 0, 3 },
    { "phase", "Offset", 0.1, 0, 10 } }),
  laser = props({ { "dir", "Points", options = DIRS4 }, { "damage", "Damage", 5, 0, 200 } }, CYCLE),
  crusher = props(WH, { { "travel", "Travel", 10, 20, 600 }, { "wait", "Wait", 0.1, 0.2, 10 },
    { "phase", "Offset", 0.1, 0, 10 }, { "damage", "Damage", 5, 0, 200 } }),
  flame = props({ { "length", "Length", 10, 40, 500 }, { "damage", "Damage", 2, 0, 100 } }, CYCLE),
  acid = props(WH, { { "damage", "Damage", 5, 0, 200 } }),
  turret = { { "hp", "HP", 10, 10, 500 }, { "rate", "Fire every", 0.1, 0.3, 10 }, { "damage", "Damage", 5, 0, 200 },
    { "phase", "Offset", 0.1, 0, 10 } },
  arm = { { "length", "Length", 10, 30, 400 }, { "count", "Saws", 1, 1, 2 }, { "spin", "Spin", 0.2, -6, 6 },
    { "r", "Saw radius", 2, 10, 60 }, { "damage", "Damage", 5, 0, 200 }, { "phase", "Angle", 0.2, 0, 6.2 } },
  conveyor = props(WH, { { "speed", "Speed", 20, -600, 600 } }),
  pad = { { "w", "Width", 10, 30, 300 }, { "power", "Power", 50, 400, 3000 } },
  fan = props(WH, { { "dir", "Blows", options = DIRS4 }, { "force", "Force", 200, 200, 8000 } }),
  crumble = props(WH, { { "delay", "Delay", 0.1, 0.1, 5 }, { "back", "Returns", 0.5, 0.5, 20 } }),
  platform = props(WH, { { "speed", "Speed", 10, 0, 600 }, { "loop", "Loop path", options = { false, true } } }),
  crate = props(WH, { { "hp", "HP", 10, 1, 1000 }, { "drop", "Drop chance", 0.01, 0, 1 } }),
  glass = props(WH, { { "hp", "HP", 1, 1, 200 } }),
  barrel = { { "hp", "HP", 5, 1, 500 }, { "radius", "Blast", 10, 30, 400 }, { "damage", "Damage", 5, 0, 300 } },
  gas = { { "hp", "HP", 5, 1, 500 }, { "radius", "Cloud", 10, 30, 400 } },
  wall = props(WH, { { "hp", "HP", 10, 10, 2000 } }),
  plank = WH,
  weight = { { "r", "Size", 2, 10, 60 }, { "damage", "Damage", 5, 0, 300 } },
  rope = {},
}
local PATHED = { saw = true, platform = true }
local RECT_TYPES = {}
for t, d in pairs(Objects.DEFAULTS) do
  if d.w then RECT_TYPES[t] = true end
end

---------------------------------------------------------------- helpers
local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do
    if k ~= "twin" then c[k] = deepcopy(v) end
  end
  return c
end

local function toArena(mx, my)
  return (mx - OX) / SCALE, (my - OY) / SCALE
end

local function inArena(mx, my)
  return mx >= OX and mx <= OX + AW * SCALE and my >= OY and my <= OY + AH * SCALE
end

local function round(v) return math.floor(v + 0.5) end

local function blankMap()
  return {
    name = "New Map",
    spawns = { { 288, 696 }, { 1248, 696 }, { 480, 696 }, { 1056, 696 } },
    rects = { { x = 144, y = 744, w = 1248, h = 48 } },
    objects = {},
  }
end

-- opts: { map = existing map (edited as a copy), returnTo = screen }
function Editor.new(opts)
  opts = opts or {}
  local src = opts.map
  local m = src and Map.parse(Map.serialize(src)) or blankMap()
  if src then
    m.id, m.builtin, m.custom, m.file, m.defaultText = src.id, src.builtin, src.custom, src.file, src.defaultText
  else
    m.custom = true
  end
  local e = setmetatable({
    map = m, tool = "select", objType = "crate", grid = true, mirror = false,
    sel = nil, undo = {}, redo = {}, msg = nil, msgT = 0, problems = {}, dirty = false,
    returnTo = opts.returnTo, spawnNext = 1,
  }, Editor)
  e:validate()
  return e
end

function Editor:say(text, bad)
  self.msg, self.msgT, self.msgBad = text, 4, bad
end

function Editor:snap(v)
  local fine = love.keyboard.isDown("lshift", "rshift")
  local g = (self.grid and not fine) and GRID or (fine and FINE or 1)
  return round(v / g) * g
end

---------------------------------------------------------------- undo
function Editor:push()
  self.undo[#self.undo + 1] = Map.serialize(self.map)
  if #self.undo > MAX_UNDO then table.remove(self.undo, 1) end
  self.redo = {}
  self.dirty = true
end

local function restore(self, text)
  local keep = self.map
  local m = Map.parse(text)
  m.id, m.builtin, m.custom, m.file, m.defaultText = keep.id, keep.builtin, keep.custom, keep.file, keep.defaultText
  self.map = m
  self.sel = nil
  self:validate()
end

function Editor:doUndo()
  if #self.undo == 0 then return end
  self.redo[#self.redo + 1] = Map.serialize(self.map)
  restore(self, table.remove(self.undo))
end

function Editor:doRedo()
  if #self.redo == 0 then return end
  self.undo[#self.undo + 1] = Map.serialize(self.map)
  restore(self, table.remove(self.redo))
end

---------------------------------------------------------------- items
-- Items: { kind = "rect" | "obj" | "spawn", ref = table, index = n }
local function objBox(o)
  if o.w then return o.x, o.y, o.w, o.h end
  local r = o.r or (o.type == "rope" and 8) or (o.type == "arm" and 14) or 18
  return o.x - r, o.y - r, r * 2, r * 2
end
Editor.objBox = objBox

function Editor:itemAt(x, y)
  local m = self.map
  for i = 4, 1, -1 do
    local s = m.spawns[i]
    if (x - s[1]) ^ 2 + (y - s[2]) ^ 2 < 22 * 22 then return { kind = "spawn", ref = s, index = i } end
  end
  for i = #m.objects, 1, -1 do
    local o = m.objects[i]
    local bx, by, bw, bh = objBox(o)
    if o.type == "rope" then
      local t = m.objects[o.target or 0]
      if t then
        local tx, ty = Objects.hangPoint(t)
        if Objects.segDist(x, y, o.x, o.y, tx, ty) < 6 then return { kind = "obj", ref = o, index = i } end
      end
    end
    if x >= bx - 3 and x <= bx + bw + 3 and y >= by - 3 and y <= by + bh + 3 then
      return { kind = "obj", ref = o, index = i }
    end
  end
  for i = #m.rects, 1, -1 do
    local r = m.rects[i]
    if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then return { kind = "rect", ref = r, index = i } end
  end
end

-- The mirror image of an item's table (rects / objects).
local MIRROR_DIR = { left = "right", right = "left" }
local function mirrorOf(t, isObj)
  local c = deepcopy(t)
  if c.w then
    c.x = AW - c.x - c.w
  else
    c.x = AW - c.x
  end
  if isObj then
    if c.dir and MIRROR_DIR[c.dir] then c.dir = MIRROR_DIR[c.dir] end
    if c.path then
      for _, p in ipairs(c.path) do p[1] = AW - p[1] end
    end
    if c.spin then c.spin = -c.spin end
    if c.speed and c.type == "conveyor" then c.speed = -c.speed end
  end
  return c
end

-- Keep a mirrored twin in step after its original changed.
local function syncTwin(t, isObj)
  local tw = t.twin
  if not tw then return end
  local m = mirrorOf(t, isObj)
  for k, v in pairs(m) do
    if k ~= "target" then tw[k] = v end
  end
end

function Editor:addRect(r)
  table.insert(self.map.rects, r)
  if self.mirror and math.abs((r.x + r.w / 2) - AW / 2) > 2 then
    local tw = mirrorOf(r, false)
    r.twin, tw.twin = tw, r
    table.insert(self.map.rects, tw)
  end
  return r
end

function Editor:addObject(o)
  table.insert(self.map.objects, o)
  if self.mirror and o.type ~= "rope" and math.abs(((o.w and o.x + o.w / 2) or o.x) - AW / 2) > 2 then
    local tw = mirrorOf(o, true)
    o.twin, tw.twin = tw, o
    table.insert(self.map.objects, tw)
  end
  return o
end

-- Remove an object and fix rope targets (they're object numbers).
function Editor:removeObject(o)
  local list = self.map.objects
  local idx
  for i, x in ipairs(list) do if x == o then idx = i end end
  if not idx then return end
  table.remove(list, idx)
  for i = #list, 1, -1 do
    local r = list[i]
    if r.type == "rope" and r.target then
      if r.target == idx then
        table.remove(list, i)
        -- removing a rope before idx shifts things again; simplest is to rescan
        return self:fixRopes()
      elseif r.target > idx then
        r.target = r.target - 1
      end
    end
  end
end

function Editor:fixRopes()
  -- After structural changes, drop ropes whose target vanished.
  local list = self.map.objects
  for i = #list, 1, -1 do
    local r = list[i]
    if r.type == "rope" and (not r.target or not list[r.target] or list[r.target].type == "rope") then
      table.remove(list, i)
      for _, o in ipairs(list) do
        if o.type == "rope" and o.target and o.target > i then o.target = o.target - 1 end
      end
    end
  end
end

function Editor:deleteSel()
  local s = self.sel
  if not s or s.kind == "spawn" then return end
  self:push()
  local function del(ref)
    if s.kind == "rect" then
      for i, r in ipairs(self.map.rects) do if r == ref then table.remove(self.map.rects, i) break end end
    else
      self:removeObject(ref)
    end
  end
  local twin = s.ref.twin
  del(s.ref)
  if twin then del(twin) end
  self.sel = nil
  self:validate()
end

function Editor:duplicateSel()
  local s = self.sel
  if not s or s.kind == "spawn" then return end
  self:push()
  local c = deepcopy(s.ref)
  c.x = c.x + GRID * 2
  c.y = c.y + GRID
  if c.path then for _, p in ipairs(c.path) do p[1], p[2] = p[1] + GRID * 2, p[2] + GRID end end
  if s.kind == "rect" then
    self.sel = { kind = "rect", ref = self:addRect(c) }
  else
    if c.type == "rope" then return end
    self.sel = { kind = "obj", ref = self:addObject(c) }
  end
  self:validate()
end

function Editor:moveItem(item, x, y)
  local ref = item.ref
  if item.kind == "spawn" then
    ref[1], ref[2] = x, y
    return
  end
  local dx, dy = x - ref.x, y - ref.y
  ref.x, ref.y = x, y
  if ref.path then for _, p in ipairs(ref.path) do p[1], p[2] = p[1] + dx, p[2] + dy end end
  syncTwin(ref, item.kind == "obj")
end

---------------------------------------------------------------- validation
-- Problems: spawns must land on solid ground, away from hazards; there must be ground.
function Editor:validate()
  local m = self.map
  local problems = {}
  if not m.name or m.name:match("^%s*$") then problems[#problems + 1] = "The map needs a name" end
  local solids = 0
  for _, r in ipairs(m.rects) do if not r.oneway then solids = solids + 1 end end
  if solids == 0 then problems[#problems + 1] = "Add at least one solid block" end
  local World = require "game.world"
  local Input = require "core.input"
  sfx.silent = true
  for i = 1, 4 do
    local s = m.spawns[i]
    local inp = Input.remote()
    inp.aim = nil
    local ok, landed, hurt, near = pcall(function()
      local w = World.new({ { name = "T", input = inp } }, 1, { pickFrom = 1, picksPerRound = 1, weights = {},
        rarity = {}, disabled = {}, forceMap = m, barrier = false })
      w:startRound()
      w.state = "playing"
      local p = w.players[1]
      p.x, p.y = s[1], s[2]
      local startFree = p:freeAt(p.x, p.y, w.solids)
      for _ = 1, 90 do
        w.state = "playing"
        w:update(1 / 60)
      end
      local nearHazard = false
      for _, o in ipairs(w.objects) do
        if Objects.HAZARD[o.type] then
          local bx, by, bw, bh = objBox(o)
          local cx = math.max(bx, math.min(s[1], bx + bw))
          local cy = math.max(by, math.min(s[2], by + bh))
          if (cx - s[1]) ^ 2 + (cy - s[2]) ^ 2 < 120 * 120 then nearHazard = true end
        end
      end
      return startFree and p.onGround and not p.dead, p.hp < p.stats.maxHp or p.dead, nearHazard
    end)
    if not ok then
      problems[#problems + 1] = "Spawn " .. i .. ": couldn't test (" .. tostring(landed) .. ")"
    else
      if not landed then problems[#problems + 1] = "Spawn " .. i .. " doesn't land on solid ground" end
      if hurt then problems[#problems + 1] = "Spawn " .. i .. " gets hurt" end
      if near then problems[#problems + 1] = "Spawn " .. i .. " is within 120 px of a hazard" end
    end
  end
  sfx.silent = false
  -- Duplicate names among custom maps.
  for _, other in ipairs(Map.list) do
    if other ~= m and other.id ~= m.id and other.name:lower() == (m.name or ""):lower()
        and not (m.file and other.file == m.file) then
      problems[#problems + 1] = "Another map is already called \"" .. other.name .. "\""
      break
    end
  end
  self.problems = problems
  return #problems == 0
end

---------------------------------------------------------------- actions
function Editor:save()
  if not self:validate() then
    self:say("Fix the problems below before saving", true)
    return false
  end
  local m = self.map
  if m.builtin then
    Map.saveOverride(m)
    self:say("Saved your version of " .. m.name .. " (reset it from the map list)")
  else
    m.file = Map.saveCustom(m)
    self:say("Saved " .. m.name)
  end
  Map.loadAll()
  self.dirty = false
  sfx.ui("cardPick")
  return true
end

function Editor:share()
  if not self:validate() then
    self:say("Fix the problems below before sharing", true)
    return
  end
  local code = Map.encodeShare(self.map)
  local ok = pcall(love.system.setClipboardText, code)
  self:say(ok and ("Map code copied (" .. #code .. " characters)") or "Couldn't use the clipboard", not ok)
end

function Editor:import()
  local ok, text = pcall(love.system.getClipboardText)
  local m, err = Map.decodeShare(ok and text or "")
  if not m then
    self:say((err or "No map code") .. " (copy a code first)", true)
    return
  end
  self:push()
  m.custom = true
  self.map = m
  self.sel = nil
  self:validate()
  self:say("Imported " .. m.name .. " as a new map")
end

function Editor:test()
  local Match = require "screens.match"
  local copy = Map.parse(Map.serialize(self.map))
  copy.index = 0
  app.switch(Match.newLocal(99, { map = copy, returnTo = self, test = true }))
end

function Editor:exit()
  if self.returnTo then
    app.switch(self.returnTo)
  else
    app.switch(require("screens.editor_hub").new())
  end
end

---------------------------------------------------------------- input
function Editor:keypressed(key)
  if ui.capturing then return end
  local ctrl = love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
  if self.typing then
    if key == "escape" or key == "return" or key == "kpenter" then
      self.typing = false
      self:validate()
    end
    return
  end
  if key == "escape" then
    if self.drag or self.pathFor or self.ropeFrom then
      self.drag, self.pathFor, self.ropeFrom = nil, nil, nil
    else
      self:exit()
    end
  elseif ctrl and key == "z" then self:doUndo()
  elseif ctrl and key == "y" then self:doRedo()
  elseif ctrl and key == "s" then self:save()
  elseif ctrl and key == "d" then self:duplicateSel()
  elseif key == "delete" or key == "backspace" then self:deleteSel()
  elseif key == "g" then self.grid = not self.grid
  elseif key == "m" then self.mirror = not self.mirror
  elseif tonumber(key) and TOOLS[tonumber(key)] then self.tool = TOOLS[tonumber(key)].id
  elseif key == "7" then self.tool = "object"
  elseif self.sel and (key == "left" or key == "right" or key == "up" or key == "down") then
    local step = love.keyboard.isDown("lshift", "rshift") and 1 or (self.grid and GRID or 5)
    local dx = key == "left" and -step or key == "right" and step or 0
    local dy = key == "up" and -step or key == "down" and step or 0
    self:push()
    local ref = self.sel.ref
    if self.sel.kind == "spawn" then
      self:moveItem(self.sel, ref[1] + dx, ref[2] + dy)
    else
      self:moveItem(self.sel, ref.x + dx, ref.y + dy)
    end
    self:validate()
  end
end

function Editor:mousepressed(mx, my, button)
  if not inArena(mx, my) then return end
  local x, y = toArena(mx, my)
  local sx, sy = self:snap(x), self:snap(y)
  local m = self.map

  if button == 2 then
    self.pathFor, self.ropeFrom, self.drag = nil, nil, nil
    return
  end
  if button ~= 1 then return end

  local tool = self.tool
  if tool == "select" then
    -- Resize handles on the selection first.
    local s = self.sel
    if s and s.kind ~= "spawn" and s.ref.w then
      local r = s.ref
      local hx, hy = r.x + r.w, r.y + r.h
      if math.abs(x - hx) < 10 and math.abs(y - hy) < 10 then
        self:push()
        self.drag = { mode = "resize", item = s }
        return
      end
    end
    local item = self:itemAt(x, y)
    self.sel = item
    if item then
      self:push()
      local ref = item.ref
      local ix, iy = item.kind == "spawn" and ref[1] or ref.x, item.kind == "spawn" and ref[2] or ref.y
      self.drag = { mode = "move", item = item, offX = x - ix, offY = y - iy }
    end
  elseif tool == "block" or tool == "oneway" then
    self:push()
    local r = { x = sx, y = sy, w = 0, h = 0, oneway = tool == "oneway" or nil }
    self.drag = { mode = "create", rect = r, x0 = sx, y0 = sy }
  elseif tool == "spawn" then
    local item = self:itemAt(x, y)
    self:push()
    if item and item.kind == "spawn" then
      self.sel = item
      self.drag = { mode = "move", item = item, offX = x - item.ref[1], offY = y - item.ref[2] }
    else
      local i = self.spawnNext
      m.spawns[i][1], m.spawns[i][2] = sx, sy
      self.sel = { kind = "spawn", ref = m.spawns[i], index = i }
      self.spawnNext = i % 4 + 1
    end
  elseif tool == "object" then
    self:push()
    local t = self.objType
    local o = { type = t }
    local d = Objects.DEFAULTS[t] or {}
    for k, v in pairs(d) do o[k] = v end
    if RECT_TYPES[t] then
      o.x, o.y = sx, sy
    else
      o.x, o.y = sx, sy
    end
    -- Floor things (spikes, pads, crates, barrels, gas, acid) sit on top of where you click.
    if t == "pad" or t == "crate" or t == "barrel" or t == "gas" then o.y = sy - (o.h or 0) end
    self.sel = { kind = "obj", ref = self:addObject(o) }
  elseif tool == "rope" then
    if not self.ropeFrom then
      self.ropeFrom = { sx, sy }
      self:say("Now click what the rope holds (crate, barrel, saw, weight, plank, mover, gas can)")
    else
      local item = self:itemAt(x, y)
      if item and item.kind == "obj" and item.ref.type ~= "rope" then
        self:push()
        local idx
        for i, o in ipairs(m.objects) do if o == item.ref then idx = i end end
        table.insert(m.objects, { type = "rope", x = self.ropeFrom[1], y = self.ropeFrom[2], target = idx })
        self:say("Rope added")
      else
        self:say("Click an object for the rope to hold", true)
      end
      self.ropeFrom = nil
    end
  elseif tool == "path" then
    if not self.pathFor then
      local item = self:itemAt(x, y)
      if item and item.kind == "obj" and PATHED[item.ref.type] then
        self:push()
        local o = item.ref
        local cx, cy = o.x, o.y
        if o.w then cx, cy = o.x + o.w / 2, o.y + o.h / 2 end
        o.path = { { cx, cy } }
        self.pathFor = o
        self.sel = item
        self:say("Click to add waypoints, right click to finish")
      else
        self:say("Click a saw or a moving platform first", true)
      end
    else
      table.insert(self.pathFor.path, { sx, sy })
      syncTwin(self.pathFor, true)
    end
  end
  self:validate()
end

function Editor:mousereleased(mx, my, button)
  local d = self.drag
  if not d then return end
  if d.mode == "create" then
    local r = d.rect
    if r.w >= 10 and r.h >= 4 then
      self.sel = { kind = "rect", ref = self:addRect(r) }
    else
      table.remove(self.undo)
    end
  end
  self.drag = nil
  self:validate()
end

function Editor:update(dt)
  self.msgT = math.max(0, self.msgT - dt)
  local d = self.drag
  if not d then return end
  local mx, my = app.mouse()
  local x, y = toArena(mx, my)
  if d.mode == "create" then
    local sx, sy = self:snap(x), self:snap(y)
    d.rect.x, d.rect.y = math.min(d.x0, sx), math.min(d.y0, sy)
    d.rect.w, d.rect.h = math.abs(sx - d.x0), math.abs(sy - d.y0)
  elseif d.mode == "move" then
    self:moveItem(d.item, self:snap(x - d.offX), self:snap(y - d.offY))
  elseif d.mode == "resize" then
    local r = d.item.ref
    r.w = math.max(10, self:snap(x) - r.x)
    r.h = math.max(4, self:snap(y) - r.y)
    syncTwin(r, d.item.kind == "obj")
  end
end

---------------------------------------------------------------- drawing
function Editor:drawArena()
  local m = self.map
  love.graphics.setColor(0.07, 0.07, 0.1)
  love.graphics.rectangle("fill", OX, OY, AW * SCALE, AH * SCALE)
  love.graphics.push()
  love.graphics.translate(OX, OY)
  love.graphics.scale(SCALE, SCALE)
  love.graphics.setScissor() -- (drawn on the canvas; nothing outside matters much)

  if self.grid then
    love.graphics.setColor(1, 1, 1, 0.04)
    love.graphics.setLineWidth(1)
    for gx = 0, AW, GRID do love.graphics.line(gx, 0, gx, AH) end
    for gy = 0, AH, GRID do love.graphics.line(0, gy, AW, gy) end
  end
  if self.mirror then
    love.graphics.setColor(0.4, 0.8, 1, 0.35)
    love.graphics.setLineWidth(2)
    love.graphics.line(AW / 2, 0, AW / 2, AH)
  end

  Map.draw(m, true)
  local list = Objects.build(m)
  Objects.draw(list, {})
  -- Path lines and rope previews
  for _, o in ipairs(m.objects) do
    if o.path and #o.path > 1 then
      love.graphics.setColor(0.4, 0.9, 1, 0.6)
      love.graphics.setLineWidth(2)
      local flat = {}
      for _, p in ipairs(o.path) do flat[#flat + 1] = p[1]; flat[#flat + 1] = p[2] end
      love.graphics.line(flat)
      for _, p in ipairs(o.path) do love.graphics.circle("fill", p[1], p[2], 4) end
    end
  end
  if self.ropeFrom then
    local mx, my = toArena(app.mouse())
    love.graphics.setColor(0.72, 0.6, 0.42, 0.7)
    love.graphics.setLineWidth(3)
    love.graphics.line(self.ropeFrom[1], self.ropeFrom[2], mx, my)
  end

  -- Spawns
  local colors = require("game.world").COLORS
  for i, s in ipairs(m.spawns) do
    local c = colors[i]
    love.graphics.setColor(c[1], c[2], c[3], 0.35)
    love.graphics.circle("fill", s[1], s[2], 20)
    love.graphics.setColor(c)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", s[1], s[2], 20)
    love.graphics.setFont(app.fonts.title)
    love.graphics.printf(tostring(i), s[1] - 20, s[2] - 15, 40, "center")
  end

  -- Rect being dragged out
  local d = self.drag
  if d and d.mode == "create" then
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.rectangle("fill", d.rect.x, d.rect.y, d.rect.w, d.rect.h)
  end

  -- Selection
  local s = self.sel
  if s then
    love.graphics.setColor(1, 0.8, 0.2)
    love.graphics.setLineWidth(3)
    if s.kind == "spawn" then
      love.graphics.circle("line", s.ref[1], s.ref[2], 26)
    else
      local bx, by, bw, bh
      if s.kind == "rect" then bx, by, bw, bh = s.ref.x, s.ref.y, s.ref.w, s.ref.h else bx, by, bw, bh = objBox(s.ref) end
      love.graphics.rectangle("line", bx - 3, by - 3, bw + 6, bh + 6)
      if s.ref.w then love.graphics.rectangle("fill", s.ref.x + s.ref.w - 6, s.ref.y + s.ref.h - 6, 12, 12) end
      if s.ref.twin then
        local t = s.ref.twin
        local tx, ty, tw, th
        if s.kind == "rect" then tx, ty, tw, th = t.x, t.y, t.w, t.h else tx, ty, tw, th = objBox(t) end
        love.graphics.setColor(1, 0.8, 0.2, 0.4)
        love.graphics.rectangle("line", tx - 3, ty - 3, tw + 6, th + 6)
      end
    end
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 0.15)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", OX, OY, AW * SCALE, AH * SCALE)
end

function Editor:drawToolbar()
  local x, y, w, h = 8, OY, 134, 30
  for i, t in ipairs(TOOLS) do
    local on = self.tool == t.id
    if ui.button(i .. "  " .. t.name, x, y, w, h, { font = app.fonts.med, color = on and ui.ACCENT or nil }) then
      self.tool = t.id
      self.pathFor, self.ropeFrom = nil, nil
    end
    y = y + h + 4
  end
  y = y + 8
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.print("7  OBJECTS", x + 4, y)
  y = y + 22
  local bw, bh = 65, 23
  for i, t in ipairs(OBJ_TYPES) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local on = self.tool == "object" and self.objType == t
    if ui.button(OBJ_NAMES[t], x + col * (bw + 4), y + row * (bh + 3), bw, bh,
      { font = app.fonts.tiny, color = on and ui.ACCENT or nil }) then
      self.tool, self.objType = "object", t
    end
  end
end

local function fmtVal(v)
  if type(v) == "boolean" then return v and "Yes" or "No" end
  if type(v) == "number" then
    if v == math.floor(v) then return tostring(v) end
    return string.format("%.2f", v):gsub("0$", "")
  end
  return tostring(v)
end

function Editor:drawInspector()
  local x, y, w = 1118, OY, 156
  ui.panel(x - 6, y - 6, w + 12, 540)
  local s = self.sel
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1)
  if not s then
    love.graphics.printf("Nothing selected", x, y + 4, w, "center")
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.printf("Pick a tool on the left, then click or drag in the arena.\n\nSelect: click an item, " ..
      "drag to move, drag its corner to resize.\n\nG: grid " .. (self.grid and "(on)" or "(off)") ..
      "\nM: mirror " .. (self.mirror and "(on)" or "(off)") .. "\nShift: fine snap\nDel: delete\nCtrl+D: duplicate" ..
      "\nCtrl+Z / Y: undo / redo", x, y + 34, w, "left")
    return
  end
  local ref = s.ref
  local title = s.kind == "spawn" and ("Spawn " .. s.index) or s.kind == "rect" and (ref.oneway and "One-way" or "Block")
    or OBJ_NAMES[ref.type] or ref.type
  love.graphics.printf(title, x, y + 2, w, "center")
  y = y + 30
  local rows = {}
  if s.kind == "spawn" then
    rows = { { 1, "X", 5, 0, AW }, { 2, "Y", 5, 0, AH } }
  elseif s.kind == "rect" then
    rows = { { "x", "X", 5, -100, AW }, { "y", "Y", 5, -100, AH }, { "w", "Width", 10, 10, Map.W + 200 },
      { "h", "Height", 2, 4, 800 }, { "oneway", "One-way", options = { false, true } } }
  else
    rows = { { "x", "X", 5, -100, AW + 100 }, { "y", "Y", 5, -100, AH + 100 } }
    for _, p in ipairs(PROPS[ref.type] or {}) do rows[#rows + 1] = p end
  end
  for _, row in ipairs(rows) do
    local key = row[1]
    local val = ref[key]
    if val == nil and row.options then val = row.options[1] end
    local d = ui.cycler(row[2], fmtVal(val), x, y, w, 26)
    if d ~= 0 then
      self:push()
      if row.options then
        local idx = 1
        for i, o in ipairs(row.options) do if o == val then idx = i end end
        ref[key] = row.options[(idx - 1 + d) % #row.options + 1]
        if key == "oneway" and ref[key] == false then ref[key] = nil end
      else
        local v = (tonumber(val) or 0) + d * row[3]
        v = math.max(row[4], math.min(row[5], v))
        ref[key] = math.floor(v / row[3] + 0.5) * row[3]
        if row[3] < 1 then ref[key] = math.floor(ref[key] * 100 + 0.5) / 100 end
      end
      if s.kind ~= "spawn" then syncTwin(ref, s.kind == "obj") end
      self:validate()
    end
    y = y + 30
  end
  if s.kind == "obj" and ref.path then
    if ui.button("Clear path (" .. #ref.path .. ")", x, y, w, 26, { font = app.fonts.small }) then
      self:push()
      ref.path = nil
    end
    y = y + 30
  end
  if s.kind ~= "spawn" then
    if ui.button("Delete", x, y + 6, w, 28, { font = app.fonts.med }) then self:deleteSel() end
  end
end

function Editor:drawTopBar()
  local m = self.map
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.print(m.builtin and (m.edited and "BUILT-IN (EDITED)" or "BUILT-IN") or "CUSTOM MAP", 10, 6)
  if self.typing then
    ui.focus = ui.count + 1 -- keep keyboard focus in the name field while typing
    local name, submitted = ui.textField(m.name or "", 10, 22, 240, 30, { font = app.fonts.med, maxLength = 30,
      placeholder = "Map name" })
    if name ~= m.name then
      m.name = name
      self.dirty = true
    end
    if submitted then
      self.typing = false
      self:validate()
    end
  elseif ui.button((m.name ~= "" and m.name or "Map name") .. "  (rename)", 10, 22, 240, 30, { font = app.fonts.med }) then
    self.typing = true
  end
  local buttons = {
    { "Undo", function() self:doUndo() end, #self.undo > 0 },
    { "Redo", function() self:doRedo() end, #self.redo > 0 },
    { self.grid and "Grid: On" or "Grid: Off", function() self.grid = not self.grid end, true },
    { self.mirror and "Mirror: On" or "Mirror: Off", function() self.mirror = not self.mirror end, true },
    { "Test", function() self:test() end, true },
    { "Save", function() self:save() end, true },
    { "Share", function() self:share() end, true },
    { "Import", function() self:import() end, true },
    { "Exit", function() self:exit() end, true },
  }
  local bx = 262
  local bw = (app.W - bx - 8 - (#buttons - 1) * 6) / #buttons
  for _, b in ipairs(buttons) do
    if ui.button(b[1], bx, 12, bw, 36, { font = app.fonts.med, disabled = not b[3] }) then b[2]() end
    bx = bx + bw + 6
  end
end

function Editor:drawStatus()
  local y = OY + AH * SCALE + 8
  love.graphics.setFont(app.fonts.small)
  local ok = #self.problems == 0
  love.graphics.setColor(ok and { 0.4, 1, 0.5 } or { 1, 0.5, 0.4 })
  love.graphics.circle("fill", OX + 8, y + 9, 6)
  local text = ok and "Ready to save and share" or table.concat(self.problems, "   |   ")
  love.graphics.printf(text, OX + 22, y, AW * SCALE - 22, "left")
  if self.msg and self.msgT > 0 then
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(self.msgBad and { 1, 0.55, 0.45, math.min(1, self.msgT) } or { 1, 1, 1, math.min(1, self.msgT) })
    love.graphics.printf(self.msg, OX, y + 44, AW * SCALE, "center")
  end
  local mx, my = app.mouse()
  if inArena(mx, my) then
    local ax, ay = toArena(mx, my)
    love.graphics.setFont(app.fonts.tiny)
    love.graphics.setColor(1, 1, 1, 0.4)
    love.graphics.printf(string.format("%d, %d", self:snap(ax), self:snap(ay)), OX, y + 24, AW * SCALE, "right")
  end
end

function Editor:draw()
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  self:drawArena()
  self:drawToolbar()
  self:drawInspector()
  self:drawTopBar()
  self:drawStatus()
end

return Editor
