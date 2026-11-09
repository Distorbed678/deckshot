-- Card art: a medallion with a motif (and an optional small badge) on every card,
-- plus the foil, glow and sparkles of the rarer cards.
-- A card file picks its art with "art <motif> [<badge>] [<tint>]", e.g. "art bullet up fire".
-- Cards without an art line (older custom cards) get one guessed from what they do.
local g = love.graphics
local Assets = require "core.assets"

local CardArt = {}

CardArt.TINTS = {
  fire = { 1, 0.55, 0.15 }, ice = { 0.45, 0.85, 1 }, toxic = { 0.5, 0.95, 0.35 }, void = { 0.72, 0.45, 1 },
  gold = { 1, 0.8, 0.25 }, blood = { 1, 0.3, 0.35 }, volt = { 1, 0.95, 0.35 }, steel = { 0.66, 0.72, 0.82 },
  sky = { 0.4, 0.7, 1 }, pink = { 1, 0.45, 0.75 },
}
CardArt.TINT_NAMES = { "fire", "ice", "toxic", "void", "gold", "blood", "volt", "steel", "sky", "pink" }

local PI = math.pi
local INK, DARK = { 0.96, 0.96, 1 }, { 0.1, 0.1, 0.14 }

-- The motifs are images in assets/art/motif_*.svg. They are painted in pure red (ink), green
-- (the card's accent) and blue (dark), and this recolours them for each card.
local recolor
local function motif(name, x, y, s, accent)
  if not recolor then
    recolor = love.graphics.newShader([[
      uniform vec3 ink;
      uniform vec3 accent;
      uniform vec3 dark;
      vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        vec4 t = Texel(tex, uv);
        return vec4(t.r * ink + t.g * accent + t.b * dark, t.a) * color;
      }
    ]])
  end
  recolor:send("ink", INK)
  recolor:send("dark", DARK)
  recolor:send("accent", { accent[1], accent[2], accent[3] })
  g.setShader(recolor)
  g.setColor(1, 1, 1)
  Assets.center("motif_" .. name, x, y, s * 2.2, s * 2.2)
  g.setShader()
end

local M = {}
for _, name in ipairs({ "armor", "axe", "bat", "blackhole", "blade", "body", "bomb", "bone", "boot", "bounce", "bullet", "bullets", "burst", "cannon", "card", "clock", "cloud", "crate", "crown", "dash", "dice", "down", "drop", "eye", "fang", "feather", "fist", "flame", "fork", "gear", "ghost", "gun", "hand", "heart", "hourglass", "hydra", "laser", "mag", "magnet", "mine", "minus", "mirror", "moon", "orb", "orbit", "phoenix", "pierce", "plus", "rocket", "saw", "seek", "shield", "shrine", "skull", "snow", "spread", "spring", "star", "swap", "swirl", "target", "thorns", "turret", "up", "uturn", "volt", "wall", "wave", "weight", "wing", "x2" }) do M[name] = true end
M.hit = true -- an old name for burst, still used by some card files

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
  local accent = spec.tint and CardArt.TINTS[spec.tint] or rim
  local function name(n) return n == "hit" and "burst" or n end
  g.setColor(0, 0, 0, 0.3)
  Assets.center("dot", cx, cy + 2, (r + 2) * 2, (r + 2) * 2)
  g.setColor(rim)
  Assets.center("dot", cx, cy, r * 2, r * 2)
  g.setColor(DARK)
  Assets.center("dot", cx, cy, (r - 3) * 2, (r - 3) * 2)
  motif(name(spec.main), cx, cy, r * 0.62, accent)
  if spec.badge then
    local bx, by, br = cx + r * 0.68, cy + r * 0.62, r * 0.44
    g.setColor(rim)
    Assets.center("dot", bx, by, br * 2, br * 2)
    g.setColor(DARK)
    Assets.center("dot", bx, by, (br - 2) * 2, (br - 2) * 2)
    motif(name(spec.badge), bx, by, br * 0.62, accent)
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
      Assets.center("sparkle", sx, sy, size * 3, size * 3, 0.4)
    end
  end
  g.setBlendMode("alpha")
  g.setColor(1, 1, 1)
end

return CardArt
