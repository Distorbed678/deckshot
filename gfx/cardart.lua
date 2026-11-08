-- Card art, drawn in code: a medallion with a motif (and an optional small badge) on every card,
-- plus the foil, glow and sparkles of the rarer cards.
-- A card file picks its art with "art <motif> [<badge>] [<tint>]", e.g. "art bullet up fire".
-- Cards without an art line (older custom cards) get one guessed from what they do.
-- Motifs draw in a -1..1 box. Nothing here uses love.graphics.line: line smoothing doesn't scale.
local g = love.graphics

local CardArt = {}

CardArt.TINTS = {
  fire = { 1, 0.55, 0.15 }, ice = { 0.45, 0.85, 1 }, toxic = { 0.5, 0.95, 0.35 }, void = { 0.72, 0.45, 1 },
  gold = { 1, 0.8, 0.25 }, blood = { 1, 0.3, 0.35 }, volt = { 1, 0.95, 0.35 }, steel = { 0.66, 0.72, 0.82 },
  sky = { 0.4, 0.7, 1 }, pink = { 1, 0.45, 0.75 },
}
CardArt.TINT_NAMES = { "fire", "ice", "toxic", "void", "gold", "blood", "volt", "steel", "sky", "pink" }

local INK, DARK = { 0.96, 0.96, 1 }, { 0.1, 0.1, 0.14 }
local A = INK -- the current accent colour
local PI = math.pi

local function ink() g.setColor(INK) end
local function acc() g.setColor(A) end
local function dark() g.setColor(DARK) end
local function disc(x, y, r) g.circle("fill", x, y, r, 28) end
local function box(x, y, w, h, r) if r then g.rectangle("fill", x, y, w, h, r, r, 8) else g.rectangle("fill", x, y, w, h) end end
local tri = g.polygon

-- A thick segment with round ends.
local function seg(x1, y1, x2, y2, w)
  local dx, dy = x2 - x1, y2 - y1
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 1e-6 then return end
  local nx, ny = -dy / d * w / 2, dx / d * w / 2
  g.polygon("fill", x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny)
  g.circle("fill", x1, y1, w / 2, 12)
  g.circle("fill", x2, y2, w / 2, 12)
end
local function path(w, ...)
  local p = { ... }
  for i = 1, #p - 3, 2 do seg(p[i], p[i + 1], p[i + 2], p[i + 3], w) end
end
local function arc(x, y, r, w, a1, a2)
  local n, px, py = math.max(4, math.ceil(math.abs(a2 - a1) / 0.22))
  for i = 0, n do
    local a = a1 + (a2 - a1) * i / n
    local qx, qy = x + math.cos(a) * r, y + math.sin(a) * r
    if px then seg(px, py, qx, qy, w) end
    px, py = qx, qy
  end
end
-- A star or cog as a fan of triangles around its centre.
local function star(x, y, n, R, r, rot)
  rot = rot or 0
  local step = PI / n
  for i = 0, 2 * n - 1 do
    local a1, a2 = rot + i * step, rot + (i + 1) * step
    local r1, r2 = i % 2 == 0 and R or r, i % 2 == 0 and r or R
    tri("fill", x, y, x + math.cos(a1) * r1, y + math.sin(a1) * r1, x + math.cos(a2) * r2, y + math.sin(a2) * r2)
  end
end
local function spiral(r0, r1, turns, w, a0)
  local px, py
  local n = math.ceil(turns * 26)
  for i = 0, n do
    local k = i / n
    local a, r = (a0 or 0) + k * turns * 2 * PI, r0 + (r1 - r0) * k
    local qx, qy = math.cos(a) * r, math.sin(a) * r
    if px then seg(px, py, qx, qy, w) end
    px, py = qx, qy
  end
end
local function at(x, y, s, a, f)
  g.push()
  g.translate(x, y)
  g.rotate(a or 0)
  g.scale(s, s)
  f()
  g.pop()
end

local M = {}
CardArt.MOTIFS = M

function M.bullet()
  at(0, 0, 1, -PI / 4, function()
    ink()
    box(-0.8, -0.3, 0.95, 0.6, 0.05)
    tri("fill", 0.15, -0.3, 0.55, -0.22, 0.9, 0, 0.55, 0.22, 0.15, 0.3)
    acc()
    box(-0.8, -0.3, 0.26, 0.6)
    dark()
    box(0.1, -0.3, 0.06, 0.6)
  end)
end
function M.bullets()
  at(-0.3, -0.5, 0.6, 0, M.bullet)
  at(0.4, -0.1, 0.6, 0, M.bullet)
  at(-0.35, 0.45, 0.6, 0, M.bullet)
