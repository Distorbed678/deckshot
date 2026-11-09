-- Every image the game draws comes from here, by name. Sources are the SVGs in assets/art;
-- tools/build_art.sh turns them into assets/sprites/<name>.png at twice their drawn size.
local Assets = { images = {} }

function Assets.image(name)
  local img = Assets.images[name]
  if img == nil then
    local ok, loaded = pcall(love.graphics.newImage, "assets/sprites/" .. name .. ".png")
    img = ok and loaded or false
    if img then img:setFilter("linear", "linear") end
    Assets.images[name] = img
  end
  return img
end

-- Stretched over a box.
function Assets.rect(name, x, y, w, h)
  local img = Assets.image(name)
  if not img then return end
  love.graphics.draw(img, x, y, 0, w / img:getWidth(), h / img:getHeight())
end

-- Centred on a point, optionally turned.
function Assets.center(name, x, y, w, h, angle)
  local img = Assets.image(name)
  if not img then return end
  local iw, ih = img:getDimensions()
  love.graphics.draw(img, x, y, angle or 0, w / iw, h / ih, iw / 2, ih / 2)
end

local tileQuads = {} -- one quad per image, moved for each draw

-- Repeated across a box, each repeat tileW by tileH.
function Assets.tile(name, x, y, w, h, tileW, tileH, scroll)
  local img = Assets.image(name)
  if not img then return end
  img:setWrap("repeat", "repeat")
  local iw, ih = img:getDimensions()
  local sx, sy = tileW / iw, tileH / ih
  local q = tileQuads[img]
  if not q then
    q = love.graphics.newQuad(0, 0, 1, 1, iw, ih)
    tileQuads[img] = q
  end
  q:setViewport((scroll or 0) / sx, 0, w / sx, h / sy, iw, ih)
  love.graphics.draw(img, q, x, y, 0, sx, sy)
end

-- Rounded boxes for the interface, stretched without distorting their corners.
local CORNER = 14
local sliceCache = {}

local function sliceQuads(img)
  local q = sliceCache[img]
  if q then return q end
  local iw, ih = img:getDimensions()
  local c = CORNER * iw / 64
  local mid = iw - c * 2
  q = {}
  local xs, ys, ss = { 0, c, iw - c }, { 0, c, ih - c }, { c, mid, c }
  for row = 1, 3 do
    for col = 1, 3 do
      q[#q + 1] = love.graphics.newQuad(xs[col], ys[row], ss[col], ss[row], iw, ih)
    end
  end
  q.c, q.mid = c, mid
  sliceCache[img] = q
  return q
end

-- mode: "fill" or "line" (a line uses the current line width).
function Assets.round(mode, x, y, w, h)
  local name = "ui_fill"
  if mode == "line" then
    local lw = love.graphics.getLineWidth()
    name = lw >= 4 and "ui_line_5" or lw >= 3 and "ui_line_3" or "ui_line_2"
  end
  local img = Assets.image(name)
  if not img or w <= 0 or h <= 0 then return end
  local q = sliceQuads(img)
  local c = math.min(CORNER, w / 2, h / 2)
  local midW, midH = w - c * 2, h - c * 2
  local i = 0
  for row = 1, 3 do
    local py = row == 1 and y or row == 2 and y + c or y + h - c
    local ph = row == 2 and midH or c
    local sy = (row == 2) and q.mid or q.c
    for col = 1, 3 do
      i = i + 1
      local pw = col == 2 and midW or c
      if pw > 0 and ph > 0 then
        local px = col == 1 and x or col == 2 and x + c or x + w - c
        local sz = (col == 2) and q.mid or q.c
        love.graphics.draw(img, q[i], px, py, 0, pw / sz, ph / sy)
      end
    end
  end
end

-- A texture repeating along a bent line. flat: x1, y1, x2, y2, ...; tileLength: world units per repeat.
-- Ropes and beams are drawn every frame, so the meshes and their vertex tables are kept and reused
-- (one per point count).
local stripMeshes, stripVerts = {}, {}
function Assets.strip(name, flat, width, tileLength)
  local img = Assets.image(name)
  if not img or #flat < 4 then return end
  img:setWrap("repeat", "clamp")
  local n = math.floor(#flat / 2)
  local verts = stripVerts[n]
  if not verts then
    verts = {}
    for i = 1, n * 2 do verts[i] = { 0, 0, 0, i % 2 == 1 and 0 or 1 } end
    stripVerts[n] = verts
    stripMeshes[n] = love.graphics.newMesh(verts, "strip", "stream")
  end
  local u = 0
  for i = 1, n do
    local x, y = flat[i * 2 - 1], flat[i * 2]
    local pi, qi = math.max(1, i - 1), math.min(n, i + 1)
    local dx, dy = flat[qi * 2 - 1] - flat[pi * 2 - 1], flat[qi * 2] - flat[pi * 2]
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then dx, dy, len = 1, 0, 1 end
    local nx, ny = -dy / len * width / 2, dx / len * width / 2
    if i > 1 then
      local sx, sy = x - flat[(i - 1) * 2 - 1], y - flat[(i - 1) * 2]
      u = u + math.sqrt(sx * sx + sy * sy) / tileLength
    end
    local a, b = verts[i * 2 - 1], verts[i * 2]
    a[1], a[2], a[3] = x + nx, y + ny, u
    b[1], b[2], b[3] = x - nx, y - ny, u
  end
  local mesh = stripMeshes[n]
  mesh:setVertices(verts)
  mesh:setTexture(img)
  love.graphics.draw(mesh)
end

return Assets
