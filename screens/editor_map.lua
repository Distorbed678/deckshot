-- Map editor. The level fills the screen; the bottom bar has Build, Edit and Delete tabs.
--   Build: pick something from the palette, click or drag to paint it on the grid. Shift-drag a
--          block to stretch one block instead.
--   Edit:  click to select, Shift-click to add, drag on empty space to box-select. Drag to move;
--          the corner handle scales, the top handle rotates. E or double-click: Edit Object.
--   Delete: click or drag a box to remove things.
--   View:  mouse wheel zooms, right or middle drag pans.
--   Keys:  1/2/3 tabs, G grid size, M mirror, Del delete, Ctrl+C/V/D copy/paste/duplicate,
--          Ctrl+G group, Ctrl+Z/Y undo/redo, Q/R rotate, arrows nudge, Ctrl+S save, P play, Esc back.
local app = require "core.app"
local ui = require "core.ui"
local Map = require "game.map"
local Objects = require "game.objects"
local Physics = require "game.physics"
local sfx = require "gfx.sfx"
local fx = require "gfx.fx"
local Popup = require "screens.editor_object"

local Editor = {}
Editor.__index = Editor
Editor.noPadHints = true

local TOP_H, BAR_H = 52, 142
local AW, AH = Map.W, Map.H
local GRIDS = { 48, 24, 12, 6, 1 }
local MAX_UNDO = 100
local MAX_OBJECTS = 255

local NAMES = { block = "Block", saw = "Saw", spikes = "Spikes", laser = "Laser", crusher = "Crusher", flame = "Flame jet",
  liquid = "Liquid", turret = "Turret", arm = "Arm", rail = "Rail", pad = "Jump pad", fan = "Fan", rope = "Rope", weight = "Weight" }
Editor.NAMES = NAMES

local function block(material, extra)
  local d = { type = "block", material = material }
  for k, v in pairs(extra or {}) do d[k] = v end
  return d
end

-- The Build palette. Blocks are all one object; these are just starting points.
local PALETTE = {
  { name = "Blocks", items = {
    { name = "Stone", def = block("stone") },
    { name = "Crate", def = block("crate", { w = 48, h = 48, hp = 60, physics = true, onBreak = "pickup", drop = 0.08 }) },
    { name = "Wood", def = block("wood", { w = 96, h = 12, physics = true }) },
    { name = "Brick", def = block("brick", { w = 48, h = 120, hp = 150, physics = true }) },
    { name = "Glass", def = block("glass", { w = 12, h = 120, hp = 1, physics = true }) },
    { name = "Metal", def = block("metal", { w = 96, h = 24 }) },
    { name = "Ice", def = block("ice", { w = 144, h = 24 }) },
    { name = "Sticky", def = block("sticky", { w = 144, h = 24 }) },
    { name = "Barrel", def = block("barrel", { w = 36, h = 48, hp = 30, physics = true, onBreak = "explode", radius = 110, damage = 55 }) },
    { name = "Gas can", def = block("gas", { w = 28, h = 42, hp = 20, physics = true, onBreak = "gas", radius = 110 }) },
  } },
  { name = "Hazards", items = {
    { name = "Saw", def = { type = "saw" } }, { name = "Spikes", def = { type = "spikes" } },
    { name = "Weight", def = { type = "weight" } }, { name = "Crusher", def = { type = "crusher" } },
    { name = "Flame jet", def = { type = "flame" } }, { name = "Laser", def = { type = "laser" } },
    { name = "Turret", def = { type = "turret" } },
  } },
  { name = "Machines", items = {
    { name = "Arm", def = { type = "arm" } }, { name = "Rail", tool = "rail" },
    { name = "Jump pad", def = { type = "pad" } }, { name = "Fan", def = { type = "fan" } },
  } },
  { name = "Liquid", items = {
    { name = "Water", def = { type = "liquid", color = "#3A8BE0" } },
    { name = "Acid", def = { type = "liquid", color = "#59D934", damage = 20, buoyant = false } },
    { name = "Lava", def = { type = "liquid", color = "#FF5A1A", damage = 30, burn = true, buoyant = false, density = 2 } },
    { name = "Poison", def = { type = "liquid", color = "#9A5BE0", poison = true } },
  } },
  { name = "Links", items = {
    { name = "Rope", tool = "rope" }, { name = "Attach", tool = "attach" },
    { name = "Spawn 1", spawn = 1 }, { name = "Spawn 2", spawn = 2 }, { name = "Spawn 3", spawn = 3 }, { name = "Spawn 4", spawn = 4 },
  } },
}

local FLAGS = { { "physics", "Physics" }, { "breakable", "Breakable" }, { "oneway", "One-way" }, { "crumble", "Crumbles" },
  { "conveyor", "Conveyor" }, { "anchored", "Anchored" } }

---------------------------------------------------------------- helpers
local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = deepcopy(v) end
  return c
end

local function round(v) return math.floor(v + 0.5) end

-- A box around an object (before its rotation).
local function objBox(o)
  if o.type == "rail" and o.path and #o.path > 0 then
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(o.path) do
      x0, y0, x1, y1 = math.min(x0, p[1]), math.min(y0, p[2]), math.max(x1, p[1]), math.max(y1, p[2])
    end
    return x0 - 10, y0 - 10, x1 - x0 + 20, y1 - y0 + 20
  end
  if o.type == "rope" then
    local x2, y2 = o.x2 or o.x, o.y2 or o.y
    return math.min(o.x, x2) - 6, math.min(o.y, y2) - 6, math.abs(x2 - o.x) + 12, math.abs(y2 - o.y) + 12
  end
  if o.type == "arm" then
    local l = o.length or 110
    return o.x - l, o.y - 14, l * 2, 28
  end
  if o.w then return o.x, o.y, o.w, o.h end
  local r = o.r or 18
  return o.x - r, o.y - r, r * 2, r * 2
end
Editor.objBox = objBox

local function centreOf(o)
  local x, y, w, h = objBox(o)
  return x + w / 2, y + h / 2
end

local function blankMap()
  return {
    name = "New Map",
    spawns = { { 288, 696 }, { 1248, 696 }, { 480, 696 }, { 1056, 696 } },
    rects = {},
    objects = { { type = "block", id = 1, material = "stone", x = 144, y = 744, w = 1248, h = 48 } },
    custom = true,
  }
end

-- opts: { map = existing map (edited as a copy), returnTo = screen }
function Editor.new(opts)
  opts = opts or {}
  local src = opts.map
  local m = src and Map.parse(Map.serialize(src)) or blankMap()
  if src then
    m.id, m.builtin, m.custom, m.file, m.defaultText = src.id, src.builtin, src.custom, src.file, src.defaultText
  end
  Map.expandBlocks(m)
  local e = setmetatable({
    map = m, tab = "build", cat = 1, brush = PALETTE[1].items[1], flags = {}, gridI = 2, mirror = false,
    sel = {}, undo = {}, redo = {}, msg = nil, msgT = 0, problems = {}, dirty = false, valT = 0,
    returnTo = opts.returnTo, clipboard = nil,
  }, Editor)
  e:fitView()
  e:validate()
  return e
end