end
function M.spread()
  for _, a in ipairs({ -0.72, 0, 0.72 }) do at(-0.62, 0, 1, a, function()
    at(0.98, 0, 0.5, PI / 4, M.bullet)
  end) end
  acc()
  disc(-0.62, 0, 0.26)
end
function M.orb()
  ink()
  disc(0, 0, 0.74)
  acc()
  disc(0.16, 0.16, 0.52)
  ink()
  disc(-0.26, -0.26, 0.15)
end
function M.rocket()
  at(0, 0, 1, -PI / 4, function()
    acc()
    tri("fill", -0.55, -0.3, -0.92, -0.62, -0.32, -0.3)
    tri("fill", -0.55, 0.3, -0.92, 0.62, -0.32, 0.3)
    tri("fill", 0.42, -0.3, 1, 0, 0.42, 0.3)
    ink()
    box(-0.6, -0.3, 1.05, 0.6, 0.1)
    dark()
    disc(0.08, 0, 0.16)
  end)
end
function M.bomb()
  acc()
  arc(0.52, -0.36, 0.34, 0.1, PI, 1.6 * PI)
  disc(0.72, -0.7, 0.17)
  ink()
  at(0.32, -0.46, 1, PI / 4, function() box(-0.2, -0.17, 0.4, 0.3, 0.05) end)
  disc(-0.08, 0.18, 0.7)
  dark()
  disc(-0.34, -0.06, 0.13)
end
function M.burst()
  acc()
  star(0, 0, 8, 0.98, 0.5, 0.2)
  ink()
  star(0, 0, 8, 0.58, 0.28, 0.45)
end
M.hit = M.burst
function M.mine()
  ink()
  for i = 0, 7 do
    local a = i * PI / 4
    seg(math.cos(a) * 0.5, math.sin(a) * 0.5, math.cos(a) * 0.88, math.sin(a) * 0.88, 0.16)
  end
  disc(0, 0, 0.6)
  acc()
  disc(0, 0, 0.26)
end
function M.laser()
  g.setColor(A[1], A[2], A[3], 0.45)
  seg(-0.9, 0.62, 0.72, -0.5, 0.42)
  acc()
  seg(-0.9, 0.62, 0.72, -0.5, 0.24)
  ink()
  seg(-0.9, 0.62, 0.72, -0.5, 0.09)
  star(0.68, -0.47, 5, 0.42, 0.14, 0.3)
end
function M.gun()
  ink()
  tri("fill", -0.62, -0.05, -0.1, -0.05, -0.22, 0.78, -0.76, 0.78)
  box(-0.78, -0.48, 1.65, 0.46, 0.06)
  acc()
  box(0.62, -0.48, 0.25, 0.46, 0.04)
  arc(0.02, 0.06, 0.2, 0.09, 0.1, PI * 0.9)
  dark()
  box(-0.6, -0.36, 0.95, 0.07)
end
function M.cannon()
  at(0, -0.12, 1, -0.38, function()
    ink()
    box(-0.8, -0.34, 1.5, 0.68, 0.12)
    acc()
    box(0.62, -0.42, 0.22, 0.84, 0.05)
    box(-0.42, -0.34, 0.14, 0.68)
  end)
  acc()
  disc(-0.22, 0.56, 0.36)
  dark()
  disc(-0.22, 0.56, 0.13)
end
function M.mag()
  ink()
  tri("fill", -0.42, -0.86, 0.3, -0.86, 0.5, 0.88, -0.26, 0.88)
  acc()
  disc(-0.05, -0.8, 0.26)
  dark()
  for i = 0, 2 do seg(-0.2 + i * 0.03, -0.35 + i * 0.4, 0.2 + i * 0.03, -0.35 + i * 0.4, 0.09) end
end
function M.heart()
  acc()
  disc(-0.4, -0.26, 0.48)
  disc(0.4, -0.26, 0.48)
  tri("fill", -0.84, 0, 0.84, 0, 0, 0.94)
  box(-0.4, -0.3, 0.8, 0.4)
  ink()
  disc(-0.46, -0.4, 0.14)
end
function M.shield()
  ink()
  tri("fill", -0.76, -0.7, 0, -0.94, 0.76, -0.7, 0.72, 0.15, 0.42, 0.62, 0, 0.94, -0.42, 0.62, -0.72, 0.15)
  acc()
  tri("fill", 0, -0.94, 0.76, -0.7, 0.72, 0.15, 0.42, 0.62, 0, 0.94)
