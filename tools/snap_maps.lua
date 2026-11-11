-- Snaps built-in maps to the editor grid (24 px edges, 12 px for objects placed by their centre)
-- and extends low grounds to the arena's bottom. Physics props keep their shape and ride on
-- what holds them up. Run from the repo root: luajit tools/snap_maps.lua . [write]
local repo, write = arg[1], arg[2] == "write"
local W, H = 1536, 864
local function s(v, g) return math.floor(v / g + 0.5) * g end

local function parseObj(line)
  local kind, rest = line:match("^obj (%S+)%s*(.*)$")
  local kv, order = {}, {}
  for k, v in rest:gmatch("(%w+)=(%S+)") do kv[k] = v; order[#order + 1] = k end
  return kind, kv, order
end
local function objLine(kind, kv, order)
  local parts = { "obj " .. kind }
  for _, k in ipairs(order) do parts[#parts + 1] = k .. "=" .. kv[k] end
  return table.concat(parts, " ")
end
local function num(v) return tonumber(v) end
local function fmt(v) if v == math.floor(v) then return tostring(math.floor(v)) end return tostring(v) end

local report = {}
local order = {}
for id in io.lines(repo .. "/data/maps/order.txt") do if id ~= "" then order[#order + 1] = id end end
for _, id in ipairs(order) do
  local path = repo .. "/data/maps/" .. id .. ".txt"
  local lines = {}
  for l in io.lines(path) do lines[#lines + 1] = l end
  -- Gather boxes (rects, oneways, blocks with w/h) with their line index.
  local boxes, changes, extended = {}, 0, 0
  local objs = {}
  for i, l in ipairs(lines) do
    local kind, x, y, w, h = l:match("^(%a+) (%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+)$")
    if kind == "rect" or kind == "oneway" then
      boxes[#boxes + 1] = { i = i, kind = kind, x = num(x), y = num(y), w = num(w), h = num(h) }
    elseif l:match("^obj ") then
      local k, kv, ord = parseObj(l)
      objs[#objs + 1] = { i = i, kind = k, kv = kv, ord = ord }
      if kv.w and kv.h and kv.x and kv.y then
        boxes[#boxes + 1] = { i = i, kind = "obj:" .. k, obj = objs[#objs], x = num(kv.x), y = num(kv.y), w = num(kv.w), h = num(kv.h), physics = kv.physics == "true" and not kv.parent }
      end
    end
  end
  -- Mirror partners (before snapping).
  for _, a in ipairs(boxes) do
    for _, b in ipairs(boxes) do
      if a ~= b and not a.mirrorOf and not b.mirrorOf and a.kind == b.kind and a.y == b.y and a.w == b.w and a.h == b.h
          and math.abs(a.x - (W - b.x - b.w)) <= 2 and a.x < b.x then
        b.mirrorOf = a
      end
    end
  end
  local byId = {}
  for _, o in ipairs(objs) do if o.kv.id then byId[o.kv.id] = o end end
  -- x edges: exact halves round toward the middle, so both sides of a symmetric map agree.
  local function sx(v)
    local t = v / 24
    if t - math.floor(t) == 0.5 then return (v < W / 2 and math.ceil(t) or math.floor(t)) * 24 end
    return s(v, 24)
  end
  local function overlapX(a, b) return a.x < b.x + b.w - 1 and b.x < a.x + a.w - 1 end
  for _, b in ipairs(boxes) do
    b.restsOn, b.below = false, false
    for _, c in ipairs(boxes) do
      if c ~= b and overlapX(b, c) then
        if math.abs(c.y - (b.y + b.h)) <= 1 then b.restsOn = true end
        if c.kind ~= "oneway" and c.y >= b.y + b.h - 1 then b.below = true end
      end
    end
  end
  for _, b in ipairs(boxes) do
    b.ox, b.oy = b.x, b.y
    -- Edges are rounded, not sizes, so pieces that touched still touch.
    local nx = sx(b.x)
    local nw = math.max(24, sx(b.x + b.w) - nx)
    local ny, nh
    if b.h >= 24 then
      ny = s(b.y, 24)
      nh = math.max(24, s(b.y + b.h, 24) - ny)
    elseif b.restsOn then
      ny, nh = s(b.y + b.h, 24) - b.h, b.h -- thin and resting on something: keep it resting
    else
      ny, nh = s(b.y, 24), b.h
    end
    if ny + nh > H and b.y + b.h <= H + 1 then nh = H - ny end
    -- Physics props keep their exact shape (stacks are balanced); they only ride on their support.
    if b.physics then nx, nw, ny, nh = b.x, b.w, b.y, b.h end
    -- Grounds that stop short of the bottom reach it (unless they stand on something).
    if b.kind == "rect" and not b.below and ny + nh < H and ny + nh >= H - 130 and ny >= 500 then
      nh = H - ny
      extended = extended + 1
    end
    b.nx, b.ny, b.nw, b.nh = nx, ny, nw, nh
  end
  -- Stacks: from the bottom up, whatever rests on something sits on its new top.
  local sorted = {}
  for _, b in ipairs(boxes) do sorted[#sorted + 1] = b end
  table.sort(sorted, function(a, b) return a.y + a.h > b.y + b.h end)
  for _, b in ipairs(sorted) do
    local support
    for _, c in ipairs(boxes) do
      if c ~= b and overlapX(b, c) and math.abs(c.y - (b.y + b.h)) <= 1 then support = c break end
    end
    if support then b.ny = support.ny - b.nh end
  end
  for _, b in ipairs(boxes) do
    if b.mirrorOf then
      local a = b.mirrorOf
      b.nx, b.ny, b.nw, b.nh = W - a.nx - a.nw, a.ny, a.nw, a.nh
    end
  end
  for _, b in ipairs(boxes) do
    if b.nx ~= b.x or b.ny ~= b.y or b.nw ~= b.w or b.nh ~= b.h then changes = changes + 1 end
    if b.obj then
      local kv = b.obj.kv
      kv.x, kv.y, kv.w, kv.h = fmt(b.nx), fmt(b.ny), fmt(b.nw), fmt(b.nh)
      b.obj.dx, b.obj.dy = b.nx - b.x, b.ny - b.y
    else
      lines[b.i] = b.kind .. " " .. fmt(b.nx) .. " " .. fmt(b.ny) .. " " .. fmt(b.nw) .. " " .. fmt(b.nh)
    end
  end
  -- Centre-based objects, rails and ropes.
  for _, o in ipairs(objs) do
    local kv = o.kv
    if not (kv.w and kv.h) and kv.x and kv.y and o.kind ~= "rope" then
      local x, y = num(kv.x), num(kv.y)
      local nx, ny = s(x, 12), s(y, 12)
      o.dx, o.dy = nx - x, ny - y
      kv.x, kv.y = fmt(nx), fmt(ny)
    end
    if kv.path then
      local pts = {}
      for px, py in kv.path:gmatch("(%-?[%d%.]+),(%-?[%d%.]+)") do pts[#pts + 1] = fmt(s(num(px), 12)) .. "," .. fmt(s(num(py), 12)) end
      kv.path = table.concat(pts, ";")
    end
  end
  for _, o in ipairs(objs) do
    local kv = o.kv
    if o.kind == "rope" then
      if kv.x then kv.x, kv.y = fmt(s(num(kv.x), 12)), fmt(s(num(kv.y), 12)) end
      local t = kv.target and byId[kv.target]
      if t and t.dx and kv.x2 then
        kv.x2, kv.y2 = fmt(num(kv.x2) + t.dx), fmt(num(kv.y2) + t.dy)
      elseif kv.x2 then
        kv.x2, kv.y2 = fmt(s(num(kv.x2), 12)), fmt(s(num(kv.y2), 12))
      end
      local f = kv.from and byId[kv.from]
      if f and f.dx and kv.x then kv.x, kv.y = fmt(num(kv.x) + f.dx), fmt(num(kv.y) + f.dy) end
    end
    lines[o.i] = objLine(o.kind, kv, o.ord)
  end
  -- Spawns stand on whatever is under them.
  for i, l in ipairs(lines) do
    local sx, sy = l:match("^spawn (%-?[%d%.]+) (%-?[%d%.]+)$")
    if sx then
      sx, sy = num(sx), num(sy)
      local best
      for _, b in ipairs(boxes) do
        if sx >= b.x - 4 and sx <= b.x + b.w + 4 and b.y >= sy - 4 and (not best or b.y < best.y) then best = b end
      end
      local nx = s(sx, 12)
      local ny = best and (best.ny - (best.y - sy)) or sy
      lines[i] = "spawn " .. fmt(nx) .. " " .. fmt(ny)
    end
  end
  report[#report + 1] = string.format("%-16s boxes changed %2d, grounds extended %d", id, changes, extended)
  if write then
    local f = assert(io.open(path, "w"))
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
  end
end
print(table.concat(report, "\n"))
