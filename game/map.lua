-- Arenas (lists of solid rectangles) and collision helpers.
local Map = {}

-- Used if no map files are found (shouldn't happen in a release build).
Map.FALLBACK = {
  name = "Fallback", id = "fallback",
  spawns = { { 300, 580 }, { 980, 580 }, { 400, 580 }, { 880, 580 } },
  rects = { { x = 140, y = 620, w = 1000, h = 40 } }, objects = {},
}


---------------------------------------------------------------- map files
-- Every map is a small text file in the editor's format:
--   deckshot-map 1
--   name <name>
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

-- Text -> map table (or nil, error).
function Map.parse(text)
  if type(text) ~= "string" then return nil, "no map data" end
  local map = { name = "Untitled", spawns = {}, rects = {}, objects = {} }
  local first = true
  for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local word, rest = line:match("^%s*(%S+)%s*(.-)%s*$")
    if first and word then
      if word ~= "deckshot-map" then return nil, "not a Deckshot map" end
      first = false
    elseif word == "name" then
      map.name = rest ~= "" and rest:sub(1, 40) or "Untitled"
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
  while #map.spawns < 4 do map.spawns[#map.spawns + 1] = { 640, 300 } end
  map.id = Map.idOf(map.name)
  return map
end

-- Map table -> text.
function Map.serialize(map)
  local out = { "deckshot-map 1", "name " .. (map.name or "Untitled") }
  for i = 1, 4 do
    local s = map.spawns[i] or { 640, 300 }
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
      m = { name = "Missing map", spawns = { { 300, 500 }, { 980, 500 }, { 400, 500 }, { 880, 500 } },
        rects = { { x = 100, y = 560, w = 1080, h = 40 } }, objects = {} }
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

function Map.overlaps(ax, ay, aw, ah, b)
  return ax < b.x + b.w and ax + aw > b.x and ay < b.y + b.h and ay + ah > b.y
end

-- Returns the first solid rect overlapping the given box, or nil. One-way platforms
-- (rect.oneway) are skipped: only players land on them, from above.
function Map.hit(rects, x, y, w, h)
  for _, b in ipairs(rects) do
    if not b.oneway and Map.overlaps(x, y, w, h, b) then return b end
  end
  return nil
end

Map.loadAll()

function Map.draw(map)
  for _, b in ipairs(map.rects) do
    if b.oneway then
      love.graphics.setColor(0.3, 0.31, 0.38, 0.55)
      love.graphics.rectangle("fill", b.x, b.y, b.w, math.min(b.h, 10))
      love.graphics.setColor(0.62, 0.64, 0.75)
      love.graphics.rectangle("fill", b.x, b.y, b.w, 3)
    else
      love.graphics.setColor(0.3, 0.31, 0.38)
      love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
      love.graphics.setColor(0.45, 0.46, 0.55)
      love.graphics.rectangle("fill", b.x, b.y, b.w, 3)
    end
  end
  Map.drawEdges()
end

-- The arena's damaging edges (left, right, bottom).
function Map.drawEdges()
  local t = love.timer.getTime()
  local a = 0.45 + 0.15 * math.sin(t * 3)
  love.graphics.setColor(1, 0.2, 0.18, a)
  love.graphics.rectangle("fill", 0, 0, 4, 720)
  love.graphics.rectangle("fill", 1276, 0, 4, 720)
  love.graphics.rectangle("fill", 0, 716, 1280, 4)
  love.graphics.setColor(1, 0.2, 0.18, a * 0.25)
  love.graphics.rectangle("fill", 4, 0, 8, 720)
  love.graphics.rectangle("fill", 1268, 0, 8, 720)
  love.graphics.rectangle("fill", 0, 708, 1280, 8)
end

return Map