end
function M.armor()
  ink()
  tri("fill", -0.88, -0.6, -0.36, -0.86, 0.36, -0.86, 0.88, -0.6, 0.66, -0.05, 0.56, 0.86, -0.56, 0.86, -0.66, -0.05)
  dark()
  disc(0, -0.86, 0.32)
  acc()
  box(-0.08, -0.5, 0.16, 1.36)
  box(-0.5, 0.2, 1, 0.14)
end
function M.skull()
  ink()
  disc(0, -0.18, 0.72)
  box(-0.4, 0.3, 0.8, 0.54, 0.08)
  dark()
  disc(-0.3, -0.18, 0.2)
  disc(0.3, -0.18, 0.2)
  tri("fill", 0, 0.08, -0.12, 0.3, 0.12, 0.3)
  box(-0.17, 0.52, 0.07, 0.32)
  box(0.1, 0.52, 0.07, 0.32)
  acc()
  disc(-0.3, -0.18, 0.08)
  disc(0.3, -0.18, 0.08)
end
function M.fist()
  ink()
  box(-0.62, -0.32, 1.26, 1.1, 0.2)
  for i = 0, 3 do box(-0.62 + i * 0.32, -0.74, 0.3, 0.7, 0.12) end
  dark()
  for i = 1, 3 do box(-0.63 + i * 0.32, -0.7, 0.04, 0.62) end
  acc()
  box(-0.8, -0.02, 0.98, 0.34, 0.14)
end
function M.bat()
  at(0, 0, 1, -PI / 4, function()
    ink()
    tri("fill", -0.6, -0.1, 0.4, -0.24, 0.98, -0.25, 0.98, 0.25, 0.4, 0.24, -0.6, 0.1)
    acc()
    box(-1, -0.11, 0.5, 0.22, 0.05)
  end)
end
function M.blade()
  at(0, 0, 1, -PI / 4, function()
    ink()
    tri("fill", -0.36, -0.15, 0.76, -0.15, 1.02, 0, 0.76, 0.15, -0.36, 0.15)
    acc()
    box(-0.44, -0.42, 0.14, 0.84, 0.05)
    box(-0.88, -0.09, 0.48, 0.18)
  end)
end
function M.axe()
  ink()
  seg(-0.66, 0.82, 0.34, -0.66, 0.15)
  acc()
  tri("fill", 0.06, -0.84, 0.56, -0.94, 0.94, -0.52, 0.86, 0.04, 0.3, -0.26)
end
function M.boot()
  ink()
  box(-0.52, -0.86, 0.66, 1.1)
  box(-0.52, 0.08, 1.3, 0.52, 0.2)
  acc()
  box(-0.58, 0.54, 1.42, 0.22, 0.05)
  dark()
  seg(-0.25, -0.5, 0.15, -0.5, 0.08)
  seg(-0.25, -0.2, 0.15, -0.2, 0.08)
end
function M.wing()
  ink()
  tri("fill", -0.74, 0.3, -0.42, -0.36, 0.96, -0.82, 0.56, -0.1)
  acc()
  tri("fill", -0.74, 0.3, -0.2, -0.05, 0.76, -0.25, 0.36, 0.3)
  ink()
  tri("fill", -0.74, 0.3, -0.2, 0.25, 0.5, 0.32, 0.1, 0.72, -0.5, 0.72)
end
function M.spring()
  acc()
  box(-0.62, -0.92, 1.24, 0.2, 0.06)
  box(-0.62, 0.72, 1.24, 0.2, 0.06)
  ink()
  path(0.17, -0.5, -0.72, 0.5, -0.45, -0.5, -0.18, 0.5, 0.09, -0.5, 0.36, 0.5, 0.72)
end
function M.feather()
  at(0, 0, 1, PI / 4, function()
    ink()
    g.ellipse("fill", 0, -0.14, 0.42, 0.78, 26)
    dark()
    seg(-0.42, -0.3, -0.14, -0.14, 0.07)
    seg(0.42, 0.14, 0.14, 0, 0.07)
    acc()
    seg(0, -0.72, 0, 0.98, 0.09)
  end)
end
function M.dash()
  g.setColor(A[1], A[2], A[3], 0.5)
  path(0.24, -0.82, -0.62, -0.38, 0, -0.82, 0.62)
  acc()
  path(0.24, -0.36, -0.62, 0.08, 0, -0.36, 0.62)
  ink()
  path(0.24, 0.12, -0.62, 0.56, 0, 0.12, 0.62)
