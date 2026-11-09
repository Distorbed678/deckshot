-- Map backgrounds: a themed sky and two layers of silhouettes that shift a little with the action,
-- plus a few drifting motes. Maps name a theme with a `theme` line; otherwise it comes from the map's id.
local platform = require "core.platform"

local Atmosphere = { camX = 0, camY = 0 }

local THEMES = {
  foundry = { block = { 0.33, 0.28, 0.27 }, edge = { 0.72, 0.45, 0.26 }, mote = { 1, 0.55, 0.2 }, shape = "towers" },
  ice = { block = { 0.31, 0.38, 0.47 }, edge = { 0.72, 0.9, 1 }, mote = { 0.85, 0.95, 1 }, shape = "peaks" },
  neon = { block = { 0.27, 0.25, 0.42 }, edge = { 0.95, 0.4, 0.9 }, mote = { 0.4, 0.9, 1 }, shape = "towers" },
  jungle = { block = { 0.3, 0.33, 0.27 }, edge = { 0.55, 0.8, 0.35 }, mote = { 0.8, 1, 0.45 }, shape = "hills" },
  void = { block = { 0.3, 0.31, 0.38 }, edge = { 0.62, 0.64, 0.82 }, mote = { 0.7, 0.65, 1 }, shape = "peaks" },
  desert = { block = { 0.42, 0.34, 0.27 }, edge = { 0.9, 0.7, 0.42 }, mote = { 1, 0.85, 0.55 }, shape = "hills" },
}
Atmosphere.NAMES = { "foundry", "ice", "neon", "jungle", "void", "desert" }

local function hash(s)
  local h = 7
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 1000003 end
  return h
end

function Atmosphere.themeOf(map)
  if map.theme and THEMES[map.theme] then return THEMES[map.theme], map.theme end
  local name = Atmosphere.NAMES[hash(map.id or map.name or "x") % #Atmosphere.NAMES + 1]
  return THEMES[name], name
end

-- Behind everything, in world coordinates.
function Atmosphere.draw(map)
  local t, name = Atmosphere.themeOf(map)
  local Map = require "game.map"
  local Assets = require "core.assets"
  -- Each theme has two drawings of its scenery; a map always gets the same one.
  local variant = hash(map.id or map.name or "x") % 2 + 1
  local base = "bg_" .. name .. "_" .. variant
  love.graphics.setColor(1, 1, 1)
  local ox, oy = -32 - Atmosphere.camX * 8, -18 - Atmosphere.camY * 4
  Assets.rect(base .. "_far", ox, oy, Map.W + 64, Map.H + 36)
  if not platform.web then Assets.rect(base .. "_near", ox - Atmosphere.camX * 14, oy - Atmosphere.camY * 6, Map.W + 64, Map.H + 36) end
  -- Drifting motes.
  local now = love.timer.getTime()
  local m = t.mote
  for i = 1, platform.web and 10 or 26 do
    local sp = 8 + (i * 7) % 18
    local x = ((i * 197.3 + now * sp) % (Map.W + 40)) - 20
    local y = (i * 83.7 + math.sin(now * 0.4 + i) * 40 - now * sp * 0.4) % Map.H
    love.graphics.setColor(m[1], m[2], m[3], 0.08 + 0.1 * (0.5 + 0.5 * math.sin(now * 1.5 + i)))
    require("core.assets").center("dot", x, y, (1.5 + i % 3) * 2, (1.5 + i % 3) * 2)
  end
  return t
end

return Atmosphere
