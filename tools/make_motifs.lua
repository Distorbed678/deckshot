-- Draws the v0.7 card motifs into assets/art/motif_*.svg. Run from the repo root, then
-- tools/build_art.sh. Motifs are painted in three pure colours that gfx/cardart.lua recolours:
-- red = ink (the main shape), green = the card's accent, blue = dark details on top.
local I, A, D = "#ff0000", "#00ff00", "#0000ff"
local out
local function fmt(n) return string.format("%.4f", n) end
local function add(s) out[#out + 1] = s end
local function rad(d) return d * math.pi / 180 end

local function C(x, y, r, col) add(string.format('<circle cx="%s" cy="%s" r="%s" fill="%s"/>', fmt(x), fmt(y), fmt(r), col)) end
local function RING(x, y, r, w, col) add(string.format('<circle cx="%s" cy="%s" r="%s" fill="none" stroke="%s" stroke-width="%s"/>', fmt(x), fmt(y), fmt(r), col, fmt(w))) end
local function P(col, ...)
  local p, t = {}, { ... }
  for i = 1, #t, 2 do p[#p + 1] = fmt(t[i]) .. "," .. fmt(t[i + 1]) end
  add(string.format('<polygon points="%s" fill="%s"/>', table.concat(p, " "), col))
end
local function PL(col, w, ...)
  local p, t = {}, { ... }
  for i = 1, #t, 2 do p[#p + 1] = fmt(t[i]) .. "," .. fmt(t[i + 1]) end
  add(string.format('<polyline points="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>', table.concat(p, " "), col, fmt(w)))
end
local function L(x1, y1, x2, y2, w, col) PL(col, w, x1, y1, x2, y2) end
-- A rectangle centred on (x, y), turned by rot degrees, with round corners rr.
local function R(x, y, w, h, col, rot, rr)
  add(string.format('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s" transform="rotate(%s %s %s)"/>',
    fmt(x - w / 2), fmt(y - h / 2), fmt(w), fmt(h), fmt(rr or 0), col, fmt(rot or 0), fmt(x), fmt(y)))
end
local function ARC(x, y, r, a0, a1, w, col)
  local x0, y0 = x + math.cos(rad(a0)) * r, y + math.sin(rad(a0)) * r
  local x1, y1 = x + math.cos(rad(a1)) * r, y + math.sin(rad(a1)) * r
  local large = (a1 - a0) % 360 > 180 and 1 or 0
  add(string.format('<path d="M%s %s A%s %s 0 %d 1 %s %s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round"/>',
    fmt(x0), fmt(y0), fmt(r), fmt(r), large, fmt(x1), fmt(y1), col, fmt(w)))
end
local function STAR(x, y, ro, ri, n, col, rot)
  local pts = {}
  for k = 0, n * 2 - 1 do
    local a = rad((rot or -90) + k * 180 / n)
    local r = k % 2 == 0 and ro or ri
    pts[#pts + 1] = x + math.cos(a) * r
    pts[#pts + 1] = y + math.sin(a) * r
  end
  P(col, unpack(pts))
end
-- Arrowhead at (x, y) pointing at angle a (degrees).
local function HEAD(x, y, a, s, col)
  local function pt(da, d) return x + math.cos(rad(a + da)) * d, y + math.sin(rad(a + da)) * d end
  local x1, y1 = pt(0, s)
  local x2, y2 = pt(140, s)
  local x3, y3 = pt(-140, s)
  P(col, x1, y1, x2, y2, x3, y3)
end

-- Building blocks.
local function bullet(x, y, len, w, rot, col, tip)
  add(string.format('<g transform="rotate(%s %s %s)">', fmt(rot or 0), fmt(x), fmt(y)))
  R(x - len * 0.1, y, len * 0.8, w, col, 0, w * 0.15)
  C(x + len * 0.3, y, w / 2, tip or col)
  add("</g>")
end
local function fist(x, y, s, col, rot)
  add(string.format('<g transform="rotate(%s %s %s)">', fmt(rot or 0), fmt(x), fmt(y)))
  R(x, y, 0.9 * s, 0.75 * s, col, 0, 0.18 * s)
  R(x - 0.5 * s, y + 0.1 * s, 0.3 * s, 0.4 * s, col, 0, 0.1 * s)
  for k = -1, 1 do L(x + 0.12 * s * k * 2.2, y - 0.35 * s, x + 0.12 * s * k * 2.2, y - 0.05 * s, 0.06 * s, D) end
  add("</g>")
end
local function shield(x, y, s, col, half)
  P(col, x - 0.76 * s, y - 0.7 * s, x, y - 0.94 * s, x + 0.76 * s, y - 0.7 * s, x + 0.72 * s, y + 0.15 * s, x + 0.42 * s, y + 0.62 * s, x, y + 0.94 * s,
    x - 0.42 * s, y + 0.62 * s, x - 0.72 * s, y + 0.15 * s)
  if half then P(half, x, y - 0.94 * s, x + 0.76 * s, y - 0.7 * s, x + 0.72 * s, y + 0.15 * s, x + 0.42 * s, y + 0.62 * s, x, y + 0.94 * s) end
end
local function heart(x, y, s, col)
  C(x - 0.32 * s, y - 0.2 * s, 0.36 * s, col)
  C(x + 0.32 * s, y - 0.2 * s, 0.36 * s, col)
  P(col, x - 0.66 * s, y - 0.08 * s, x + 0.66 * s, y - 0.08 * s, x, y + 0.75 * s)
end
-- A Deckshot character: a round body on two short legs, with eyes.
local function person(x, y, s, col)
  L(x - 0.2 * s, y + 0.2 * s, x - 0.24 * s, y + 0.72 * s, 0.13 * s, col)
  L(x + 0.2 * s, y + 0.2 * s, x + 0.24 * s, y + 0.72 * s, 0.13 * s, col)
  C(x, y - 0.12 * s, 0.5 * s, col)
  C(x - 0.15 * s, y - 0.2 * s, 0.07 * s, D)
  C(x + 0.15 * s, y - 0.2 * s, 0.07 * s, D)
end
local function flame(x, y, s, col, inner)
  P(col, x, y - s, x + 0.45 * s, y - 0.2 * s, x + 0.5 * s, y + 0.35 * s, x + 0.2 * s, y + 0.65 * s, x - 0.2 * s, y + 0.65 * s, x - 0.5 * s, y + 0.35 * s,
    x - 0.45 * s, y - 0.2 * s)
  if inner then P(inner, x, y - 0.3 * s, x + 0.22 * s, y + 0.2 * s, x, y + 0.55 * s, x - 0.22 * s, y + 0.2 * s) end
end
local function bolt(x, y, s, col)
  P(col, x + 0.15 * s, y - s, x - 0.45 * s, y + 0.1 * s, x - 0.05 * s, y + 0.1 * s, x - 0.2 * s, y + s, x + 0.45 * s, y - 0.15 * s, x + 0.05 * s, y - 0.15 * s)
end
local function snowflake(x, y, s, col)
  for k = 0, 2 do
    local a = rad(k * 60)
    L(x - math.cos(a) * s, y - math.sin(a) * s, x + math.cos(a) * s, y + math.sin(a) * s, 0.14 * s, col)
  end
end
local function drop(x, y, s, col)
  C(x, y + 0.25 * s, 0.45 * s, col)
  P(col, x - 0.42 * s, y + 0.1 * s, x, y - 0.8 * s, x + 0.42 * s, y + 0.1 * s)
end
local function speedlines(x, y, s, col)
  for k = -1, 1 do L(x - 0.5 * s, y + k * 0.3 * s, x + 0.2 * s - math.abs(k) * 0.2 * s, y + k * 0.3 * s, 0.1 * s, col) end
end

local M = {}
-- Guns and bullets
M.hollowpoint = function() bullet(0, 0, 1.6, 0.6, -35, I); C(0.32, -0.22, 0.14, D) end
M.reload = function() ARC(0, 0, 0.72, -60, 230, 0.18, A); HEAD(0.36, -0.62, 20, 0.26, A); bullet(0, 0.05, 0.9, 0.36, -90, I) end
M.speedbullet = function() bullet(0.25, 0, 1.2, 0.5, 0, I); speedlines(-0.45, 0, 0.9, A) end
M.slug = function() C(0.1, 0, 0.58, I); C(-0.05, -0.15, 0.2, D); L(-0.85, -0.4, -0.55, -0.25, 0.12, A); L(-0.9, 0.05, -0.55, 0.05, 0.12, A); L(-0.85, 0.5, -0.55, 0.3, 0.12, A) end
M.bigbullet = function() bullet(0, 0, 1.7, 0.95, -90, I); R(0, 0.35, 0.95, 0.12, D) end
M.straight = function() L(-0.85, 0, 0.6, 0, 0.16, A); HEAD(0.85, 0, 0, 0.32, A); bullet(-0.1, -0.45, 0.9, 0.32, 0, I) end
M.trigger = function() R(0, -0.35, 1.5, 0.42, I, 0, 0.08); ARC(0.05, 0.1, 0.32, 0, 180, 0.12, I); L(0.05, -0.1, -0.05, 0.3, 0.14, A); R(-0.55, 0.15, 0.32, 0.55, I, 12, 0.08) end
M.pinball = function() C(0.35, -0.45, 0.32, I); C(0.27, -0.53, 0.1, D); R(-0.2, 0.55, 0.9, 0.2, A, -18, 0.1); R(0.55, 0.55, 0.5, 0.2, A, 18, 0.1) end
M.icebullet = function() bullet(-0.1, 0.15, 1.3, 0.5, -20, I); snowflake(0.55, -0.45, 0.32, A) end
M.venom = function() bullet(-0.1, -0.2, 1.3, 0.5, 0, I); drop(0.45, 0.45, 0.4, A); drop(0.05, 0.6, 0.28, A) end
M.push = function() bullet(-0.35, 0, 1, 0.46, 0, I); ARC(0.25, 0, 0.35, -60, 60, 0.12, A); ARC(0.25, 0, 0.6, -50, 50, 0.12, A) end
M.heatgun = function() R(-0.1, 0.05, 1.3, 0.42, I, 0, 0.08); R(-0.55, 0.4, 0.3, 0.55, I, 10, 0.08); for k = -1, 1 do PL(A, 0.1, k * 0.3, -0.3, k * 0.3 + 0.1, -0.5, k * 0.3 - 0.05, -0.68, k * 0.3 + 0.05, -0.85) end end
M.spingun = function() R(0, 0, 0.9, 0.3, I, -30, 0.06); R(-0.25, 0.15, 0.22, 0.4, I, -30, 0.06); ARC(0, 0, 0.75, 200, 340, 0.12, A); HEAD(0.7, -0.27, 80, 0.22, A); ARC(0, 0, 0.75, 20, 160, 0.12, A); HEAD(-0.7, 0.27, 260, 0.22, A) end
M.hose = function() for k = -1, 1 do R(0.1, k * 0.25, 1.4, 0.18, I, 0, 0.06) end; R(-0.55, 0, 0.35, 0.85, I, 0, 0.1); C(0.85, 0, 0.12, A); speedlines(0.95, 0.45, 0.4, A) end
M.keg = function() R(0, 0.15, 1.1, 1.2, I, 0, 0.3); R(0, -0.15, 1.1, 0.1, D); R(0, 0.45, 1.1, 0.1, D); PL(A, 0.1, 0, -0.45, 0.2, -0.7, 0.45, -0.75); STAR(0.55, -0.8, 0.18, 0.07, 5, A) end
M.scope = function() RING(0, 0, 0.7, 0.14, I); L(0, -0.95, 0, -0.35, 0.1, I); L(0, 0.35, 0, 0.95, 0.1, I); L(-0.95, 0, -0.35, 0, 0.1, I); L(0.35, 0, 0.95, 0, 0.1, I); C(0, 0, 0.12, A) end
M.boomerang = function() PL(I, 0.28, -0.7, 0.5, 0, -0.5, 0.7, 0.5); ARC(0, 0.2, 0.75, 200, 340, 0.08, A) end
M.momentum = function() bullet(0.3, 0.2, 1, 0.42, 0, I); for k = 0, 2 do C(-0.3 - k * 0.25, 0.2, 0.12 - k * 0.03, A) end; HEAD(0.3, -0.45, 0, 0.25, A); L(-0.5, -0.45, 0.2, -0.45, 0.1, A) end
M.bloodbullet = function() bullet(0, -0.2, 1.4, 0.55, 0, I); drop(-0.2, 0.5, 0.35, A) end
M.wound = function() bullet(0.1, 0, 1.2, 0.45, -30, I); for k = 0, 2 do drop(-0.5 + k * 0.3, 0.55 + (k % 2) * 0.15, 0.22, A) end end
-- Bodies, defence and HP
M.anvil = function() P(I, -0.8, -0.35, 0.7, -0.35, 0.85, -0.1, 0.3, -0.05, 0.3, 0.35, 0.55, 0.65, -0.55, 0.65, -0.3, 0.35, -0.3, -0.05, -0.6, -0.1); R(0, -0.55, 1, 0.12, A) end
M.plate = function() R(0, 0, 1.3, 1.3, I, 0, 0.12); for _, p in ipairs({ { -0.45, -0.45 }, { 0.45, -0.45 }, { -0.45, 0.45 }, { 0.45, 0.45 } }) do C(p[1], p[2], 0.1, D) end; R(0, 0, 0.7, 0.12, A) end
M.decay = function() heart(0, 0, 0.9, I); PL(D, 0.08, 0.1, -0.4, -0.05, -0.1, 0.12, 0.15, -0.02, 0.45); C(-0.6, 0.7, 0.08, A); C(-0.35, 0.82, 0.06, A); C(0.5, 0.75, 0.07, A) end
M.brokenheart = function() heart(0, 0, 0.95, I); PL(D, 0.12, 0.02, -0.5, -0.12, -0.15, 0.1, 0.15, -0.05, 0.5) end
M.battery = function() R(-0.05, 0, 1.4, 0.8, I, 0, 0.12); R(0.75, 0, 0.12, 0.35, I); R(-0.45, 0, 0.42, 0.55, A, 0, 0.05); R(0.15, 0, 0.6, 0.55, D, 0, 0.05) end
M.pulse = function() PL(A, 0.12, -0.95, 0.25, -0.45, 0.25, -0.25, -0.35, 0, 0.65, 0.2, 0.05, 0.4, 0.25, 0.95, 0.25); heart(0, -0.15, 0.55, I) end
M.lastbreath = function() R(0, 0.35, 0.45, 0.9, I, 0, 0.06); flame(0, -0.45, 0.42, A, D); L(0, -0.12, 0, 0.0, 0.06, D) end
M.castle = function() R(0, 0.25, 1.5, 0.9, I, 0, 0.04); for k = -2, 2 do R(k * 0.33, -0.3, 0.2, 0.25, I) end; R(0, 0.45, 0.35, 0.5, D, 0, 0.15); R(-0.5, 0, 0.15, 0.25, A); R(0.5, 0, 0.15, 0.25, A) end
M.quickshield = function() shield(0.15, 0, 0.85, I, A); speedlines(-0.75, 0.1, 0.55, A) end
M.parry = function() R(0, 0, 0.18, 1.8, I, 45, 0.05); R(0, 0, 0.18, 1.8, I, -45, 0.05); STAR(0, 0, 0.55, 0.15, 4, A, 0) end
M.absorb = function() shield(0, 0.1, 0.8, I); for _, a in ipairs({ -150, -90, -30 }) do local x, y = math.cos(rad(a)) * 0.95, math.sin(rad(a)) * 0.95 + 0.1; HEAD(x * 0.7, y * 0.7 + 0.03, a + 180, 0.2, A) end; C(0, 0.1, 0.18, D) end
M.scale = function() L(0, -0.75, 0, 0.75, 0.14, I); L(-0.7, -0.45, 0.7, -0.45, 0.12, I); ARC(-0.6, -0.05, 0.28, 0, 180, 0.1, A); ARC(0.6, -0.05, 0.28, 0, 180, 0.1, A); R(0, 0.8, 0.8, 0.14, I) end
M.shields = function() shield(-0.32, 0.05, 0.6, I, D); shield(0.32, -0.05, 0.6, I, A) end
M.bunker = function() P(I, -0.9, 0.7, -0.6, -0.3, 0.6, -0.3, 0.9, 0.7); R(0, 0.05, 0.9, 0.18, D); R(0, -0.42, 1.3, 0.12, A) end
M.brokenshield = function() shield(-0.12, 0, 0.8, I); P(D, 0.15, -0.95, -0.05, -0.2, 0.2, 0.15, 0, 0.95, 0.35, 0.95, 0.45, 0.15, 0.25, -0.2, 0.45, -0.95); C(0.6, -0.5, 0.1, A); C(0.75, 0.0, 0.08, A) end
M.ward = function() ARC(0, 0.45, 0.85, 180, 360, 0.16, A); RING(0, 0.45, 0.55, 0.06, A); person(0, 0.2, 0.75, I); R(0, 0.75, 1.9, 0.12, I) end
M.riposte = function() R(-0.15, 0.1, 0.16, 1.5, I, 35, 0.04); R(0.15, 0.1, 0.16, 1.5, I, -35, 0.04); R(-0.55, 0.62, 0.45, 0.12, D, 35); R(0.55, 0.62, 0.45, 0.12, D, -35); ARC(0, -0.3, 0.5, 200, 340, 0.1, A) end
M.charge = function() RING(0, 0, 0.78, 0.16, I); bolt(0, 0, 0.62, A) end
M.aegis = function() C(0, 0.1, 0.85, A); C(0, 0.1, 0.7, D); person(0, 0.2, 0.8, I); ARC(0, 0.1, 0.85, 200, 260, 0.08, I) end
M.spikeshield = function() shield(0, 0.05, 0.75, I, A); for k = -1, 1 do P(I, k * 0.45 - 0.12, -0.75, k * 0.45 + 0.12, -0.75, k * 0.45, -1.0) end end
M.rally = function() L(-0.55, -0.85, -0.55, 0.85, 0.12, I); P(A, -0.5, -0.85, 0.75, -0.6, -0.5, -0.25); heart(0.35, 0.45, 0.4, I) end
M.lastbullet = function() bullet(0, 0.05, 1.5, 0.6, -90, I); RING(0, 0.05, 0.85, 0.08, A); STAR(0.6, -0.6, 0.2, 0.08, 4, A, 0) end
-- Movement and dashes
M.afterburner = function() R(0.15, 0, 1.0, 0.55, I, 0, 0.15); P(I, 0.65, -0.27, 0.95, 0, 0.65, 0.27); flame(-0.62, 0, 0.42, A, D) end
M.stride = function() person(0.45, 0, 0.75, I); for k = 0, 2 do C(-0.15 - k * 0.32, 0.5, 0.1, A) end; L(-0.8, 0.75, 0.9, 0.75, 0.08, A) end
M.razor = function() P(I, -0.9, 0.2, 0.5, -0.2, 0.9, 0, 0.5, 0.2); speedlines(-0.55, -0.45, 0.6, A); speedlines(-0.55, 0.55, 0.6, A) end
M.trail = function() person(0.6, 0, 0.7, I); flame(-0.1, 0.45, 0.28, A); flame(-0.45, 0.5, 0.22, A); flame(-0.75, 0.55, 0.16, A) end
M.link = function() RING(-0.32, 0, 0.32, 0.13, I); RING(0.32, 0, 0.32, 0.13, A) end
M.plane = function() P(I, 0.9, 0, -0.6, -0.45, -0.35, 0, -0.6, 0.45); P(A, -0.1, 0, -0.75, -0.85, -0.45, 0); P(A, -0.1, 0, -0.75, 0.85, -0.45, 0) end
M.teleport = function() person(-0.5, 0.05, 0.6, A); person(0.45, 0.05, 0.75, I); PL(A, 0.08, -0.5, -0.55, -0.05, -0.95, 0.4, -0.75); HEAD(0.4, -0.75, 60, 0.18, A) end
M.portal = function() RING(0, 0, 0.75, 0.18, A); C(0, 0, 0.5, D); HEAD(0.2, 0, 0, 0.35, I); L(-0.95, 0, 0.0, 0, 0.14, I) end
M.runner = function() C(0.15, -0.65, 0.2, I); PL(I, 0.18, 0.1, -0.4, -0.1, 0.15, -0.55, 0.5); PL(I, 0.18, -0.1, 0.15, 0.35, 0.3, 0.25, 0.75); PL(I, 0.15, 0.1, -0.3, 0.5, -0.1); speedlines(-0.6, -0.3, 0.4, A) end
M.flip = function() R(0, -0.85, 1.6, 0.14, A); add('<g transform="rotate(180 -0.15 0)">'); person(-0.15, 0.05, 0.8, I); add("</g>"); ARC(0.1, 0, 0.7, -80, 80, 0.12, A); HEAD(0.22, -0.69, -110, 0.2, A) end
M.lunge = function() fist(0.35, 0, 0.75, I); speedlines(-0.5, 0, 0.6, A) end
-- Melee
M.wraps = function() fist(0, 0, 1.1, I); for k = -1, 1 do R(0, k * 0.22 + 0.05, 1.0, 0.08, A, 10) end end
M.reach = function() fist(0.55, 0, 0.6, I); R(-0.3, 0, 1.0, 0.3, I); L(-0.45, -0.35, -0.05, -0.35, 0.08, A); HEAD(0.05, -0.35, 0, 0.14, A) end
M.counter = function() fist(-0.35, 0.25, 0.65, I); fist(0.35, -0.25, 0.65, I, 180); C(0, 0, 0.18, A) end
M.gauntlet = function() fist(0, -0.1, 1.2, I); R(0, 0.65, 1.0, 0.35, A, 0, 0.08) end
M.jab = function() fist(0.3, 0, 0.8, I); for k = -1, 1 do L(-0.9, k * 0.3, -0.45, k * 0.3, 0.08, A) end; STAR(0.85, -0.55, 0.2, 0.08, 4, A, 0) end
M.launch = function() person(0, -0.15, 0.8, I); HEAD(0, -0.9, -90, 0.25, A); for k = -1, 1 do L(k * 0.3, 0.55, k * 0.3, 0.9, 0.08, A) end end
M.uppercut = function() fist(0, -0.1, 0.9, I, -90); ARC(0.35, 0.35, 0.55, 90, 200, 0.12, A) end
M.combo = function() fist(-0.5, 0.25, 0.5, I); fist(0.05, 0, 0.55, I); fist(0.55, -0.3, 0.6, A) end
M.meteor = function() C(0.35, 0.35, 0.45, I); C(0.2, 0.25, 0.12, D); for k = 0, 2 do L(0.05 - k * 0.15, -0.05 - k * 0.1, -0.6 - k * 0.15, -0.75 + k * 0.05, 0.1, A) end; R(0, 0.88, 1.8, 0.12, A) end
M.tornado = function() for k = 0, 4 do R(0.1 * math.sin(k), -0.7 + k * 0.33, 1.3 - k * 0.22, 0.16, k % 2 == 0 and I or A, 0, 0.08) end end
M.grab = function() C(0, 0.35, 0.35, I); for k = -1, 1 do PL(I, 0.14, k * 0.25, 0.1, k * 0.38, -0.4, k * 0.22, -0.75) end; PL(A, 0.08, -0.85, 0.75, -0.5, 0.75) end
M.pounce = function() for k = -1, 1 do PL(I, 0.16, k * 0.35 - 0.3, 0.8, k * 0.35 + 0.15, -0.1, k * 0.35 + 0.35, -0.8) end; speedlines(-0.65, -0.4, 0.4, A) end
M.decoy = function() person(0.4, 0, 0.75, I); add('<g opacity="1">'); person(-0.4, 0, 0.75, A); add("</g>"); C(-0.4, -0.42, 0.06, D) end
-- Gadgets
M.grenade = function() C(0, 0.15, 0.62, I); R(0.05, -0.55, 0.35, 0.22, I); RING(0.4, -0.65, 0.15, 0.07, A); for k = -1, 1 do L(k * 0.25, -0.2, k * 0.25, 0.5, 0.06, D) end end
M.trap = function() R(0, 0.55, 1.6, 0.25, I, 0, 0.05); for k = -2, 2 do P(A, k * 0.32 - 0.13, 0.42, k * 0.32 + 0.13, 0.42, k * 0.32, -0.2) end end
M.detonator = function() R(0, 0.25, 0.9, 0.8, I, 0, 0.1); R(0, -0.3, 0.12, 0.45, I); C(0, -0.55, 0.15, A); C(0, 0.25, 0.22, D); PL(A, 0.07, 0.55, 0.2, 0.85, -0.1, 0.7, -0.5) end
M.bee = function() R(0, 0.15, 0.85, 0.6, I, 0, 0.3); R(-0.08, 0.15, 0.1, 0.6, D); R(0.18, 0.15, 0.1, 0.6, D); C(0.5, 0.05, 0.18, I); add('<ellipse cx="-0.15" cy="-0.35" rx="0.32" ry="0.2" fill="' .. A .. '"/>'); add('<ellipse cx="0.2" cy="-0.38" rx="0.26" ry="0.17" fill="' .. A .. '"/>') end
M.gravorb = function() C(0, 0, 0.55, I); C(0, 0, 0.28, D); ARC(0, 0, 0.8, -40, 60, 0.1, A); ARC(0, 0, 0.8, 140, 240, 0.1, A); HEAD(0.55, 0.62, 140, 0.18, A); HEAD(-0.55, -0.62, 320, 0.18, A) end
M.hive = function()
  for _, p in ipairs({ { 0, 0 }, { 0.5, 0.29 }, { -0.5, 0.29 }, { 0, -0.58 }, { 0.5, -0.29 }, { -0.5, -0.29 }, { 0, 0.58 } }) do
    local pts = {}
    for k = 0, 5 do local a = rad(k * 60); pts[#pts + 1] = p[1] + math.cos(a) * 0.27; pts[#pts + 1] = p[2] + math.sin(a) * 0.27 end
    P((p[1] == 0 and p[2] == 0) and A or I, unpack(pts))
  end
end
M.cluster = function() C(0, -0.2, 0.42, I); for _, a in ipairs({ 30, 150, 270 }) do C(math.cos(rad(a + 60)) * 0.65, math.sin(rad(a + 60)) * 0.65 - 0.1, 0.2, A) end; PL(A, 0.08, 0.2, -0.55, 0.35, -0.8) end
M.scrap = function() P(I, -0.8, 0.5, -0.4, -0.3, 0.1, 0.1, 0.5, -0.6, 0.85, 0.6); for k = -1, 1 do C(k * 0.4, 0.45, 0.09, D) end; R(0.4, -0.65, 0.4, 0.15, A, 25) end
M.nova = function() C(0, 0, 0.3, I); for k = 0, 7 do local a = rad(k * 45); C(math.cos(a) * 0.72, math.sin(a) * 0.72, 0.12, A) end; RING(0, 0, 0.5, 0.06, A) end
-- Bounce
M.angle = function() PL(A, 0.1, -0.85, -0.7, 0, 0.6, 0.85, -0.7); R(0, 0.82, 1.3, 0.14, I); C(0.85, -0.7, 0.16, I) end
M.superball = function() C(0.2, -0.1, 0.6, I); ARC(0.2, -0.1, 0.4, 200, 320, 0.12, D); speedlines(-0.75, 0.35, 0.5, A) end
M.trickshot = function() PL(A, 0.1, -0.85, 0.6, -0.5, -0.5, 0.2, 0.5, 0.55, -0.2); RING(0.6, -0.35, 0.3, 0.1, I); C(0.6, -0.35, 0.1, I) end
M.pocket = function() C(0, 0.35, 0.5, I); C(0, 0.35, 0.28, D); C(-0.45, -0.5, 0.2, A); L(-0.3, -0.35, -0.15, -0.1, 0.06, A) end
M.rubber = function() PL(I, 0.12, -0.8, -0.8, 0.8, -0.8, 0.8, 0.8, -0.8, 0.8, -0.8, -0.8); PL(A, 0.07, -0.6, 0.6, 0.6, -0.1, -0.3, -0.6, 0.6, 0.3); C(0.6, 0.3, 0.12, A) end
M.bodyhit = function() person(0, 0.15, 0.85, I); PL(A, 0.08, -0.85, -0.6, -0.25, -0.1, 0.85, -0.65); C(-0.25, -0.1, 0.1, A) end
-- Status
M.puddle = function() add('<ellipse cx="0" cy="0.5" rx="0.85" ry="0.28" fill="' .. I .. '"/>'); drop(0, -0.25, 0.45, A) end
M.acid = function() R(0, 0.25, 0.9, 1.1, I, 0, 0.2); R(0, -0.42, 0.45, 0.3, I); R(0, 0.45, 0.9, 0.5, A, 0, 0.15); C(-0.15, 0.4, 0.07, D); C(0.2, 0.55, 0.05, D) end
M.crack = function() P(I, -0.3, -0.85, 0.4, -0.75, 0.55, 0.85, -0.45, 0.75); PL(D, 0.07, 0.1, -0.8, -0.05, -0.2, 0.15, 0.2, -0.05, 0.75); snowflake(-0.7, -0.6, 0.18, A) end
M.frozen = function() R(0, 0, 1.4, 1.4, A, 0, 0.12); person(0, 0.1, 0.85, I); L(-0.45, -0.55, -0.2, -0.3, 0.06, D) end
M.thermal = function() flame(-0.35, 0.05, 0.55, I, A); snowflake(0.45, 0.05, 0.42, A) end
M.plague = function() for k = 0, 2 do local a = rad(-90 + k * 120); RING(math.cos(a) * 0.35, math.sin(a) * 0.35, 0.38, 0.13, I) end; C(0, 0, 0.16, A) end
M.shard = function() P(A, -0.1, -0.9, 0.35, -0.2, 0.05, 0.85, -0.4, 0.1); P(I, 0.45, -0.6, 0.85, -0.3, 0.6, 0.2); P(I, -0.55, 0.25, -0.85, 0.65, -0.45, 0.75) end
M.wildfire = function() flame(0, 0, 0.62, I, A); flame(-0.6, 0.35, 0.32, A); flame(0.6, 0.35, 0.32, A) end
M.chain = function() bolt(-0.45, -0.1, 0.45, I); bolt(0.15, 0.2, 0.4, A); bolt(0.65, -0.15, 0.32, I) end
M.thunderstep = function() add('<ellipse cx="-0.3" cy="0.4" rx="0.25" ry="0.42" fill="' .. I .. '"/>'); add('<ellipse cx="0.35" cy="0.0" rx="0.25" ry="0.42" fill="' .. I .. '"/>'); bolt(0.45, -0.55, 0.35, A); bolt(-0.25, -0.1, 0.3, A) end

local list = {}
for name in pairs(M) do list[#list + 1] = name end
table.sort(list)
for _, name in ipairs(list) do
  out = {}
  M[name]()
  local f = assert(io.open("assets/art/motif_" .. name .. ".svg", "w"))
  f:write('<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="-1.1 -1.1 2.2 2.2">' .. table.concat(out) .. "</svg>")
  f:close()
end
print("motifs", #list)