end
function M.volt()
  acc()
  tri("fill", 0.3, -0.96, -0.6, 0.15, -0.02, 0.15)
  tri("fill", 0.3, -0.96, -0.02, 0.15, 0.1, -0.15)
  tri("fill", -0.3, 0.96, 0.6, -0.15, 0.02, -0.15)
  tri("fill", -0.3, 0.96, 0.02, -0.15, -0.1, 0.15)
  ink()
  tri("fill", 0.18, -0.54, -0.28, 0.08, 0.04, 0.08)
end
function M.snow()
  for i = 0, 2 do at(0, 0, 1, i * PI / 3, function()
    ink()
    seg(0, -0.92, 0, 0.92, 0.13)
    acc()
    path(0.11, -0.3, -0.84, 0, -0.56, 0.3, -0.84)
    path(0.11, -0.3, 0.84, 0, 0.56, 0.3, 0.84)
  end) end
end
function M.drop()
  acc()
  disc(0, 0.26, 0.64)
  tri("fill", -0.6, 0.04, 0, -0.98, 0.6, 0.04)
  ink()
  disc(-0.24, 0.32, 0.14)
end
function M.flame()
  acc()
  disc(0, 0.32, 0.62)
  tri("fill", -0.6, 0.18, -0.36, -0.4, -0.18, -0.14, 0.12, -0.98, 0.42, -0.24, 0.6, 0.14)
  ink()
  disc(0, 0.46, 0.34)
  tri("fill", -0.32, 0.36, 0.05, -0.28, 0.32, 0.36)
end
function M.ghost()
  ink()
  disc(0, -0.22, 0.68)
  box(-0.68, -0.22, 1.36, 0.92)
  dark()
  for i = -1, 1 do tri("fill", i * 0.46 - 0.2, 0.74, i * 0.46 + 0.2, 0.74, i * 0.46, 0.48) end
  acc()
  disc(-0.26, -0.22, 0.15)
  disc(0.26, -0.22, 0.15)
end
function M.eye()
  ink()
  g.ellipse("fill", 0, 0, 0.98, 0.58, 28)
  acc()
  disc(0, 0, 0.42)
  dark()
  disc(0, 0, 0.2)
  ink()
  disc(0.13, -0.13, 0.08)
end
function M.clock()
  ink()
  disc(0, 0, 0.88)
  dark()
  seg(0, 0, 0, -0.58, 0.15)
  acc()
  seg(0, 0, 0.42, 0.22, 0.15)
  dark()
  disc(0, 0, 0.1)
end
function M.hourglass()
  acc()
  tri("fill", -0.56, -0.74, 0.56, -0.74, 0, -0.02)
  tri("fill", -0.56, 0.74, 0.56, 0.74, 0, 0.02)
  ink()
  box(-0.72, -0.94, 1.44, 0.22, 0.07)
  box(-0.72, 0.72, 1.44, 0.22, 0.07)
end
function M.star()
  acc()
  star(0, 0, 5, 1, 0.44, -PI / 2)
  ink()
  star(0, 0, 5, 0.46, 0.2, -PI / 2)
end
function M.crown()
  acc()
  tri("fill", -0.82, -0.46, -0.82, 0.62, -0.1, 0.62)
  tri("fill", 0.82, -0.46, 0.82, 0.62, 0.1, 0.62)
  tri("fill", 0, -0.66, -0.56, 0.62, 0.56, 0.62)
  ink()
  disc(-0.82, -0.52, 0.14)
  disc(0.82, -0.52, 0.14)
  disc(0, -0.74, 0.16)
  box(-0.86, 0.6, 1.72, 0.24, 0.05)
end
function M.dice()
  at(0, 0, 1, 0.16, function()
    ink()
    box(-0.76, -0.76, 1.52, 1.52, 0.24)
    dark()
    for _, p in ipairs({ { -0.4, -0.4 }, { 0.4, -0.4 }, { -0.4, 0.4 }, { 0.4, 0.4 } }) do disc(p[1], p[2], 0.15) end
    acc()
    disc(0, 0, 0.18)
  end)
end
function M.card()
  at(-0.2, 0, 1, -0.24, function()
    acc()
    box(-0.5, -0.74, 1, 1.48, 0.12)
  end)
  at(0.22, 0.04, 1, 0.16, function()
    ink()
    box(-0.5, -0.74, 1, 1.48, 0.12)
    acc()
    star(0, 0, 4, 0.34, 0.12)
  end)
end
function M.orbit()
  acc()
  arc(0, 0, 0.76, 0.08, 0, 2 * PI)
  ink()
  disc(0, 0, 0.34)
  for i = 0, 2 do
    local a = i * 2 * PI / 3 - 0.5
    disc(math.cos(a) * 0.76, math.sin(a) * 0.76, 0.2)
  end
