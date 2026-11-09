-- Arenas (lists of solid rectangles) and collision helpers.
local Map = {}

-- The arena in world units. The whole arena is always on screen: the game view is drawn scaled
-- by Map.VIEW so it fits the 1280x720 screen (menus and the HUD are not scaled).
Map.W, Map.H = 1536, 864
Map.VIEW = 1280 / Map.W
Map.FORMAT = 4
local OLD_SCALE = 1.2 -- format 1 maps were made for a 1280x720 arena

-- Used if no map files are found (shouldn't happen in a release build).
Map.FALLBACK = {
  name = "Fallback", id = "fallback",
  spawns = { { 360, 696 }, { 1176, 696 }, { 480, 696 }, { 1056, 696 } },
  rects = { { x = 168, y = 744, w = 1200, h = 48 } }, objects = {},
}


---------------------------------------------------------------- map files
-- Every map is a small text file in the editor's format:
--   deckshot-map 3           (format 1 = the old 1280x720 arena, spread out when loaded;
--                             before format 3, floating objects are anchored when loaded)
--   name <name>
--   theme <name>             (optional background: see gfx/atmosphere.lua)
--   spawn <x> <y>            (4 lines, spawns 1-4 in order)
--   rect <x> <y> <w> <h>     solid block
--   oneway <x> <y> <w> <h>   one-way platform
--   obj <type> key=value ... (map objects; path=x,y;x,y  target=<object number>)
-- Built-in maps live in data/maps/ (order in data/maps/order.txt). Editing one in-game saves
-- an override to the save folder (user/maps/<id>.txt); custom maps go to user/custom_maps/.
Map.BUILTIN_DIR = "data/maps/"
Map.OVERRIDE_DIR = "user/maps/"
Map.CUSTOM_DIR = "user/custom_maps/"
Map.SHARE_PREFIX = "DSMAP1:"

function Map.idOf(name)
  local id = (name or "map"):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  return id ~= "" and id or "map"
end

local function num(v)
  local n = tonumber(v)
  if not n then return v end
  if n == math.floor(n) then return math.floor(n) end
  return n
end

local function fmt(v)
  if type(v) == "number" then
    if v == math.floor(v) then return tostring(math.floor(v)) end
    return string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", "")
  end
  if type(v) == "boolean" then return v and "true" or "false" end
  return tostring(v)
end

local function round(v) return math.floor(v + 0.5) end

-- Spreads a format 1 map over the bigger arena: blocks grow with it, and things that sit on a
-- surface (or hang from one) stay attached to it instead of floating. Sizes of breakables,
-- saws and so on don't change.
local WIDE = { spikes = true, acid = true, conveyor = true, crumble = true, platform = true, plank = true, crusher = true }
local TOP_ALIGNED = { crusher = true }
function Map.upgrade(map)
  local k = OLD_SCALE
  for _, s in ipairs(map.spawns) do s[1], s[2] = round(s[1] * k), round(s[2] * k) end
  for _, r in ipairs(map.rects) do
    local x1, y1 = round((r.x + r.w) * k), round((r.y + r.h) * k)
    r.x, r.y = round(r.x * k), round(r.y * k)
    r.w, r.h = x1 - r.x, y1 - r.y
  end
  for _, o in ipairs(map.objects) do
    if o.w and o.h then
      local dir = o.dir
      local w, h = o.w, o.h
      if WIDE[o.type] or dir == "left" or dir == "right" then w = round(w * k) end
      if o.type == "fan" then
        if dir == "left" or dir == "right" then h = h else h = round(h * k) end
      end
      if dir == "left" or dir == "right" then
        if o.type == "spikes" then h, w = round(o.h * k), o.w end
      end
      local x, y = round(o.x * k), round(o.y * k)
      local vertical = dir == "left" or dir == "right"
      if not vertical and dir ~= "down" and not TOP_ALIGNED[o.type] then y = round((o.y + o.h) * k) - h end
      if dir == "left" then x = round((o.x + o.w) * k) - w end
      o.x, o.y, o.w, o.h = x, y, w, h
    else
      o.x, o.y = round(o.x * k), round(o.y * k)
    end
    if o.travel then o.travel = round(o.travel * k) end
    if o.length and o.type == "flame" then o.length = round(o.length * k) end
    if o.path then
      for _, pt in ipairs(o.path) do pt[1], pt[2] = round(pt[1] * k), round(pt[2] * k) end
    end
  end
end

-- Before format 3 only crates, barrels and gas cans fell. Everything else stayed where it was
-- put, so whatever a map left floating or sunk into terrain gets an anchor to keep the layout.
local BOXES = { wall = { 40, 120 }, plank = { 100, 14 }, glass = { 16, 120 }, spikes = { 80, 16 }, crate = { 50, 50 },
  barrel = { 36, 48 }, gas = { 28, 42 }, crumble = { 120, 18 }, platform = { 120, 18 }, conveyor = { 200, 20 },
  crusher = { 120, 60 } }
local ROUND = { saw = 28, weight = 26, turret = 18 }
local NEWLY_LOOSE = { wall = true, plank = true, glass = true, spikes = true, saw = true, weight = true, turret = true }

local function objectBox(o)
  local size = BOXES[o.type]
  if size then return o.x, o.y, o.w or size[1], o.h or size[2] end
  local r = o.r or ROUND[o.type]
  if r then return o.x - r, o.y - r, r * 2, r * 2 end
end

function Map.anchorFloating(map)
  local held = {}
  for _, o in ipairs(map.objects) do
    if o.type == "rope" and o.target then held[o.target] = true end
  end
  local supports = {}
  for _, r in ipairs(map.rects) do supports[#supports + 1] = { x = r.x, y = r.y, w = r.w, h = r.h, terrain = true } end
  for _, o in ipairs(map.objects) do
    local x, y, w, h = objectBox(o)
    if x and BOXES[o.type] and o.type ~= "spikes" then supports[#supports + 1] = { x = x, y = y, w = w, h = h, ref = o } end
  end
  for i, o in ipairs(map.objects) do
    if NEWLY_LOOSE[o.type] and not held[i] and not (o.path and #o.path >= 2) then
      local x, y, w, h = objectBox(o)
      local resting, sunk = false, false
      for _, b in ipairs(supports) do
        if b.ref ~= o then
          if Map.overlaps(x + 2, y + h - 1, w - 4, 8, b) then resting = true end
          if b.terrain and Map.overlaps(x + 8, y + 8, math.max(1, w - 16), math.max(1, h - 16), b) then sunk = true end
        end
      end
      if not resting or sunk or (o.type == "spikes" and (o.dir or "up") ~= "up") then o.anchored = true end
    end
  end
end

-- Format 4 has one Block object with a material and toggles instead of separate crates, walls,
-- glass, planks, barrels, gas cans, crumbling platforms and conveyors. Blade arms and moving
-- platforms became plain arms and rails with objects attached, and acid became a liquid.
-- Objects are referred to by `id` (ropes' `target`, attachments' `parent`) instead of position.
local BLOCKS = {
  crate = { material = "crate", hp = 60, drop = 0.08, onBreak = "pickup", physics = true },
  wall = { material = "brick", hp = 150, physics = true },
  glass = { material = "glass", hp = 1, physics = true },
  plank = { material = "wood", hp = 0, physics = true },
  barrel = { material = "barrel", hp = 30, onBreak = "explode", radius = 110, damage = 55, physics = true },
  gas = { material = "gas", hp = 20, onBreak = "gas", radius = 110, physics = true },
  crumble = { material = "stone", crumble = true, delay = 0.5, back = 4 },
  conveyor = { material = "metal", conveyor = true, speed = 160 },
}
local OLD_PHYSICS = { saw = true, weight = true, turret = true, spikes = true }

function Map.convertObjects(map)
  local list = map.objects
  local held, nextId = {}, #list + 1
  for i, o in ipairs(list) do
    o.id = i
    if o.type == "rope" and o.target then held[o.target] = true end
  end
  local function add(o)
    o.id = nextId
    nextId = nextId + 1
    list[#list + 1] = o
    return o
  end
  local count = #list
  for i = 1, count do
    local o = list[i]
    local b = BLOCKS[o.type]
    if b then
      local size = BOXES[o.type]
      o.w, o.h = o.w or size[1], o.h or size[2]
      for k, v in pairs(b) do
        if o[k] == nil then o[k] = v end
      end
      o.type = "block"
    elseif o.type == "acid" then
      o.type = "liquid"
      o.color = "#59D934"
      o.w, o.h = o.w or 200, o.h or 40
      o.damage = o.damage or 20
    elseif o.type == "platform" then
      o.w, o.h = o.w or 120, o.h or 18
      local path = o.path
      o.type, o.material, o.path = "block", "metal", nil
      if path and #path >= 2 then
        local rail = add({ type = "rail", x = path[1][1], y = path[1][2], path = path, speed = o.speed or 120, loop = o.loop })
        o.x, o.y = path[1][1] - o.w / 2, path[1][2] - o.h / 2
        o.parent = rail.id
      elseif held[i] then
        o.physics = true
      end
      o.speed, o.loop = nil, nil
    elseif o.type == "arm" then
      local arm = o
      local length, count2, r, damage = o.length or 110, o.count or 2, o.r or 22, o.damage or 25
      for k = 1, count2 do
        local a = (o.phase or 0) + (k - 1) * math.pi
        add({ type = "saw", x = o.x + math.cos(a) * length, y = o.y + math.sin(a) * length, r = r, damage = damage, parent = arm.id })
      end
      arm.length, arm.r, arm.damage, arm.count = length, nil, nil, count2 == 1 and 1 or nil
    elseif o.type == "saw" and o.path and #o.path >= 2 then
      local rail = add({ type = "rail", x = o.path[1][1], y = o.path[1][2], path = o.path, speed = o.speed or 160 })
      o.x, o.y, o.path, o.speed = rail.x, rail.y, nil, nil
      o.parent = rail.id
    elseif OLD_PHYSICS[o.type] and not o.anchored then
      o.physics = true
    elseif o.type == "rope" then
      o.level = true -- old rope bridges stay walkable
    end
  end
end

-- Plain blocks are stored as map rects; everything with a setting stays an object.
function Map.plainBlock(o)
  return o.type == "block" and (o.material or "stone") == "stone" and not o.physics and (o.hp or 0) <= 0 and not o.rot
    and (o.slope or "none") == "none"
    and not o.crumble and not o.conveyor and not o.anchored and not o.parent and not o.color
    and (o.onBreak or "none") == "none"
end

-- The editor treats every block as an object; rects come back when the map is saved.
function Map.expandBlocks(map)
  local nextId = 1
  for _, o in ipairs(map.objects) do nextId = math.max(nextId, (o.id or 0) + 1) end
  for _, r in ipairs(map.rects) do
    map.objects[#map.objects + 1] = { type = "block", material = "stone", id = nextId, x = r.x, y = r.y, w = r.w, h = r.h,
      oneway = r.oneway }
    nextId = nextId + 1
  end
  map.rects = {}
end

function Map.compactBlocks(map)
  local used = {}
  for _, o in ipairs(map.objects) do
    if o.target then used[o.target] = true end
    if o.from then used[o.from] = true end
    if o.parent then used[o.parent] = true end
  end
  local keep = {}
  for _, o in ipairs(map.objects) do
    if Map.plainBlock(o) and not used[o.id or -1] then
      map.rects[#map.rects + 1] = { x = o.x, y = o.y, w = o.w or 48, h = o.h or 48, oneway = o.oneway or nil }
    else
      keep[#keep + 1] = o
    end
  end
  map.objects = keep
  -- Tiles painted side by side become one long block.
  table.sort(map.rects, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    if a.h ~= b.h then return a.h < b.h end
    return a.x < b.x
  end)
  local merged = {}
  for _, r in ipairs(map.rects) do
    local last = merged[#merged]
    if last and last.y == r.y and last.h == r.h and last.oneway == r.oneway and last.x + last.w == r.x then
      last.w = last.w + r.w
    else
      merged[#merged + 1] = r
    end
  end
  map.rects = merged
end

-- Text -> map table (or nil, error).
function Map.parse(text)
  if type(text) ~= "string" then return nil, "no map data" end
  local map = { name = "Untitled", spawns = {}, rects = {}, objects = {} }
  local first = true
  local format = 1
  for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local word, rest = line:match("^%s*(%S+)%s*(.-)%s*$")
    if first and word then
      if word ~= "deckshot-map" then return nil, "not a Deckshot map" end
      first = false
      format = tonumber(rest) or 1
    elseif word == "name" then
      map.name = rest ~= "" and rest:sub(1, 40) or "Untitled"
    elseif word == "theme" then
      map.theme = rest ~= "" and rest or nil
    elseif word == "channel" then
      local n, c = rest:match("^(%d+)%s+(#%x%x%x%x%x%x)")
      if n then
        map.channels = map.channels or {}
        map.channels[tonumber(n)] = c
      end
    elseif word == "spawn" then
      local x, y = rest:match("^(%S+)%s+(%S+)")
      if tonumber(x) and tonumber(y) then map.spawns[#map.spawns + 1] = { tonumber(x), tonumber(y) } end
    elseif word == "rect" or word == "oneway" then
      local x, y, w, h = rest:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
      if tonumber(h) then
        map.rects[#map.rects + 1] = { x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h),
          oneway = word == "oneway" or nil }
      end
    elseif word == "obj" then
      local otype, props = rest:match("^(%S+)%s*(.*)$")
      if otype then
        local o = { type = otype }
        for k, v in props:gmatch("([%w_]+)=(%S+)") do
          if k == "path" then
            local pts = {}
            for px, py in v:gmatch("([%-%d%.]+),([%-%d%.]+)") do pts[#pts + 1] = { tonumber(px), tonumber(py) } end
            o.path = pts
          elseif v == "true" or v == "false" then
            o[k] = v == "true"
          else
            o[k] = num(v)
          end
        end
        map.objects[#map.objects + 1] = o
      end
    end
  end
  if first then return nil, "empty map" end
  if format < 2 then Map.upgrade(map) end
  if format < 3 then Map.anchorFloating(map) end
  if format < 4 then Map.convertObjects(map) end
  while #map.spawns < 4 do map.spawns[#map.spawns + 1] = { Map.W / 2, 360 } end
  map.id = Map.idOf(map.name)
  return map
end

-- Map table -> text.
function Map.serialize(map)
  local out = { "deckshot-map " .. Map.FORMAT, "name " .. (map.name or "Untitled") }
  if map.theme then out[#out + 1] = "theme " .. map.theme end
  local channels = {}
  for n in pairs(map.channels or {}) do channels[#channels + 1] = n end
  table.sort(channels)
  for _, n in ipairs(channels) do out[#out + 1] = "channel " .. n .. " " .. map.channels[n] end
  for i = 1, 4 do
    local s = map.spawns[i] or { Map.W / 2, 360 }
    out[#out + 1] = "spawn " .. fmt(s[1]) .. " " .. fmt(s[2])
  end
  for _, r in ipairs(map.rects) do
    out[#out + 1] = (r.oneway and "oneway " or "rect ") .. fmt(r.x) .. " " .. fmt(r.y) .. " " .. fmt(r.w) .. " " .. fmt(r.h)
  end
  for _, o in ipairs(map.objects or {}) do
    local keys = {}
    for k, v in pairs(o) do
      if k ~= "type" and k ~= "path" and (type(v) == "number" or type(v) == "string" or type(v) == "boolean") then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys)
    local parts = { "obj", o.type }
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. fmt(o[k]) end
    if o.path and #o.path > 0 then
      local pts = {}
      for _, pt in ipairs(o.path) do pts[#pts + 1] = fmt(pt[1]) .. "," .. fmt(pt[2]) end
      parts[#parts + 1] = "path=" .. table.concat(pts, ";")
    end
    out[#out + 1] = table.concat(parts, " ")
  end
  return table.concat(out, "\n") .. "\n"
end

-- Share codes: the map text, compressed and base64-encoded.
function Map.encodeShare(map)
  local packed = love.data.compress("string", "zlib", Map.serialize(map), 9)
  return Map.SHARE_PREFIX .. love.data.encode("string", "base64", packed)
end

function Map.decodeShare(code)
  code = (code or ""):gsub("%s+", "")
  local body = code:match("^" .. Map.SHARE_PREFIX:gsub("%p", "%%%0") .. "(.+)$")
  if not body then return nil, "That isn't a map code" end
  local ok, packed = pcall(love.data.decode, "string", "base64", body)
  if not ok then return nil, "The map code is damaged" end
  local ok2, text = pcall(love.data.decompress, "string", "zlib", packed)
  if not ok2 then return nil, "The map code is damaged" end
  return Map.parse(text)
end

local function readFile(path)
  if not love.filesystem.getInfo(path) then return nil end
  return love.filesystem.read(path)
end

-- Give every map its network index and id lookups.
local function indexList()
  Map.byId = {}
  for i, m in ipairs(Map.list) do
    m.index = i
    m.id = m.id or Map.idOf(m.name)
    Map.byId[m.id] = m
  end
end

-- (Re)load every map: built-ins (with in-game edits applied), then custom maps by name.
function Map.loadAll()
  local list = {}
  local order = readFile(Map.BUILTIN_DIR .. "order.txt") or ""
  for id in order:gmatch("[%w_]+") do
    local text = readFile(Map.BUILTIN_DIR .. id .. ".txt")
    local m = text and Map.parse(text)
    if m then
      m.id, m.builtin = id, true
      m.defaultText = text
      local edited = readFile(Map.OVERRIDE_DIR .. id .. ".txt")
      local em = edited and Map.parse(edited)
      if em then
        em.id, em.builtin, em.edited, em.defaultText = id, true, true, text
        m = em
      end
      list[#list + 1] = m
    end
  end
  if #list == 0 then
    list[1] = Map.FALLBACK
  end
  local customs = {}
  for _, file in ipairs(love.filesystem.getDirectoryItems(Map.CUSTOM_DIR)) do
    if file:match("%.txt$") then
      local m = Map.parse(readFile(Map.CUSTOM_DIR .. file))
      if m then
        m.id, m.custom = "c_" .. file:gsub("%.txt$", ""), true
        m.file = file
        customs[#customs + 1] = m
      end
    end
  end
  table.sort(customs, function(a, b) return a.name:lower() < b.name:lower() end)
  for _, m in ipairs(customs) do list[#list + 1] = m end
  Map.list = list
  Map.session = nil
  indexList()
end

-- Save a custom map (new or existing). Returns the file name.
function Map.saveCustom(map)
  love.filesystem.createDirectory(Map.CUSTOM_DIR)
  local file = map.file
  if not file then
    local base = Map.idOf(map.name)
    file = base .. ".txt"
    local n = 2
    while love.filesystem.getInfo(Map.CUSTOM_DIR .. file) do
      file = base .. "_" .. n .. ".txt"
      n = n + 1
    end
  end
  love.filesystem.write(Map.CUSTOM_DIR .. file, Map.serialize(map))
  return file
end

function Map.deleteCustom(map)
  if map.file then love.filesystem.remove(Map.CUSTOM_DIR .. map.file) end
end

-- Edits to a built-in map are saved as an override (reset deletes it).
function Map.saveOverride(map)
  love.filesystem.createDirectory(Map.OVERRIDE_DIR)
  love.filesystem.write(Map.OVERRIDE_DIR .. map.id .. ".txt", Map.serialize(map))
end

function Map.resetOverride(id)
  love.filesystem.remove(Map.OVERRIDE_DIR .. id .. ".txt")
end

-- Online: the maps the host plays with. entries = { { id = .., text = .. or nil } } where text is
-- sent for custom / edited maps and nil for built-ins everyone has.
function Map.sessionEntries()
  local out = {}
  for _, m in ipairs(Map.list) do
    out[#out + 1] = { id = m.id, text = (m.custom or m.edited) and Map.serialize(m) or nil }
  end
  return out
end

function Map.setSession(entries)
  Map.loadAll()
  local builtins = Map.byId
  local list = {}
  for _, e in ipairs(entries) do
    local m = e.text and Map.parse(e.text) or builtins[e.id]
    if m then
      m.id = e.id
      if e.text then m.custom = true end
    else
      m = { name = "Missing map", spawns = { { 360, 600 }, { 1176, 600 }, { 480, 600 }, { 1056, 600 } },
        rects = { { x = 120, y = 672, w = 1296, h = 48 } }, objects = {} }
    end
    list[#list + 1] = m
  end
  Map.list = list
  Map.session = true
  indexList()
end

-- Pick a random map, avoiding the index of the previous one. `disabled` is an optional
-- set of map indices to leave out (the map pool setting); if it leaves nothing, all maps are used.
function Map.random(exclude, disabled)
  local pool = {}
  for i in ipairs(Map.list) do
    if not (disabled and disabled[i]) then pool[#pool + 1] = i end
  end
  if #pool == 0 then
    for i in ipairs(Map.list) do pool[i] = i end
  end
  local i
  repeat
    i = pool[love.math.random(#pool)]
  until i ~= exclude or #pool == 1
  return Map.list[i], i
end

-- King of the Hill: where a hill can sit. Surfaces wide enough to stand on, spread out over the
-- arena and away from hazards.
local HAZARD_TYPES = { saw = true, spikes = true, laser = true, crusher = true, flame = true, acid = true, turret = true, arm = true }
function Map.hillPoints(map)
  if map.hills then return map.hills end
  local tops = {}
  for _, r in ipairs(map.rects) do
    if r.w >= 120 and r.y > 170 and r.y < Map.H - 30 then
      tops[#tops + 1] = { r.x + r.w / 2, r.y - 70, r.w }
    end
  end
  table.sort(tops, function(a, b) return a[3] > b[3] end)
  local function safe(x, y)
    for _, o in ipairs(map.objects or {}) do
      if HAZARD_TYPES[o.type] then
        local ox, oy = o.x + (o.w or 0) / 2, o.y + (o.h or 0) / 2
        if (ox - x) ^ 2 + (oy - y) ^ 2 < 140 * 140 then return false end
      end
    end
    return true
  end
  local out = {}
  for _, t in ipairs(tops) do
    local far = safe(t[1], t[2])
    for _, o in ipairs(out) do
      if (o[1] - t[1]) ^ 2 + (o[2] - t[2]) ^ 2 < 300 * 300 then far = false end
    end
    if far and #out < 8 then out[#out + 1] = { math.floor(t[1]), math.floor(t[2]) } end
  end
  if #out == 0 then out[1] = { Map.W / 2, Map.H / 2 } end
  map.hills = out
  return out
end

function Map.overlaps(ax, ay, aw, ah, b)
  return ax < b.x + b.w and ax + aw > b.x and ay < b.y + b.h and ay + ah > b.y
end

Map.loadAll()

return Map
