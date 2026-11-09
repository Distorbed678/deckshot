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

-- Repeated across a box, each repeat tileW by tileH.
function Assets.tile(name, x, y, w, h, tileW, tileH, scroll)
  local img = Assets.image(name)
  if not img then return end
  img:setWrap("repeat", "repeat")
  local iw, ih = img:getDimensions()
  local sx, sy = tileW / iw, tileH / ih
  local q = love.graphics.newQuad((scroll or 0) / sx, 0, w / sx, h / sy, iw, ih)
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
  local xs, ys = { x, x + c, x + w - c }, { y, y + c, y + h - c }
  local ws, hs = { c, w - c * 2, c }, { c, h - c * 2, c }
  local i = 0
  for row = 1, 3 do
    for col = 1, 3 do
      i = i + 1
      local sz = (col == 2) and q.mid or q.c
      local sy = (row == 2) and q.mid or q.c
      if ws[col] > 0 and hs[row] > 0 then
        love.graphics.draw(img, q[i], xs[col], ys[row], 0, ws[col] / sz, hs[row] / sy)
      end
    end
  end
end

-- A texture repeating along a bent line. flat: x1, y1, x2, y2, ...; tileLength: world units per repeat.
function Assets.strip(name, flat, width, tileLength)
  local img = Assets.image(name)
  if not img or #flat < 4 then return end
  img:setWrap("repeat", "clamp")
  local n = #flat / 2
  local verts, u = {}, 0
  for i = 1, n do
    local x, y = flat[i * 2 - 1], flat[i * 2]
    local px, py = flat[math.max(1, i - 1) * 2 - 1], flat[math.max(1, i - 1) * 2]
    local qx, qy = flat[math.min(n, i + 1) * 2 - 1], flat[math.min(n, i + 1) * 2]
    local dx, dy = qx - px, qy - py
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then dx, dy, len = 1, 0, 1 end
    local nx, ny = -dy / len * width / 2, dx / len * width / 2
    if i > 1 then
      local sx, sy = x - flat[(i - 1) * 2 - 1], y - flat[(i - 1) * 2]
      u = u + math.sqrt(sx * sx + sy * sy) / tileLength
    end
    verts[#verts + 1] = { x + nx, y + ny, u, 0 }
    verts[#verts + 1] = { x - nx, y - ny, u, 1 }
  end
  local mesh = love.graphics.newMesh(verts, "strip", "stream")
  mesh:setTexture(img)
  love.graphics.draw(mesh)
end

return Assets