end
function M.blackhole()
  acc()
  spiral(0.3, 0.98, 0.9, 0.13, 0)
  spiral(0.3, 0.98, 0.9, 0.13, PI)
  ink()
  arc(0, 0, 0.38, 0.09, 0, 2 * PI)
  g.setColor(0, 0, 0)
  disc(0, 0, 0.34)
end
function M.swirl()
  ink()
  spiral(0.08, 0.86, 2.1, 0.17, 0)
  acc()
  disc(0, 0, 0.14)
end
function M.target()
  acc()
  arc(0, 0, 0.66, 0.15, 0, 2 * PI)
  ink()
  seg(-0.96, 0, -0.34, 0, 0.13)
  seg(0.34, 0, 0.96, 0, 0.13)
  seg(0, -0.96, 0, -0.34, 0.13)
  seg(0, 0.34, 0, 0.96, 0.13)
  disc(0, 0, 0.13)
end
function M.magnet()
  acc()
  arc(0, -0.05, 0.56, 0.36, 0, PI)
  box(-0.74, -0.42, 0.36, 0.4)
  box(0.38, -0.42, 0.36, 0.4)
  ink()
  box(-0.74, -0.82, 0.36, 0.4)
  box(0.38, -0.82, 0.36, 0.4)
end
function M.mirror()
  acc()
  seg(0.48, -0.9, 0.48, 0.9, 0.24)
  ink()
  path(0.16, -0.86, -0.72, 0.22, 0, -0.86, 0.72)
  tri("fill", -0.98, 0.42, -0.58, 0.56, -0.92, 0.92)
end
function M.turret()
  acc()
  box(-0.1, -0.5, 1.04, 0.3, 0.06)
  ink()
  disc(-0.1, -0.34, 0.5)
  tri("fill", -0.14, 0, -0.76, 0.86, 0.56, 0.86)
  dark()
  disc(-0.1, -0.34, 0.16)
end
function M.crate()
  ink()
  box(-0.82, -0.82, 1.64, 1.64, 0.08)
  dark()
  box(-0.66, -0.66, 1.32, 1.32)
  acc()
  seg(-0.6, 0.6, 0.6, -0.6, 0.24)
  ink()
  box(-0.66, -0.12, 0, 0)
end
function M.hand()
  ink()
  box(-0.52, -0.08, 1.04, 1, 0.22)
  for i = 0, 3 do box(-0.52 + i * 0.27, -0.84 + (i == 1 and -0.08 or i == 2 and -0.04 or 0), 0.23, 1.1, 0.1) end
  acc()
  at(0.4, 0.3, 1, -0.7, function() box(0, -0.15, 0.66, 0.3, 0.13) end)
end
function M.moon()
  ink()
  disc(0, 0, 0.82)
  dark()
  disc(0.36, -0.16, 0.7)
  acc()
  star(0.46, -0.26, 4, 0.3, 0.09)
end
function M.bone()
  ink()
  seg(-0.55, 0.55, 0.55, -0.55, 0.3)
  for _, p in ipairs({ { -0.8, 0.48 }, { -0.48, 0.8 }, { 0.8, -0.48 }, { 0.48, -0.8 } }) do disc(p[1], p[2], 0.25) end
end
function M.thorns()
  ink()
  star(0, 0, 11, 1, 0.58)
  dark()
  disc(0, 0, 0.46)
  acc()
  disc(0, 0, 0.32)
end
function M.wall()
  for row = 0, 2 do
    local y = -0.84 + row * 0.58
    local off = row % 2 == 1 and -0.42 or 0
    for c = 0, 2 do
      local x = -0.84 + c * 0.86 + off
      local x0, x1 = math.max(-0.84, x), math.min(0.84, x + 0.8)
      if x1 > x0 + 0.1 then
        if (row + c) % 3 == 1 then acc() else ink() end
        box(x0, y, x1 - x0, 0.52, 0.05)
      end
    end
  end
end
function M.wave()
  ink()
  disc(0, 0.62, 0.22)
  box(-0.92, 0.72, 1.84, 0.16, 0.05)
  acc()
  arc(0, 0.62, 0.52, 0.13, PI * 1.08, PI * 1.92)
  arc(0, 0.62, 0.94, 0.13, PI * 1.08, PI * 1.92)
  g.setColor(A[1], A[2], A[3], 0.55)
  arc(0, 0.62, 1.36, 0.13, PI * 1.22, PI * 1.78)
