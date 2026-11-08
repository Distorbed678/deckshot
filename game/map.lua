-- Arenas (lists of solid rectangles) and collision helpers.
local Map = {}

local function R(x, y, w, h) return { x = x, y = y, w = w, h = h } end

-- A left/right symmetric arena (1280 wide). `half` rects are used as given and mirrored
-- around the centre line; `center` rects are used once. Spawns 1 and 3 are given for the
-- left side, 2 and 4 are their mirror images.
local function Sym(name, spawnA, spawnB, half, center)
  local rects = {}
  for _, r in ipairs(half) do
    rects[#rects + 1] = r
    rects[#rects + 1] = R(1280 - r.x - r.w, r.y, r.w, r.h)
  end
  for _, r in ipairs(center or {}) do rects[#rects + 1] = r end
  return {
    name = name,
    spawns = { spawnA, { 1280 - spawnA[1], spawnA[2] }, spawnB, { 1280 - spawnB[1], spawnB[2] } },
    rects = rects,
  }
end

Map.list = {
  {
    name = "Classic",
    spawns = { { 300, 520 }, { 980, 520 }, { 360, 370 }, { 920, 370 } },
    rects = {
      R(140, 560, 1000, 40),
      R(600, 500, 80, 60),
      R(260, 410, 200, 20),
      R(820, 410, 200, 20),
      R(540, 280, 200, 20),
    },
  },
  {
    name = "Islands",
    spawns = { { 200, 540 }, { 1080, 540 }, { 350, 380 }, { 930, 380 } },
    rects = {
      R(80, 580, 300, 40),
      R(540, 500, 200, 40),
      R(900, 580, 300, 40),
      R(280, 420, 140, 20),
      R(860, 420, 140, 20),
      R(540, 320, 200, 20),
    },
  },
  {
    name = "The Pit",
    spawns = { { 220, 560 }, { 1060, 560 }, { 330, 290 }, { 950, 290 } },
    rects = {
      R(100, 600, 1080, 40),
      R(100, 180, 40, 420),
      R(1140, 180, 40, 420),
      R(600, 560, 80, 40),
      R(500, 450, 280, 20),
      R(260, 330, 140, 20),
      R(880, 330, 140, 20),
    },
  },
  {
    name = "The Box",
    spawns = { { 180, 600 }, { 1100, 600 }, { 250, 330 }, { 1030, 330 } },
    rects = {
      R(60, 640, 1160, 40),
      R(60, 40, 1160, 30),
      R(60, 70, 30, 570),
      R(1190, 70, 30, 570),
      R(360, 500, 140, 24),
      R(780, 500, 140, 24),
      R(570, 370, 140, 24),
      R(200, 370, 100, 24),
      R(980, 370, 100, 24),
    },
  },
  {
    name = "Pillars",
    spawns = { { 200, 560 }, { 1080, 560 }, { 500, 430 }, { 780, 430 } },
    rects = {
      R(120, 600, 1040, 40),
      R(300, 440, 40, 160),
      R(620, 380, 40, 220),
      R(940, 440, 40, 160),
      R(440, 470, 120, 16),
      R(720, 470, 120, 16),
      R(560, 260, 160, 16),
    },
  },
  {
    name = "Staircase",
    spawns = { { 160, 580 }, { 1120, 580 }, { 260, 340 }, { 1020, 340 } },
    rects = {
      R(80, 620, 240, 30),
      R(320, 540, 160, 30),
      R(480, 460, 320, 30),
      R(800, 540, 160, 30),
      R(960, 620, 240, 30),
      R(200, 380, 120, 16),
      R(960, 380, 120, 16),
      R(580, 300, 120, 16),
    },
  },
  {
    name = "The Bridge",
    spawns = { { 180, 480 }, { 1100, 480 }, { 270, 320 }, { 1010, 320 } },
    rects = {
      R(60, 520, 260, 200),
      R(960, 520, 260, 200),
      R(420, 520, 440, 16),
      R(60, 300, 24, 220),
      R(1196, 300, 24, 220),
      R(200, 360, 140, 16),
      R(940, 360, 140, 16),
      R(570, 330, 140, 16),
    },
  },
  {
    name = "The Cage",
    spawns = { { 200, 580 }, { 1080, 580 }, { 300, 430 }, { 980, 430 } },
    rects = {
      R(100, 620, 1080, 40),
      R(500, 320, 280, 20),
      R(500, 340, 20, 180),
      R(760, 340, 20, 180),
      R(560, 470, 160, 16),
      R(220, 470, 160, 16),
      R(900, 470, 160, 16),
      R(320, 330, 100, 16),
      R(860, 330, 100, 16),
    },
  },
  {
    name = "Skyward",
    spawns = { { 200, 540 }, { 1080, 540 }, { 350, 380 }, { 930, 380 } },
    rects = {
      R(120, 580, 160, 20),
      R(1000, 580, 160, 20),
      R(400, 520, 140, 20),
      R(740, 520, 140, 20),
      R(580, 420, 120, 20),
      R(260, 400, 120, 20),
      R(900, 400, 120, 20),
      R(420, 290, 120, 20),
      R(740, 290, 120, 20),
      R(580, 180, 120, 20),
    },
  },
  {
    name = "The Divide",
    spawns = { { 220, 560 }, { 1060, 560 }, { 240, 300 }, { 1040, 300 } },
    rects = {
      R(100, 600, 1080, 40),
      R(615, 330, 50, 270),
      R(380, 470, 140, 16),
      R(760, 470, 140, 16),
      R(180, 340, 120, 16),
      R(980, 340, 120, 16),
    },
  },

  -- v0.3 arenas (symmetric)
  Sym("Twin Towers", { 220, 560 }, { 360, 260 },
    { R(330, 300, 60, 300), R(470, 460, 120, 16) },
    { R(140, 600, 1000, 40), R(560, 330, 160, 16) }),
  Sym("Gauntlet", { 180, 560 }, { 340, 440 },
    { R(260, 480, 160, 16), R(460, 224, 24, 140) },
    { R(80, 600, 1120, 40), R(80, 200, 1120, 24), R(560, 400, 160, 16) }),
  Sym("Floating Isles", { 200, 520 }, { 280, 290 },
    { R(100, 560, 220, 30), R(400, 450, 140, 20), R(220, 330, 120, 20) },
    { R(560, 520, 160, 30), R(570, 250, 140, 20) }),
  Sym("The Ring", { 240, 580 }, { 380, 440 },
    { R(140, 260, 30, 360), R(320, 480, 140, 16) },
    { R(140, 620, 1000, 30), R(340, 140, 600, 24), R(540, 360, 200, 16) }),
  Sym("Ramparts", { 150, 480 }, { 470, 390 },
    { R(60, 520, 180, 100), R(240, 560, 120, 60), R(420, 430, 120, 16) },
    { R(60, 620, 1160, 40), R(590, 320, 100, 16), R(620, 560, 40, 60) }),
  Sym("Sky Bridge", { 200, 400 }, { 260, 260 },
    { R(60, 440, 280, 280), R(200, 300, 120, 16) },
    { R(340, 440, 600, 12), R(580, 280, 120, 16), R(540, 620, 200, 20) }),
  Sym("Crossfire", { 180, 560 }, { 320, 260 },
    { R(250, 500, 140, 16), R(420, 400, 140, 16), R(250, 300, 140, 16) },
    { R(100, 600, 1080, 40), R(570, 300, 140, 16) }),
  Sym("The Well", { 200, 540 }, { 170, 260 },
    { R(100, 580, 420, 40), R(240, 440, 140, 16), R(120, 300, 100, 16) },
    { R(520, 690, 240, 30), R(560, 380, 160, 16) }),
  Sym("Zigzag", { 300, 600 }, { 220, 290 },
    { R(100, 520, 200, 16), R(380, 430, 160, 16), R(140, 330, 160, 16) },
    { R(200, 640, 880, 30), R(560, 500, 160, 16), R(580, 240, 120, 16) }),
  Sym("Fortress", { 200, 580 }, { 340, 300 },
    { R(520, 420, 24, 200), R(240, 500, 140, 16), R(280, 340, 120, 16) },
    { R(120, 620, 1040, 40), R(520, 400, 240, 20) }),
  Sym("Pinball", { 180, 590 }, { 270, 290 },
    { R(250, 520, 40, 40), R(420, 440, 40, 40), R(250, 330, 40, 40), R(130, 420, 40, 40) },
    { R(100, 630, 1080, 30), R(620, 350, 40, 40), R(600, 520, 80, 20) }),
  Sym("Overpass", { 160, 580 }, { 300, 340 },
    { R(240, 380, 320, 20), R(100, 500, 120, 16) },
    { R(80, 620, 1120, 30), R(590, 250, 100, 16) }),
  Sym("Canyon", { 160, 380 }, { 460, 480 },
    { R(60, 420, 220, 300), R(380, 520, 120, 16), R(120, 280, 100, 16) },
    { R(280, 640, 720, 40), R(560, 420, 160, 16) }),
  Sym("Lighthouse", { 200, 560 }, { 440, 320 },
    { R(260, 480, 160, 16), R(380, 360, 120, 16) },
    { R(100, 600, 1080, 40), R(610, 250, 60, 350), R(570, 230, 140, 20) }),
  Sym("Stepping Stones", { 150, 540 }, { 150, 260 },
    { R(80, 580, 140, 30), R(300, 520, 100, 20), R(460, 440, 90, 20), R(280, 360, 90, 20), R(100, 300, 100, 20) },
    { R(590, 560, 100, 24), R(590, 300, 100, 20) }),
}

-- Stable index per map (sent over the network) and a name-based id (settings file).
Map.byId = {}
for i, m in ipairs(Map.list) do
  m.index = i
  m.id = m.name:lower():gsub("[^%w]+", "_")
  Map.byId[m.id] = m
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