function Editor:fitView()
  local vw, vh = app.W, app.H - TOP_H - BAR_H
  self.zoom = math.min(vw / (AW + 40), vh / (AH + 40))
  self.camX, self.camY = AW / 2, AH / 2
end

function Editor:toArena(mx, my)
  local vx, vy = app.W / 2, TOP_H + (app.H - TOP_H - BAR_H) / 2
  return (mx - vx) / self.zoom + self.camX, (my - vy) / self.zoom + self.camY
end

local function inView(mx, my)
  return my >= TOP_H and my <= app.H - BAR_H
end

function Editor:say(text, bad)
  self.msg, self.msgT, self.msgBad = text, 4, bad
end

function Editor:gridSize()
  return GRIDS[self.gridI]
end

function Editor:snap(v)
  local g = self:gridSize()
  return round(v / g) * g
end

function Editor:newId()
  local n = 0
  for _, o in ipairs(self.map.objects) do n = math.max(n, o.id or 0) end
  return n + 1
end

---------------------------------------------------------------- undo
function Editor:push()
  self.undo[#self.undo + 1] = Map.serialize(self.map)
  if #self.undo > MAX_UNDO then table.remove(self.undo, 1) end
  self.redo = {}
  self.dirty = true
end

-- Something changed: check the map again once things settle.
function Editor:touch()
  self.dirty = true
  self.valT = 0.4
end

local function restore(self, text)
  local keep = self.map
  local m = Map.parse(text)
  m.id, m.builtin, m.custom, m.file, m.defaultText = keep.id, keep.builtin, keep.custom, keep.file, keep.defaultText
  self.map = m
  self.sel = {}
  self:touch()
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
local function hitObject(o, x, y)
  if o.type == "rope" then
    return Objects.segDist(x, y, o.x, o.y, o.x2 or o.x, o.y2 or o.y) < 8
  end
  if o.type == "rail" and o.path then
    for i = 1, #o.path - 1 do
      if Objects.segDist(x, y, o.path[i][1], o.path[i][2], o.path[i + 1][1], o.path[i + 1][2]) < 10 then return true end
    end
    return false
  end
  local bx, by, bw, bh = objBox(o)
  if o.rot and o.rot ~= 0 then
    local cx, cy = bx + bw / 2, by + bh / 2
    local c, s = math.cos(-o.rot), math.sin(-o.rot)
    local dx, dy = x - cx, y - cy
    x, y = cx + dx * c - dy * s, cy + dx * s + dy * c
  end
  return x >= bx - 3 and x <= bx + bw + 3 and y >= by - 3 and y <= by + bh + 3
end

-- What's under the point: spawns first, then things drawn on top.
function Editor:itemAt(x, y)
  local m = self.map
  for i = 4, 1, -1 do
    local s = m.spawns[i]
    if (x - s[1]) ^ 2 + (y - s[2]) ^ 2 < 22 * 22 then return { kind = "spawn", ref = s, index = i } end
  end
  -- Small things before big ones, so a saw on a block can be picked.
  local best, bestArea
  for i = #m.objects, 1, -1 do
    local o = m.objects[i]
    if hitObject(o, x, y) then
      local _, _, bw, bh = objBox(o)
      local area = bw * bh
      if not best or area < bestArea then best, bestArea = o, area end
    end
  end
  return best and { kind = "obj", ref = best } or nil
end

function Editor:isSelected(ref)
  for _, it in ipairs(self.sel) do
    if it.ref == ref then return true end
  end
  return false
end

-- Selecting one member of a group selects the group.
function Editor:select(item, add)
  if not add then self.sel = {} end
  if not item then return end
  if not self:isSelected(item.ref) then self.sel[#self.sel + 1] = item end
  local g = item.kind == "obj" and item.ref.group
  if g then
    for _, o in ipairs(self.map.objects) do
      if o.group == g and not self:isSelected(o) then self.sel[#self.sel + 1] = { kind = "obj", ref = o } end
    end
  end
end

function Editor:selectedObjects()
  local out = {}
  for _, it in ipairs(self.sel) do
    if it.kind == "obj" then out[#out + 1] = it.ref end
  end
  return out
end

local MIRROR_DIR = { left = "right", right = "left" }

function Editor:mirrorCopy(o)
  local c = deepcopy(o)
  c.id = self:newId()
  local bx, _, bw = objBox(o)
  if c.type == "rope" then
    c.x, c.x2 = AW - c.x, AW - c.x2
    c.target, c.from = nil, nil
  elseif c.w then
    c.x = AW - c.x - c.w
  else
    c.x = AW - c.x
  end
  if c.dir and MIRROR_DIR[c.dir] then c.dir = MIRROR_DIR[c.dir] end
  if c.path then
    for _, p in ipairs(c.path) do p[1] = AW - p[1] end
  end
  if c.spin then c.spin = -c.spin end
  if c.conveyor and c.speed then c.speed = -c.speed end
  if c.rot then c.rot = -c.rot end
  c.parent = nil
  if math.abs(bx + bw / 2 - AW / 2) > 2 then table.insert(self.map.objects, c) end
end

function Editor:addObject(o)
  o.id = o.id or self:newId()
  table.insert(self.map.objects, o)
  if self.mirror then self:mirrorCopy(o) end
  return o
end

function Editor:removeObject(o)
  local list = self.map.objects
  for i = #list, 1, -1 do
    if list[i] == o then table.remove(list, i) break end
  end
  if o.id then
    for i = #list, 1, -1 do
      local r = list[i]
      if r.parent == o.id then r.parent = nil end
      if r.type == "rope" and (r.target == o.id or r.from == o.id) then table.remove(list, i) end
    end
  end
end

function Editor:deleteSel()
  local objs = self:selectedObjects()
  if #objs == 0 then return end
  self:push()
  for _, o in ipairs(objs) do self:removeObject(o) end
  self.sel = {}
  self:touch()
end

-- Copies of objects with fresh ids; links inside the copied set follow along.
function Editor:cloneSet(objs, dx, dy)
  local nextId = self:newId()
  local map = {}
  for _, o in ipairs(objs) do
    map[o.id or -1] = nextId
    nextId = nextId + 1
  end
  local out = {}
  for _, o in ipairs(objs) do
    local c = deepcopy(o)
    c.id = map[o.id or -1]
    c.x, c.y = c.x + dx, c.y + dy
    if c.x2 then c.x2, c.y2 = c.x2 + dx, c.y2 + dy end
    if c.path then for _, p in ipairs(c.path) do p[1], p[2] = p[1] + dx, p[2] + dy end end
    c.parent = c.parent and map[c.parent] or nil
    c.target = c.target and map[c.target] or nil
    c.from = c.from and map[c.from] or nil
    c.group = nil
    table.insert(self.map.objects, c)
    out[#out + 1] = { kind = "obj", ref = c }
  end
  return out
end

function Editor:copySel()
  local objs = self:selectedObjects()
  if #objs == 0 then return end
  self.clipboard = deepcopy(objs)
  self:say("Copied " .. #objs)
end

function Editor:paste()
  if not self.clipboard then return end
  self:push()
  local mx, my = app.mouse()
  local x, y = self:toArena(mx, my)
  local cx, cy = centreOf(self.clipboard[1])
  self.sel = self:cloneSet(self.clipboard, self:snap(x - cx), self:snap(y - cy))
  self:touch()
end

function Editor:duplicateSel()
  local objs = self:selectedObjects()
  if #objs == 0 then return end
  self:push()
  self.sel = self:cloneSet(objs, self:gridSize() * 2, self:gridSize())
  self:touch()
end

function Editor:groupSel()
  local objs = self:selectedObjects()
  if #objs == 0 then return end
  self:push()
  if #objs == 1 or objs[1].group then
    for _, o in ipairs(objs) do o.group = nil end
    self:say("Ungrouped")
  else
    local g = 0
    for _, o in ipairs(self.map.objects) do g = math.max(g, o.group or 0) end
    for _, o in ipairs(objs) do o.group = g + 1 end
    self:say("Grouped " .. #objs)
  end
  self.dirty = true
end

function Editor:mirrorSel()
  local objs = self:selectedObjects()
  if #objs == 0 then return end
  self:push()
  for _, o in ipairs(objs) do self:mirrorCopy(o) end
  self:touch()
end

-- Move every link that follows an object: tied rope ends and things attached to it.
local function moveBy(self, o, dx, dy, moved)
  if moved[o] then return end
  moved[o] = true
  o.x, o.y = o.x + dx, o.y + dy
  if o.x2 then o.x2, o.y2 = o.x2 + dx, o.y2 + dy end
  if o.path then for _, p in ipairs(o.path) do p[1], p[2] = p[1] + dx, p[2] + dy end end
  if o.id then
    for _, c in ipairs(self.map.objects) do
      if c.parent == o.id then moveBy(self, c, dx, dy, moved) end
      if c.type == "rope" and not moved[c] then
        if c.target == o.id then c.x2, c.y2 = c.x2 + dx, c.y2 + dy end
        if c.from == o.id then c.x, c.y = c.x + dx, c.y + dy end
      end
    end
  end
end

function Editor:nudge(dx, dy)
  if #self.sel == 0 then return end
  self:push()
  local moved = {}
  for _, it in ipairs(self.sel) do
    if it.kind == "spawn" then
      it.ref[1], it.ref[2] = it.ref[1] + dx, it.ref[2] + dy
    else
      moveBy(self, it.ref, dx, dy, moved)
    end
  end
  self:touch()
end

-- Turn the selection around its centre.
function Editor:rotateSel(angle)
  local objs = self:selectedObjects()
  if #objs == 0 then return end
  self:push()
  local cx, cy = 0, 0
  for _, o in ipairs(objs) do
    local x, y = centreOf(o)
    cx, cy = cx + x / #objs, cy + y / #objs
  end
  local c, s = math.cos(angle), math.sin(angle)
  for _, o in ipairs(objs) do
    if #objs > 1 then
      local x, y = centreOf(o)
      local dx, dy = x - cx, y - cy
      moveBy(self, o, round(cx + dx * c - dy * s - x), round(cy + dx * s + dy * c - y), {})
    end
    self:setRot(o, (o.rot or 0) + angle)
  end
  self:touch()
end

function Editor:setRot(o, angle)
  if o.type == "arm" then
    o.phase = (angle % (math.pi * 2))
    return
  end
  if o.type == "rope" or o.type == "rail" then return end
  angle = (angle + math.pi) % (math.pi * 2) - math.pi
  o.rot = math.abs(angle) > 0.001 and math.floor(angle * 1000 + 0.5) / 1000 or nil
end

function Editor:scaleSel(k)
  local objs = self:selectedObjects()
  if #objs == 0 then return end
  self:push()
  for _, o in ipairs(objs) do
    if o.w then
      local cx, cy = o.x + o.w / 2, o.y + o.h / 2
      o.w, o.h = math.max(4, round(o.w * k)), math.max(4, round(o.h * k))
      o.x, o.y = round(cx - o.w / 2), round(cy - o.h / 2)
    elseif o.r then
      o.r = math.max(6, round(o.r * k))
    elseif o.type == "arm" or o.type == "flame" then
      o.length = math.max(30, round((o.length or 110) * k))
    end
  end
  self:touch()
end

function Editor:openProperties()
  local objs = self:selectedObjects()
  if #objs == 0 then return end
  local same = {}
  for _, o in ipairs(objs) do
    if o.type == objs[1].type then same[#same + 1] = o end
  end
  Popup.open(self, same)
end

---------------------------------------------------------------- placing
function Editor:makeFromBrush(brush)
  local o = deepcopy(brush.def)
  o.x, o.y = 0, 0
  for k, v in pairs(Objects.DEFAULTS[o.type] or {}) do
    if o[k] == nil then o[k] = deepcopy(v) end
  end
  if o.type == "block" then
    local f = self.flags
    if f.physics then o.physics = true end
    if f.breakable and (o.hp or 0) <= 0 then o.hp = Objects.MATERIALS[o.material].hp end
    if f.oneway then o.oneway, o.h = true, math.min(o.h, 18) end
    if f.crumble then o.crumble, o.delay, o.back = true, 0.5, 4 end
    if f.conveyor then o.conveyor, o.speed = true, 160 end
  end
  if self.flags.anchored and Physics.isLoose(o) then o.anchored, o.anchorType = true, "fixed" end
  return o
end

local function brushSize(o)
  local _, _, w, h = objBox(o)
  return w, h
end

-- Put a brush's object with its centre on the arena point, on the grid.
function Editor:placeAt(brush, x, y)
  local o = self:makeFromBrush(brush)
  local w, h = brushSize(o)
  if o.w then
    o.x, o.y = self:snap(x - w / 2), self:snap(y - h / 2)
  else
    o.x, o.y = self:snap(x), self:snap(y)
  end
  return self:addObject(o)
end

function Editor:spotTaken(brush, o)
  for _, c in ipairs(self.map.objects) do
    if c ~= o and c.type == o.type and c.material == o.material and c.x == o.x and c.y == o.y then return true end
  end
  return false
end

function Editor:finishRail()
  local r = self.railing
  self.railing = nil
  if r and (not r.path or #r.path < 2) then
    self:removeObject(r)
    self:say("A rail needs at least two points", true)
  elseif r then
    self:say("Rail placed. Use Attach to put objects on it")
  end
  self:touch()
end

function Editor:cancelTools()
  if self.railing then self:finishRail() end
  self.ropeFrom, self.attachChild, self.drag = nil, nil, nil
end

function Editor:buildClick(x, y, sx, sy)
  local brush, m = self.brush, self.map
  if brush.spawn then
    self:push()
    m.spawns[brush.spawn][1], m.spawns[brush.spawn][2] = sx, sy
    self:touch()
  elseif brush.tool == "rope" then
    local item = self:itemAt(x, y)
    local tied = item and item.kind == "obj" and item.ref.type ~= "rope" and item.ref or nil
    if not self.ropeFrom then
      self.ropeFrom = { x = tied and centreOf(tied) or sx, y = tied and select(2, centreOf(tied)) or sy, obj = tied }
      self:say("Now click where it ends: an object, or empty space to pin it")
    else
      self:push()
      local a = self.ropeFrom
      local ex, ey = sx, sy
      if tied then ex, ey = centreOf(tied) end
      self:addObject({ type = "rope", x = a.x, y = a.y, x2 = ex, y2 = ey, from = a.obj and a.obj.id or nil,
        target = tied and tied.id or nil, pin2 = not tied or nil, segHp = 60, slack = 1 })
      self.ropeFrom = nil
      self:say("Rope added")
      self:touch()
    end
  elseif brush.tool == "rail" then
    if not self.railing then
      self:push()
      local r = self:addObject({ type = "rail", x = sx, y = sy, speed = 120, force = 1, path = { { sx, sy } } })
      self.railing = r
      self:say("Click to add points, right click or Enter to finish")
    else
      table.insert(self.railing.path, { sx, sy })
    end
  elseif brush.tool == "attach" then
    local item = self:itemAt(x, y)
    if not self.attachChild then
      if item and item.kind == "obj" and item.ref.type ~= "rope" and item.ref.type ~= "rail" and item.ref.type ~= "arm" then
        self.attachChild = item.ref
        self:say("Now click the arm or rail to attach it to")
      else
        self:say("Click the object you want to attach first", true)
      end
    else
      if item and item.kind == "obj" and (item.ref.type == "arm" or item.ref.type == "rail") then
        self:push()
        self.attachChild.parent = item.ref.id
        self:say("Attached")
        self:touch()
      else
        self:say("That isn't an arm or a rail", true)
      end
      self.attachChild = nil
    end
  elseif brush.def then
    self:push()
    local shift = love.keyboard.isDown("lshift", "rshift")
    local o = self:placeAt(brush, x, y)
    if shift and o.type == "block" then
      self.drag = { mode = "stretch", obj = o, x0 = o.x, y0 = o.y, minW = o.w, minH = o.h }
    else
      local w, h = brushSize(o)
      self.drag = { mode = "paint", brush = brush, x0 = o.x, y0 = o.y, stepX = math.max(w, self:gridSize()), stepY = math.max(h, self:gridSize()),
        round = o.w == nil, cells = { ["0:0"] = true } }
    end
    self:touch()
  end
end

---------------------------------------------------------------- handles
local function handles(self)
  if #self.sel ~= 1 or self.sel[1].kind ~= "obj" then return nil end
  local o = self.sel[1].ref
  local bx, by, bw, bh = objBox(o)
  local cx, cy = bx + bw / 2, by + bh / 2
  local rot = o.rot or 0
  local c, s = math.cos(rot), math.sin(rot)
  local function world(dx, dy) return cx + dx * c - dy * s, cy + dx * s + dy * c end
  local out = {}
  if o.w or o.r or o.type == "arm" or o.type == "flame" then
    local hx, hy = world(bw / 2, bh / 2)
    out.scale = { hx, hy }
    local rx, ry = world(0, -bh / 2 - 26)
    if o.type ~= "arm" then out.rotate = { rx, ry } end
  end
  if o.type == "crusher" then out.travel = { o.x + o.w / 2, o.y + o.h + (o.travel or 200) } end
  if o.type == "rail" and o.path then out.path = o.path end
  if o.type == "rope" then
    if not o.from then out.ropeA = { o.x, o.y } end
    if not o.target then out.ropeB = { o.x2, o.y2 } end
  end
  return out, o
end

local function near(x, y, p, r) return p and (x - p[1]) ^ 2 + (y - p[2]) ^ 2 < r * r end

---------------------------------------------------------------- input
function Editor:keypressed(key)
  if ui.capturing then return end
  local ctrl = love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
  if self.typing then
    if key == "escape" or key == "return" or key == "kpenter" then
      self.typing = false
      self:touch()
    end
    return
  end
  if self.live then
    if key == "escape" or key == "p" then self:stopLive() end
    return
  end
  if key == "escape" then
    if self.railing or self.ropeFrom or self.attachChild or self.drag then
      self:cancelTools()
    elseif #self.sel > 0 then
      self.sel = {}
    else
      self:exit()
    end
  elseif key == "return" and self.railing then self:finishRail()
  elseif ctrl and key == "z" then self:doUndo()
  elseif ctrl and key == "y" then self:doRedo()
  elseif ctrl and key == "s" then self:save()
  elseif ctrl and key == "d" then self:duplicateSel()
  elseif ctrl and key == "c" then self:copySel()
  elseif ctrl and key == "v" then self:paste()
  elseif ctrl and key == "g" then self:groupSel()
  elseif key == "delete" or key == "backspace" then self:deleteSel()
  elseif key == "g" then self.gridI = self.gridI % #GRIDS + 1
  elseif key == "m" then self.mirror = not self.mirror
  elseif key == "p" then self:startLive()
  elseif key == "e" then self:openProperties()
  elseif key == "q" then self:rotateSel(-math.pi / 12)
  elseif key == "r" then self:rotateSel(math.pi / 12)
  elseif key == "1" then self.tab = "build"
  elseif key == "2" then self.tab = "edit"
  elseif key == "3" then self.tab = "delete"
  elseif key == "left" or key == "right" or key == "up" or key == "down" then
    local step = self:gridSize()
    self:nudge(key == "left" and -step or key == "right" and step or 0, key == "up" and -step or key == "down" and step or 0)
  end
end

function Editor:wheelmoved(_, dy)
  local mx, my = app.mouse()
  if not inView(mx, my) then return end
  local ax, ay = self:toArena(mx, my)
  self.zoom = math.max(0.25, math.min(4, self.zoom * (dy > 0 and 1.15 or 1 / 1.15)))
  local nx, ny = self:toArena(mx, my)
  self.camX, self.camY = self.camX + ax - nx, self.camY + ay - ny
end

function Editor:mousepressed(mx, my, button)
  if self.live or not inView(mx, my) then return end
  if button == 2 or button == 3 then
    self.panning = { mx = mx, my = my, camX = self.camX, camY = self.camY, moved = false, button = button }
    return
  end
  if button ~= 1 then return end
  local x, y = self:toArena(mx, my)
  local sx, sy = self:snap(x), self:snap(y)

  if self.tab == "build" then
    self:buildClick(x, y, sx, sy)
  elseif self.tab == "delete" then
    self.drag = { mode = "erase", x0 = x, y0 = y }
  else
    -- Handles of the selection come first.
    local h, o = handles(self)
    if h then
      local r = 12 / self.zoom
      if near(x, y, h.rotate, r) then
        self:push()
        self.drag = { mode = "rotate", obj = o }
        return
      elseif near(x, y, h.scale, r) then
        self:push()
        self.drag = { mode = "scale", obj = o }
        return
      elseif near(x, y, h.travel, r) then
        self:push()
        self.drag = { mode = "travel", obj = o }
        return
      elseif near(x, y, h.ropeA, r) then
        self:push()
        self.drag = { mode = "ropeEnd", obj = o, a = true }
        return
      elseif near(x, y, h.ropeB, r) then
        self:push()
        self.drag = { mode = "ropeEnd", obj = o }
        return
      elseif h.path then
        for i, p in ipairs(h.path) do
          if near(x, y, p, r) then
            self:push()
            self.drag = { mode = "waypoint", point = p, obj = o, index = i }
            return
          end
        end
      end
    end
    local item = self:itemAt(x, y)
    local shift = love.keyboard.isDown("lshift", "rshift")
    if item then
      local now = love.timer.getTime()
      local again = self.lastClick and self.lastClick.ref == item.ref and now - self.lastClick.t < 0.3
      self.lastClick = { ref = item.ref, t = now }
      if not self:isSelected(item.ref) then self:select(item, shift) end
      if again and item.kind == "obj" then
        self:openProperties()
        return
      end
      self:push()
      local first = self.sel[1]
      local ix = first.kind == "spawn" and first.ref[1] or first.ref.x
      local iy = first.kind == "spawn" and first.ref[2] or first.ref.y
      self.drag = { mode = "move", x0 = x, y0 = y, ix = ix, iy = iy, last = { dx = 0, dy = 0 }, changed = false }
    else
      if not shift then self.sel = {} end
      self.drag = { mode = "box", x0 = x, y0 = y }
    end
  end
end

function Editor:boxItems(x0, y0, x1, y1)
  local ax, ay, bx, by = math.min(x0, x1), math.min(y0, y1), math.max(x0, x1), math.max(y0, y1)
  local out = {}
  for _, o in ipairs(self.map.objects) do
    local cx, cy = centreOf(o)
    if cx >= ax and cx <= bx and cy >= ay and cy <= by then out[#out + 1] = { kind = "obj", ref = o } end
  end
  return out
end

function Editor:mousereleased(mx, my, button)
  local p = self.panning
  if p and (button == 2 or button == 3) then
    self.panning = nil
    if not p.moved and button == 2 then self:cancelTools() end
    return
  end
  local d = self.drag
  if not d or button ~= 1 then return end
  self.drag = nil
  local x, y = self:toArena(mx, my)
  if d.mode == "box" then
    for _, it in ipairs(self:boxItems(d.x0, d.y0, x, y)) do self:select(it, true) end
  elseif d.mode == "erase" then
    local list
    if math.abs(x - d.x0) < 4 and math.abs(y - d.y0) < 4 then
      local item = self:itemAt(x, y)
      list = item and item.kind == "obj" and { item } or {}
    else
      list = self:boxItems(d.x0, d.y0, x, y)
    end
    if #list > 0 then
      self:push()
      for _, it in ipairs(list) do self:removeObject(it.ref) end
      self.sel = {}
      self:touch()
    end
  elseif d.mode == "move" and not d.changed then
    table.remove(self.undo)
  else
    self:touch()
  end
end

function Editor:updateDrag(x, y)
  local d = self.drag
  if not d then return end
  if d.mode == "paint" then
    local kx = round((x - (d.x0 + (d.round and 0 or d.stepX / 2))) / d.stepX)
    local ky = round((y - (d.y0 + (d.round and 0 or d.stepY / 2))) / d.stepY)
    local key = kx .. ":" .. ky
    if not d.cells[key] then
      d.cells[key] = true
      local o = self:makeFromBrush(d.brush)
      o.x, o.y = d.x0 + kx * d.stepX, d.y0 + ky * d.stepY
      if self:spotTaken(d.brush, o) then return end
      self:addObject(o)
      self:touch()
    end
  elseif d.mode == "stretch" then
    local o = d.obj
    local sx, sy = self:snap(x), self:snap(y)
    o.x, o.y = math.min(d.x0, sx), math.min(d.y0, sy)
    o.w, o.h = math.max(d.minW, math.abs(sx - d.x0)), math.max(d.minH, math.abs(sy - d.y0))
    self:touch()
  elseif d.mode == "move" then
    local dx, dy = self:snap(d.ix + x - d.x0) - d.ix, self:snap(d.iy + y - d.y0) - d.iy
    local ddx, ddy = dx - d.last.dx, dy - d.last.dy
    if ddx ~= 0 or ddy ~= 0 then
      d.changed = true
      d.last.dx, d.last.dy = dx, dy
      local moved = {}
      for _, it in ipairs(self.sel) do
        if it.kind == "spawn" then
          it.ref[1], it.ref[2] = it.ref[1] + ddx, it.ref[2] + ddy
        else
          moveBy(self, it.ref, ddx, ddy, moved)
        end
      end
      self:touch()
    end
  elseif d.mode == "scale" then
    local o = d.obj
    if o.w then
      local cx, cy = o.x + o.w / 2, o.y + o.h / 2
      local c, s = math.cos(-(o.rot or 0)), math.sin(-(o.rot or 0))
      local dx, dy = x - cx, y - cy
      local lx, ly = dx * c - dy * s, dx * s + dy * c
      o.w, o.h = math.max(4, self:snap(lx * 2)), math.max(4, self:snap(ly * 2))
      o.x, o.y = round(cx - o.w / 2), round(cy - o.h / 2)
    elseif o.r then
      o.r = math.max(6, round(math.sqrt((x - o.x) ^ 2 + (y - o.y) ^ 2) * 0.72))
    elseif o.type == "arm" or o.type == "flame" then
      o.length = math.max(30, round(math.abs(x - o.x)))
    end
    self:touch()
  elseif d.mode == "rotate" then
    local cx, cy = centreOf(d.obj)
    local a = math.atan2(y - cy, x - cx) + math.pi / 2
    if not love.keyboard.isDown("lshift", "rshift") then a = round(a / (math.pi / 12)) * (math.pi / 12) end
    self:setRot(d.obj, a)
    self:touch()
  elseif d.mode == "travel" then
    d.obj.travel = math.max(12, self:snap(y - d.obj.y - d.obj.h))
    self:touch()
  elseif d.mode == "waypoint" then
    d.point[1], d.point[2] = self:snap(x), self:snap(y)
    if d.index == 1 then d.obj.x, d.obj.y = d.point[1], d.point[2] end
    self:touch()
  elseif d.mode == "ropeEnd" then
    if d.a then d.obj.x, d.obj.y = self:snap(x), self:snap(y) else d.obj.x2, d.obj.y2 = self:snap(x), self:snap(y) end
    self:touch()
  end
end

function Editor:update(dt)
  self.msgT = math.max(0, self.msgT - dt)
  if self.live then return self:updateLive(dt) end
  if self.valT > 0 then
    self.valT = self.valT - dt
    if self.valT <= 0 and not self.drag then self:validate() elseif self.valT <= 0 then self.valT = 0.2 end
  end
  local mx, my = app.mouse()
  local p = self.panning
  if p then
    local dx, dy = mx - p.mx, my - p.my
    if math.abs(dx) + math.abs(dy) > 3 then p.moved = true end
    self.camX, self.camY = p.camX - dx / self.zoom, p.camY - dy / self.zoom
  end
  local x, y = self:toArena(mx, my)
  self:updateDrag(x, y)
end

---------------------------------------------------------------- validation
-- The map as it will be saved: plain blocks become rects again.
function Editor:exported()
  local c = Map.parse(Map.serialize(self.map))
  c.id, c.builtin, c.custom, c.file, c.defaultText = self.map.id, self.map.builtin, self.map.custom, self.map.file, self.map.defaultText
  Map.compactBlocks(c)
  return c
end

-- Problems: spawns must land on solid ground, away from hazards; there must be ground.
function Editor:validate()
  local m = self.map
  local problems = {}
  if not m.name or m.name:match("^%s*$") then problems[#problems + 1] = "The map needs a name" end
  local c = self:exported()
  local solids = 0
  for _, r in ipairs(c.rects) do if not r.oneway then solids = solids + 1 end end
  for _, o in ipairs(c.objects) do if o.type == "block" and not o.oneway then solids = solids + 1 end end
  if solids == 0 then problems[#problems + 1] = "Add at least one solid block" end
  if #c.objects > MAX_OBJECTS then problems[#problems + 1] = "Too many objects (" .. #c.objects .. " of " .. MAX_OBJECTS .. ")" end
  local World = require "game.world"
  local Input = require "core.input"
  local wasSilent = sfx.silent
  sfx.silent = true
  for i = 1, 4 do
    local s = c.spawns[i]
    local inp = Input.remote()
    inp.aim = nil
    local ok, landed, hurt, near2 = pcall(function()
      local w = World.new({ { name = "T", input = inp } }, 1, { pickFrom = 1, picksPerRound = 1, weights = {},
        rarity = {}, disabled = {}, forceMap = c, barrier = false })
      w:startRound()
      w.state = "playing"
      local p = w.players[1]
      p.x, p.y = s[1], s[2]
      local startFree = p:freeAt(p.x, p.y)
      for _ = 1, 90 do
        w.state = "playing"
        w:update(1 / 60)
      end
      local nearHazard = false
      for _, o in ipairs(w.objects) do
        if Objects.isHazard(o) then
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
      if near2 then problems[#problems + 1] = "Spawn " .. i .. " is within 120 px of a hazard" end
    end
  end
  fx.clear()
  sfx.silent = wasSilent
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
    self:say("Fix the problems shown above the toolbar before saving", true)
    return false
  end
  local c = self:exported()
  if c.builtin then
    Map.saveOverride(c)
    self:say("Saved your version of " .. c.name .. " (reset it from the map list)")
  else
    self.map.file = Map.saveCustom(c)
    self:say("Saved " .. c.name)
  end
  Map.loadAll()
  self.dirty = false
  sfx.ui("cardPick")
  return true
end

function Editor:share()
  if not self:validate() then
    self:say("Fix the problems shown above the toolbar before sharing", true)
    return
  end
  local code = Map.encodeShare(self:exported())
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
  Map.expandBlocks(m)
  self.map = m
  self.sel = {}
  self:touch()
  self:say("Imported " .. m.name .. " as a new map")
end

function Editor:test()
  local Match = require "screens.match"
  local copy = self:exported()
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

---------------------------------------------------------------- live playtest
-- The real game running in the editor's view, on a copy; stopping just throws the copy away.
function Editor:startLive()
  local World = require "game.world"
  local Input = require "core.input"
  local Cards = require "game.cards"
  local Settings = require "core.settings"
  self:cancelTools()
  self.sel = {}
  local copy = self:exported()
  copy.index = 0
  local inp = Input.keys(Settings.values.binds.p1)
  World.setSlotColors({ 1, 2, 3, 4 })
  local w = World.new({ { name = "You", input = inp } }, 999, { pickFrom = 1, picksPerRound = 1,
    weights = Cards.DEFAULT_RULES.weights, rarity = {}, disabled = {}, forceMap = copy, barrier = false, practice = true })
  w:startRound()
  w.state = "playing"
  self.live = { world = w, input = inp, respawn = 0 }
  fx.clear()
end

function Editor:stopLive()
  self.live = nil
  fx.clear()
end

function Editor:updateLive(dt)
  local L, Input = self.live, require "core.input"
  local w = L.world
  local p = w.players[1]
  Input.poll(L.input, false, p and p.x, p and p.y, 0, 0)
  w.state = "playing"
  w:update(math.min(dt, 1 / 30))
  fx.update(dt)
  if p.dead then
    L.respawn = L.respawn + dt
    if L.respawn > 0.8 then
      L.respawn = 0
      local s = w.map.spawns[1]
      p:spawn(s[1], s[2], 1, w)
    end
  end
end

---------------------------------------------------------------- drawing
local function drawOutline(o, pad, zoom)
  local bx, by, bw, bh = objBox(o)
  local cx, cy = bx + bw / 2, by + bh / 2
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.rotate(o.rot or 0)
  love.graphics.setLineWidth(2 / zoom)
  love.graphics.rectangle("line", -bw / 2 - pad, -bh / 2 - pad, bw + pad * 2, bh + pad * 2)
  love.graphics.pop()
end

function Editor:drawWorld()
  local m = self.map
  love.graphics.setColor(0.07, 0.07, 0.1)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local vx, vy = app.W / 2, TOP_H + (app.H - TOP_H - BAR_H) / 2
  love.graphics.push()
  love.graphics.translate(vx, vy)
  love.graphics.scale(self.zoom, self.zoom)
  love.graphics.translate(-self.camX, -self.camY)

  love.graphics.setColor(0.1, 0.1, 0.15)
  love.graphics.rectangle("fill", 0, 0, AW, AH)

  local L = self.live
  if L then
    local w = L.world
    Map.draw(w.map, true)
    Objects.draw(w.objects, w.effects)
    for _, b in ipairs(w.bullets) do b:draw() end
    for _, p in ipairs(w.players) do p:draw() end
    fx.draw()
    love.graphics.pop()
    return
  end

  local g = self:gridSize()
  if g >= 12 then
    love.graphics.setColor(1, 1, 1, 0.05)
    love.graphics.setLineWidth(1 / self.zoom)
    for gx = 0, AW, g do love.graphics.line(gx, 0, gx, AH) end
    for gy = 0, AH, g do love.graphics.line(0, gy, AW, gy) end
  end
  if self.mirror then
    love.graphics.setColor(0.4, 0.8, 1, 0.35)
    love.graphics.setLineWidth(2 / self.zoom)
    love.graphics.line(AW / 2, 0, AW / 2, AH)
  end
  love.graphics.setColor(1, 1, 1, 0.18)
  love.graphics.setLineWidth(2 / self.zoom)
  love.graphics.rectangle("line", 0, 0, AW, AH)

  Map.draw(m, true)
  local list = Objects.build(m)
  Objects.draw(list, {})

  -- Links: what's attached to what, and crusher strokes.
  for i, o in ipairs(m.objects) do
    local inst = list[i]
    if inst and inst.parentObj then
      local px, py = inst.parentObj.x, inst.parentObj.y
      local cx, cy = centreOf(o)
      love.graphics.setColor(0.4, 0.9, 1, 0.6)
      love.graphics.setLineWidth(2 / self.zoom)
      love.graphics.line(cx, cy, px, py)
      love.graphics.circle("fill", cx, cy, 3 / self.zoom)
    end
    if o.type == "crusher" then
      love.graphics.setColor(1, 0.8, 0.3, 0.35)
      love.graphics.rectangle("line", o.x, o.y + (o.travel or 200), o.w, o.h)
    end
    if o.group then
      love.graphics.setColor(0.55, 0.9, 0.6, 0.3)
      drawOutline(o, 2, self.zoom)
    end
  end

  local mx, my = app.mouse()
  local ax, ay = self:toArena(mx, my)
  if self.ropeFrom then
    love.graphics.setColor(0.72, 0.6, 0.42, 0.7)
    love.graphics.setLineWidth(3 / self.zoom)
    love.graphics.line(self.ropeFrom.x, self.ropeFrom.y, ax, ay)
  end
  if self.railing and self.railing.path[1] then
    local last = self.railing.path[#self.railing.path]
    love.graphics.setColor(0.6, 0.65, 0.85, 0.6)
    love.graphics.setLineWidth(3 / self.zoom)
    love.graphics.line(last[1], last[2], self:snap(ax), self:snap(ay))
  end
  if self.attachChild then
    local cx, cy = centreOf(self.attachChild)
    love.graphics.setColor(0.4, 0.9, 1, 0.8)
    love.graphics.setLineWidth(2 / self.zoom)
    love.graphics.line(cx, cy, ax, ay)
  end

  -- Ghost of what the brush would place.
  if self.tab == "build" and not self.drag and inView(mx, my) and self.brush.def then
    local o = self:makeFromBrush(self.brush)
    local w, h = brushSize(o)
    if o.w then
      o.x, o.y = self:snap(ax - w / 2), self:snap(ay - h / 2)
    else
      o.x, o.y = self:snap(ax), self:snap(ay)
    end
    local ghost = Objects.build({ name = "g", rects = {}, objects = { o }, channels = m.channels })
    love.graphics.setColor(1, 1, 1, 0.5)
    Objects.draw(ghost, {})
  end

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

  love.graphics.setColor(1, 0.8, 0.2)
  for _, it in ipairs(self.sel) do
    if it.kind == "spawn" then
      love.graphics.circle("line", it.ref[1], it.ref[2], 26)
    else
      drawOutline(it.ref, 3, self.zoom)
    end
  end
  local h = self.tab == "edit" and handles(self)
  if h then
    local size = 7 / self.zoom
    if h.scale then
      love.graphics.setColor(1, 0.8, 0.2)
      love.graphics.rectangle("fill", h.scale[1] - size, h.scale[2] - size, size * 2, size * 2)
    end
    if h.rotate then
      love.graphics.setColor(0.5, 0.9, 1)
      love.graphics.circle("fill", h.rotate[1], h.rotate[2], size)
    end
    if h.travel then
      love.graphics.setColor(1, 0.55, 0.2)
      love.graphics.circle("fill", h.travel[1], h.travel[2], size)
    end
    for _, key in ipairs({ "ropeA", "ropeB" }) do
      if h[key] then
        love.graphics.setColor(0.9, 0.75, 0.5)
        love.graphics.circle("fill", h[key][1], h[key][2], size)
      end
    end
    if h.path then
      love.graphics.setColor(0.7, 0.8, 1)
      for _, p in ipairs(h.path) do love.graphics.circle("fill", p[1], p[2], size) end
    end
  end

  local d = self.drag
  if d and (d.mode == "box" or d.mode == "erase") then
    local c = d.mode == "erase" and { 1, 0.3, 0.25 } or { 0.5, 0.8, 1 }
    love.graphics.setColor(c[1], c[2], c[3], 0.15)
    love.graphics.rectangle("fill", math.min(d.x0, ax), math.min(d.y0, ay), math.abs(ax - d.x0), math.abs(ay - d.y0))
    love.graphics.setColor(c)
    love.graphics.setLineWidth(1.5 / self.zoom)
    love.graphics.rectangle("line", math.min(d.x0, ax), math.min(d.y0, ay), math.abs(ax - d.x0), math.abs(ay - d.y0))
  end
  love.graphics.pop()
end

local thumbs = {}
local function thumb(item)
  if thumbs[item] ~= nil then return thumbs[item] end
  local list
  if item.def then
    local o = deepcopy(item.def)
    for k, v in pairs(Objects.DEFAULTS[o.type] or {}) do
      if o[k] == nil then o[k] = deepcopy(v) end
    end
    o.x, o.y = 0, 0
    o.physics = nil
    list = Objects.build({ name = "t", rects = {}, objects = { o } })
    list[1].s = (o.type == "flame" or o.type == "laser") and 2 or list[1].s
    if o.type == "crusher" then list[1].top = list[1].y + 380 end -- only a stub of its long shaft
  end
  thumbs[item] = list or false
  return thumbs[item]
end

local function drawThumb(item, x, y, size)
  local list = thumb(item)
  love.graphics.push()
  if list then
    local o = list[1]
    local bx, by, bw, bh = objBox(o)
    if o.type == "flame" then bx, by, bw, bh = -24, -(o.length + 12), 48, o.length + 24 end
    if o.type == "crusher" or o.type == "fan" then bh = math.min(bh, 120) end
    local k = math.min((size - 12) / math.max(1, bw), (size - 12) / math.max(1, bh), 1)
    love.graphics.translate(x + size / 2, y + size / 2)
    love.graphics.scale(k, k)
    love.graphics.translate(-(bx + bw / 2), -(by + bh / 2))
    Objects.draw(list, {})
  else
    local cx, cy = x + size / 2, y + size / 2
    if item.spawn then
      local c = require("game.world").COLORS[item.spawn]
      love.graphics.setColor(c)
      love.graphics.setLineWidth(3)
      love.graphics.circle("line", cx, cy, size * 0.3)
      love.graphics.setFont(app.fonts.med)
      love.graphics.printf(tostring(item.spawn), x, cy - 11, size, "center")
    elseif item.tool == "rope" then
      love.graphics.setColor(0.72, 0.6, 0.42)
      love.graphics.setLineWidth(3)
      love.graphics.line(cx - 14, cy - 14, cx, cy + 6, cx + 14, cy - 10)
    elseif item.tool == "rail" then
      love.graphics.setColor(0.55, 0.58, 0.68)
      love.graphics.setLineWidth(4)
      love.graphics.line(cx - 18, cy + 8, cx - 4, cy - 8, cx + 18, cy - 8)
      love.graphics.setColor(0.8, 0.82, 0.92)
      love.graphics.circle("fill", cx - 4, cy - 8, 5)
    elseif item.tool == "attach" then
      love.graphics.setColor(0.4, 0.9, 1)
      love.graphics.setLineWidth(3)
      love.graphics.circle("line", cx - 9, cy, 7)
      love.graphics.circle("line", cx + 9, cy, 7)
    end
  end
  love.graphics.pop()
end

function Editor:drawBuild(x, y, w)
  local catW = 92
  for i, c in ipairs(PALETTE) do
    if ui.button(c.name, x + (i - 1) * (catW + 4), y, catW, 24, { font = app.fonts.small, color = self.cat == i and ui.ACCENT or nil }) then
      self.cat = i
      self:cancelTools()
    end
  end
  if self.cat == 1 then
    local fx0 = x + #PALETTE * (catW + 4) + 12
    local fw = (w - (fx0 - x) - 5 * 4) / #FLAGS
    for i, f in ipairs(FLAGS) do
      local on = self.flags[f[1]]
      if ui.button(f[2], fx0 + (i - 1) * (fw + 4), y, fw, 24, { font = app.fonts.tiny, color = on and { 0.4, 1, 0.55 } or nil }) then
        self.flags[f[1]] = not on or nil
      end
    end
  end
  local items = PALETTE[self.cat].items
  local size = 78
  for i, item in ipairs(items) do
    local ix = x + (i - 1) * (size + 6)
    local iy = y + 30
    if ui.button("", ix, iy, size, size, { font = app.fonts.tiny, color = self.brush == item and ui.ACCENT or nil }) then
      self.brush = item
      self:cancelTools()
    end
    drawThumb(item, ix, iy - 2, size - 14)
    love.graphics.setColor(1, 1, 1, 0.75)
    ui.printFit(item.name, app.fonts.tiny, ix + 3, iy + size - 17, size - 6, "center")
  end
end

function Editor:drawEdit(x, y, w)
  local n = #self.sel
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.print(n == 0 and "Nothing selected: click something, or drag a box" or (n .. " selected"), x, y + 2)
  local rows = {
    { { "Edit Object (E)", function() self:openProperties() end }, { "Copy", function() self:copySel() end },
      { "Paste", function() self:paste() end }, { "Duplicate", function() self:duplicateSel() end },
      { "Group / ungroup", function() self:groupSel() end }, { "Mirror copy", function() self:mirrorSel() end } },
    { { "Rotate -15", function() self:rotateSel(-math.pi / 12) end }, { "Rotate +15", function() self:rotateSel(math.pi / 12) end },
      { "Rotate 90", function() self:rotateSel(math.pi / 2) end }, { "Smaller", function() self:scaleSel(1 / 1.25) end },
      { "Bigger", function() self:scaleSel(1.25) end }, { "Delete", function() self:deleteSel() end } },
  }
  local bw = (w - 5 * 6) / 6
  for r, row in ipairs(rows) do
    for c, b in ipairs(row) do
      if ui.button(b[1], x + (c - 1) * (bw + 6), y + 24 + (r - 1) * 44, bw, 38, { font = app.fonts.small, disabled = n == 0 and b[1] ~= "Paste" }) then
        b[2]()
      end
    end
  end
end

function Editor:drawDelete(x, y, w)
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.7)
  love.graphics.print("Click something to remove it, or drag a box over several", x, y + 10)
  if ui.button("Clear level", x, y + 50, 180, 38, { font = app.fonts.med }) then
    local Confirm = require "screens.confirm"
    Confirm.ask("Clear level?", "Everything except the spawns will be removed.", function()
      self:push()
      self.map.objects = {}
      self.sel = {}
      self:touch()
    end, { yes = "Clear", danger = true })
  end
end

function Editor:drawBar()
  local y0 = app.H - BAR_H
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, y0, app.W, BAR_H)
  love.graphics.setColor(1, 1, 1, 0.12)
  love.graphics.rectangle("fill", 0, y0, app.W, 2)
  if self.live then
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.printf("Playtesting with live physics. Your Player 1 controls work. Nothing you do here changes the map.", 0, y0 + 26, app.W, "center")
    if ui.button("Stop", app.W / 2 - 90, y0 + 66, 180, 44, { font = app.fonts.med, color = { 1, 0.45, 0.35 } }) then self:stopLive() end
    return
  end
  local tabs = { { "build", "Build" }, { "edit", "Edit" }, { "delete", "Delete" } }
  for i, t in ipairs(tabs) do
    if ui.button(t[2], 8, y0 + 8 + (i - 1) * 44, 92, 38, { font = app.fonts.med, color = self.tab == t[1] and ui.ACCENT or nil }) then
      self.tab = t[1]
      self:cancelTools()
    end
  end
  local x, y, w = 110, y0 + 8, app.W - 118
  if self.tab == "build" then self:drawBuild(x, y, w)
  elseif self.tab == "edit" then self:drawEdit(x, y, w)
  else self:drawDelete(x, y, w) end
end

function Editor:drawTopBar()
  local m = self.map
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, TOP_H)
  love.graphics.setFont(app.fonts.tiny)
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.print(m.builtin and "BUILT-IN" or "CUSTOM MAP", 10, 2)
  if self.typing then
    ui.focus = ui.count + 1 -- keep keyboard focus in the name field while typing
    local name, submitted = ui.textField(m.name or "", 10, 16, 230, 32, { font = app.fonts.med, maxLength = 30,
      placeholder = "Map name" })
    if name ~= m.name then
      m.name = name
      self.dirty = true
    end
    if submitted then
      self.typing = false
      self:touch()
    end
  elseif ui.button((m.name ~= "" and m.name or "Map name"), 10, 16, 230, 32, { font = app.fonts.med }) then
    self.typing = true
  end
  local g = self:gridSize()
  local buttons = {
    { "Undo", function() self:doUndo() end, #self.undo > 0 },
    { "Redo", function() self:doRedo() end, #self.redo > 0 },
    { g > 1 and ("Grid " .. g) or "Grid off", function() self.gridI = self.gridI % #GRIDS + 1 end, true },
    { self.mirror and "Mirror on" or "Mirror off", function() self.mirror = not self.mirror end, true },
    { "Fit view", function() self:fitView() end, true },
    { self.live and "Stop" or "Play here", function() if self.live then self:stopLive() else self:startLive() end end, true, { 0.4, 1, 0.55 } },
    { "Full test", function() self:test() end, true },
    { "Save", function() self:save() end, true },
    { "Share", function() self:share() end, true },
    { "Import", function() self:import() end, true },
    { "Exit", function() self:exit() end, true },
  }
  local bx = 250
  local bw = (app.W - bx - 8 - (#buttons - 1) * 5) / #buttons
  for _, b in ipairs(buttons) do
    if ui.button(b[1], bx, 8, bw, 36, { font = app.fonts.small, disabled = not b[3] or (self.live and b[1] ~= "Stop" and b[1] ~= "Fit view"), color = b[4] }) then b[2]() end
    bx = bx + bw + 5
  end
end

function Editor:drawStatus()
  if self.live then return end
  local y = app.H - BAR_H - 24
  love.graphics.setColor(0.09, 0.09, 0.12, 0.75)
  love.graphics.rectangle("fill", 0, y - 2, app.W, 24)
  love.graphics.setFont(app.fonts.small)
  local ok = #self.problems == 0
  love.graphics.setColor(ok and { 0.4, 1, 0.5 } or { 1, 0.5, 0.4 })
  love.graphics.circle("fill", 14, y + 9, 5)
  love.graphics.printf(ok and "Ready to save and share" or table.concat(self.problems, "   |   "), 26, y, app.W * 0.62, "left")
  if self.msg and self.msgT > 0 then
    love.graphics.setColor(self.msgBad and { 1, 0.55, 0.45, math.min(1, self.msgT) } or { 1, 1, 1, math.min(1, self.msgT) })
    love.graphics.printf(self.msg, app.W * 0.5, y, app.W * 0.5 - 12, "right")
  end
end

function Editor:draw()
  self:drawWorld()
  self:drawTopBar()
  self:drawBar()
  self:drawStatus()
end

return Editor