end
function M.fang()
  acc()
  box(-0.88, -0.92, 1.76, 0.3, 0.1)
  ink()
  tri("fill", -0.78, -0.66, -0.08, -0.66, -0.44, 0.84)
  tri("fill", 0.08, -0.66, 0.78, -0.66, 0.44, 0.84)
end
function M.hydra()
  acc()
  path(0.2, 0, 0.9, 0, 0.1, -0.1, -0.5)
  path(0.2, 0, 0.5, -0.62, 0.16, -0.72, -0.3)
  path(0.2, 0, 0.5, 0.62, 0.16, 0.72, -0.3)
  ink()
  disc(-0.1, -0.62, 0.26)
  disc(-0.74, -0.42, 0.26)
  disc(0.74, -0.42, 0.26)
end
function M.phoenix()
  acc()
  tri("fill", -0.08, 0.1, -0.98, -0.78, -0.72, 0.38)
  tri("fill", 0.08, 0.1, 0.98, -0.78, 0.72, 0.38)
  tri("fill", -0.3, 0.2, 0, 1, 0.3, 0.2)
  ink()
  disc(0, -0.05, 0.34)
  disc(0, -0.5, 0.24)
  dark()
  disc(0.06, -0.54, 0.06)
end
function M.shrine()
  ink()
  tri("fill", -0.92, -0.5, 0, -0.98, 0.92, -0.5)
  box(-0.84, -0.46, 1.68, 0.16)
  box(-0.84, 0.72, 1.68, 0.2, 0.04)
  acc()
  for i = -1, 1 do box(i * 0.56 - 0.13, -0.26, 0.26, 0.94) end
end
function M.seek()
  ink()
  arc(-0.14, 0.32, 0.62, 0.17, PI * 0.72, PI * 1.82)
  tri("fill", 0.26, -0.48, 0.86, -0.36, 0.42, 0.14)
  acc()
  disc(0.66, 0.54, 0.26)
  dark()
  disc(0.66, 0.54, 0.09)
end
function M.fork()
  ink()
  seg(-0.9, 0, -0.1, 0, 0.17)
  seg(-0.1, 0, 0.6, -0.68, 0.14)
  seg(-0.1, 0, 0.72, 0, 0.14)
  seg(-0.1, 0, 0.6, 0.68, 0.14)
  acc()
  disc(0.64, -0.72, 0.22)
  disc(0.78, 0, 0.22)
  disc(0.64, 0.72, 0.22)
end
function M.pierce()
  ink()
  box(-0.42, -0.92, 0.2, 1.84, 0.05)
  box(0.18, -0.92, 0.2, 1.84, 0.05)
  acc()
  seg(-0.92, 0, 0.56, 0, 0.2)
  tri("fill", 0.46, -0.38, 1, 0, 0.46, 0.38)
end
function M.swap()
  ink()
  seg(-0.76, -0.38, 0.4, -0.38, 0.2)
  tri("fill", 0.32, -0.76, 0.96, -0.38, 0.32, 0)
  acc()
  seg(0.76, 0.38, -0.4, 0.38, 0.2)
  tri("fill", -0.32, 0, -0.96, 0.38, -0.32, 0.76)
end
function M.uturn()
  ink()
  arc(0.1, 0, 0.56, 0.19, -PI * 0.5, PI * 0.5)
  seg(0.1, 0.56, -0.36, 0.56, 0.19)
  seg(0.1, -0.56, -0.86, -0.56, 0.19)
  acc()
  tri("fill", -0.3, 0.14, -0.98, 0.56, -0.3, 0.98)
end
function M.bounce()
  ink()
  box(-0.98, 0.76, 1.96, 0.14, 0.05)
  arc(-0.42, 0.68, 0.52, 0.12, PI, 2 * PI)
  arc(0.36, 0.68, 0.26, 0.12, PI, 1.75 * PI)
  acc()
  disc(0.68, 0.14, 0.27)
end
function M.gear()
  ink()
  star(0, 0, 8, 0.98, 0.74, 0.15)
  dark()
  disc(0, 0, 0.34)
  acc()
  disc(0, 0, 0.17)
end
function M.weight()
  ink()
  arc(0, -0.5, 0.3, 0.14, PI, 2 * PI)
  arc(0, -0.5, 0.3, 0.14, 0, PI)
  tri("fill", -0.5, -0.3, 0.5, -0.3, 0.88, 0.88, -0.88, 0.88)
  acc()
  box(-0.62, 0.22, 1.24, 0.22)
end
function M.saw()
  ink()
  star(0, 0, 10, 0.99, 0.64, 0.2)
  acc()
  arc(0, 0, 0.4, 0.09, 0, 2 * PI)
  dark()
  disc(0, 0, 0.13)
end
function M.cloud()
  ink()
  disc(-0.46, 0.14, 0.42)
  disc(0.08, -0.18, 0.56)
  disc(0.54, 0.2, 0.38)
  box(-0.46, 0.14, 1, 0.42)
  acc()
  disc(-0.3, 0.74, 0.1)
  disc(0.1, 0.8, 0.13)
  disc(0.46, 0.74, 0.08)
end
function M.body()
  ink()
  seg(-0.26, 0.42, -0.34, 0.92, 0.15)
  seg(0.26, 0.42, 0.34, 0.92, 0.15)
  disc(0, -0.08, 0.68)
  dark()
  disc(-0.22, -0.18, 0.11)
  disc(0.22, -0.18, 0.11)
  acc()
  arc(0, 0.04, 0.26, 0.09, 0.3, PI - 0.3)
end
function M.up()
  acc()
  tri("fill", 0, -0.96, 0.8, 0, -0.8, 0)
  box(-0.32, -0.04, 0.64, 0.94)
end
function M.down()
  acc()
  tri("fill", 0, 0.96, 0.8, 0, -0.8, 0)
  box(-0.32, -0.9, 0.64, 0.94)
end
function M.plus()
  acc()
  box(-0.26, -0.9, 0.52, 1.8, 0.06)
  box(-0.9, -0.26, 1.8, 0.52, 0.06)
end
function M.minus()
  acc()
  box(-0.9, -0.28, 1.8, 0.56, 0.08)
end
function M.x2()
  ink()
  disc(-0.32, -0.28, 0.54)
  acc()
  disc(0.32, 0.28, 0.54)
end

-- Motifs an editor can offer, as a sorted list.
CardArt.NAMES = {}
for name in pairs(M) do
  if name ~= "hit" then CardArt.NAMES[#CardArt.NAMES + 1] = name end
end
table.sort(CardArt.NAMES)

-- "main [badge] [tint]" -> { main, badge, tint }, or nil if there's no known motif.
local CACHE = {}
function CardArt.parse(text)
  if not text or text == "" then return nil end
  local spec = CACHE[text]
  if spec ~= nil then return spec or nil end
  local words = {}
  for w in text:gmatch("%S+") do words[#words + 1] = w end
  spec = false
  if M[words[1]] then
    spec = { main = words[1] }
    for i = 2, #words do
      if CardArt.TINTS[words[i]] then spec.tint = words[i]
      elseif M[words[i]] and not spec.badge then spec.badge = words[i] end
    end
  end
  CACHE[text] = spec
  return spec or nil
end

-- For cards without an art line: guess from the first thing the card changes.
local GUESS = {
  { "melee", "fist" }, { "heavy", "fist" }, { "block", "shield" }, { "shield", "shield" }, { "dash", "dash" },
  { "reload", "mag" }, { "ammo", "mag" }, { "bounce", "bounce" }, { "explosion", "burst" }, { "bullets", "spread" },
  { "maxHp", "heart" }, { "armor", "armor" }, { "speed", "boot" }, { "jump", "spring" }, { "gravity", "feather" },
  { "knockback", "burst" }, { "fireDelay", "gun" }, { "spread", "spread" }, { "gun", "bullet" }, { "bullet", "bullet" },
}
local TRIGGER_GUESS = { block = "shield", dash = "dash", kill = "skull", hurt = "heart", jump = "spring", land = "wave", interval = "clock" }
local function guess(def)
  if def.triggers and def.triggers[1] then
    local m = TRIGGER_GUESS[def.triggers[1].when]
    if m then return { main = m } end
  end
  for _, r in ipairs(def.rows or {}) do
    local stat = r.stat
    for _, g2 in ipairs(GUESS) do
      if stat:lower():find(g2[1]:lower(), 1, true) then return { main = g2[2] } end
    end
  end
  return { main = "star" }
end

function CardArt.specOf(card)
  local def = card.def or {}
  return CardArt.parse(def.art) or guess(def)
end

-- The card's art: a dark medallion centred on (cx, cy). rim: the rarity's colour.
function CardArt.medal(card, cx, cy, r, rim)
  local spec = CardArt.specOf(card)
  A = spec.tint and CardArt.TINTS[spec.tint] or rim
  g.setColor(0, 0, 0, 0.3)
  g.circle("fill", cx, cy + 2, r + 2, 40)
  g.setColor(rim)
  g.circle("fill", cx, cy, r, 40)
  dark()
  g.circle("fill", cx, cy, r - 3, 40)
  at(cx, cy, r * 0.62, 0, M[spec.main])
  if spec.badge then
    local bx, by, br = cx + r * 0.68, cy + r * 0.62, r * 0.44
    g.setColor(rim)
    g.circle("fill", bx, by, br, 24)
    dark()
    g.circle("fill", bx, by, br - 2, 24)
    at(bx, by, br * 0.62, 0, M[spec.badge])
  end
  g.setColor(1, 1, 1)
end

---------------------------------------------------------------- rarity flair
local FOIL_LEVEL = { rare = 1, epic = 2, legendary = 3 }
local foilShader, foilTried, whitePixel
local FOIL = [[
extern float time;
extern float level;
extern vec2 size;
vec4 effect(vec4 c, Image tex, vec2 uv, vec2 sc) {
  vec2 p = uv * size;
  vec2 q = abs(p - size * 0.5) - (size * 0.5 - vec2(14.0));
  float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 14.0;
  float mask = clamp(0.5 - d, 0.0, 1.0);
  float diag = (p.x + p.y * 0.7) / (size.x + size.y * 0.7);
  float sweep = fract(time * 0.28);
  float s1 = max(0.0, 1.0 - abs(diag - (sweep * 1.8 - 0.4)) * 7.0);
  float sheen = s1 * s1;
  // The coloured band takes the full effect; the text below it only a trace.
  float body = 1.0 - 0.8 * smoothstep(76.0, 88.0, p.y);
  vec3 col = vec3(sheen) * 0.5 * body;
  if (level > 1.5) {
    vec3 rainbow = 0.5 + 0.5 * cos(6.2832 * (diag * 1.6 - time * 0.12 + vec3(0.0, 0.33, 0.67)));
    float bands = 0.5 + 0.5 * sin((p.x - p.y) * 0.16 + time * 1.4);
    float amount = level > 2.5 ? 0.3 : 0.14;
    col += rainbow * amount * (0.45 + 0.55 * bands) * body;
  }
  return vec4(col * mask, 1.0);
}
]]

local function getFoil()
  if not foilTried then
    foilTried = true
    local ok, sh = pcall(g.newShader, FOIL)
    if ok then foilShader = sh end
    local data = love.image.newImageData(1, 1)
    data:setPixel(0, 0, 1, 1, 1, 1)
    whitePixel = g.newImage(data)
  end
  return foilShader
end

local function fract(v) return v - math.floor(v) end

-- Behind the card: the soft glow of epic and legendary cards.
function CardArt.glow(x, y, w, h, rarityId, color, t)
  local n = rarityId == "legendary" and 5 or rarityId == "epic" and 3 or 0
  if n == 0 then return end
  local pulse = 0.5 + 0.5 * math.sin(t * 3)
  local top = rarityId == "legendary" and 0.16 + 0.12 * pulse or 0.09 + 0.06 * pulse
  for i = n, 1, -1 do
    local e = i * 4
    g.setColor(color[1], color[2], color[3], top * (1 - (i - 1) / n))
    g.rectangle("fill", x - e, y - e, w + e * 2, h + e * 2, 14 + e, 14 + e, 12)
  end
end

-- Over the finished card: the foil sheen and, on the rarest cards, sparkles.
function CardArt.foil(x, y, w, h, rarityId, t)
  local level = FOIL_LEVEL[rarityId]
  if not level then return end
  local shader = getFoil()
  g.setBlendMode("add", "alphamultiply")
  if shader then
    g.setShader(shader)
    shader:send("time", t % 1000)
    shader:send("level", level)
    shader:send("size", { w, h })
    g.setColor(1, 1, 1)
    g.draw(whitePixel, x, y, 0, w, h)
    g.setShader()
  end
  if level >= 2 then
    local n = level == 3 and 9 or 4
    for i = 1, n do
      local period = 1.3 + i * 0.17
      local phase = t / period + i * 0.37
      local seed = math.floor(phase)
      local k = phase - seed
      local sx = x + 12 + fract(math.sin(seed * 12.9898 + i * 78.233) * 43758.5453) * (w - 24)
      local sy = y + 8 + fract(math.sin(seed * 39.346 + i * 11.135) * 24634.6345) * 74 -- in the band, off the text
      local size = (3 + i % 3 * 2) * math.sin(k * PI)
      g.setColor(1, 1, 1, 0.9 * math.sin(k * PI))
      star(sx, sy, 4, size * 1.5, size * 0.28, 0.4)
    end
  end
  g.setBlendMode("alpha")
  g.setColor(1, 1, 1)
end

return CardArt
