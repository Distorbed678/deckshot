-- Hats and faces. Purely visual. Hats and faces are identified on the network by their position
-- in these lists (append only). `unlock` = { stat, count } from core/profile.lua; none = free.
local Cosmetics = {}

local G = love.graphics

Cosmetics.STAT_TEXT = {
  wins = "Win %d matches", rounds = "Win %d rounds", picks = "Pick %d cards", kills = "Get %d kills",
  hillWins = "Win %d King of the Hill rounds",
}

-- Hats are drawn with (0, 0) at the top of the head; r is the body radius.
Cosmetics.HATS = {
  { id = "none", name = "No hat" },
  { id = "cap", name = "Cap", draw = function(r, c)
    G.setColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45)
    G.arc("fill", 0, 3, r * 0.68, math.pi, math.pi * 2)
    G.rectangle("fill", r * 0.1, 0, r * 0.95, 4, 2, 2)
  end },
  { id = "party", name = "Party Hat", draw = function(r)
    G.setColor(1, 0.4, 0.75)
    G.polygon("fill", -r * 0.42, 4, r * 0.42, 4, 0, -r * 1.05)
    G.setColor(1, 0.95, 0.4)
    G.circle("fill", 0, -r * 1.05, 3.5)
  end },
  { id = "headband", name = "Headband", unlock = { "rounds", 5 }, draw = function(r)
    G.setColor(0.95, 0.2, 0.2)
    G.rectangle("fill", -r * 0.8, r * 0.15, r * 1.6, 5, 2, 2)
    G.polygon("fill", -r * 0.8, r * 0.2, -r * 1.25, r * 0.05, -r * 1.2, r * 0.5)
  end },
  { id = "horns", name = "Horns", unlock = { "rounds", 25 }, draw = function(r)
    G.setColor(0.92, 0.9, 0.8)
    G.polygon("fill", -r * 0.7, 6, -r * 0.25, 2, -r * 0.8, -r * 0.65)
    G.polygon("fill", r * 0.7, 6, r * 0.25, 2, r * 0.8, -r * 0.65)
  end },
  { id = "tophat", name = "Top Hat", unlock = { "wins", 3 }, draw = function(r)
    G.setColor(0.12, 0.12, 0.15)
    G.rectangle("fill", -r * 0.85, 0, r * 1.7, 5, 2, 2)
    G.rectangle("fill", -r * 0.52, -r * 0.95, r * 1.04, r * 0.98)
    G.setColor(0.8, 0.15, 0.2)
    G.rectangle("fill", -r * 0.52, -r * 0.22, r * 1.04, 5)
  end },
  { id = "viking", name = "Viking Helm", unlock = { "wins", 10 }, draw = function(r)
    G.setColor(0.65, 0.66, 0.72)
    G.arc("fill", 0, 5, r * 0.75, math.pi, math.pi * 2)
    G.setColor(0.92, 0.9, 0.8)
    G.polygon("fill", -r * 0.72, 2, -r * 1.3, -r * 0.7, -r * 0.42, -r * 0.3)
    G.polygon("fill", r * 0.72, 2, r * 1.3, -r * 0.7, r * 0.42, -r * 0.3)
  end },
  { id = "wizard", name = "Wizard Hat", unlock = { "picks", 50 }, draw = function(r)
    G.setColor(0.35, 0.22, 0.75)
    G.polygon("fill", -r * 0.85, 4, r * 0.85, 4, r * 0.3, -r * 1.3)
    G.setColor(1, 0.9, 0.3)
    G.circle("fill", r * 0.05, -r * 0.3, 3)
  end },
  { id = "halo", name = "Halo", unlock = { "picks", 200 }, draw = function(r)
    G.setColor(1, 0.92, 0.45)
    G.setLineWidth(3)
    G.ellipse("line", 0, -r * 0.42, r * 0.65, r * 0.2)
  end },
  { id = "antenna", name = "Antenna", unlock = { "kills", 50 }, draw = function(r)
    G.setColor(0.8, 0.8, 0.86)
    G.setLineWidth(2)
    G.line(0, 3, 0, -r * 0.8)
    G.setColor(1, 0.3, 0.3, 0.6 + 0.4 * math.sin(love.timer.getTime() * 6))
    G.circle("fill", 0, -r * 0.85, 4)
  end },
  { id = "crown", name = "Crown", unlock = { "wins", 25 }, draw = function(r)
    G.setColor(1, 0.8, 0.25)
    G.polygon("fill", -r * 0.65, 4, -r * 0.65, -r * 0.5, -r * 0.3, -r * 0.1, 0, -r * 0.65, r * 0.3, -r * 0.1,
      r * 0.65, -r * 0.5, r * 0.65, 4)
  end },
  { id = "laurel", name = "Laurels", unlock = { "hillWins", 3 }, draw = function(r)
    G.setColor(0.45, 0.8, 0.35)
    for i = -3, 3 do
      if i ~= 0 then
        local a = -math.pi / 2 + i * 0.42
        G.ellipse("fill", math.cos(a) * r * 0.72, r * 0.45 + math.sin(a) * r * 0.6, 5, 3)
      end
    end
  end },
}

local function dot(x, y, s) G.circle("fill", x, y, s) end

-- Faces get: r, look (x, y from -1 to 1), state { blink, hurt, firing }, alpha. (0, 0) is the middle of the face.
local function eyes(r, look, st, size, gap)
  local px, py = look[1] * r * 0.12, look[2] * r * 0.1
  if st.hurt then
    G.setLineWidth(2)
    for _, s in ipairs({ -1, 1 }) do
      local x = s * gap + px
      G.line(x - 3, py - 3, x + s * 3, py, x - 3, py + 3)
    end
    return
  end
  if st.blink then
    G.setLineWidth(2)
    G.line(-gap - 3 + px, py, -gap + 3 + px, py)
    G.line(gap - 3 + px, py, gap + 3 + px, py)
    return
  end
  local k = st.firing and 1.3 or 1
  dot(-gap + px, py, size * k)
  dot(gap + px, py, size * k)
end

Cosmetics.FACES = {
  { id = "classic", name = "Classic", draw = function(r, look, st) eyes(r, look, st, r * 0.13, 5) end },
  { id = "round", name = "Wide Eyes", draw = function(r, look, st)
    if st.hurt or st.blink then return eyes(r, look, st, r * 0.13, 6) end
    G.push("all")
    local _, _, _, a = G.getColor()
    G.setColor(1, 1, 1, a)
    dot(-6, 0, r * 0.26)
    dot(6, 0, r * 0.26)
    G.pop()
    eyes(r, look, st, r * 0.12, 6)
  end },
  { id = "happy", name = "Happy", draw = function(r, look, st)
    eyes(r, look, st, r * 0.12, 6)
    if not st.hurt then
      G.setLineWidth(2)
      G.arc("line", "open", look[1] * 2, r * 0.26, r * 0.22, 0.25, math.pi - 0.25)
    end
  end },
  { id = "sleepy", name = "Sleepy", unlock = { "rounds", 10 }, draw = function(r, look, st)
    eyes(r, look, { blink = true, hurt = st.hurt }, r * 0.13, 6)
  end },
  { id = "angry", name = "Angry", unlock = { "kills", 25 }, draw = function(r, look, st)
    eyes(r, look, st, r * 0.12, 6)
    G.setLineWidth(3)
    G.line(-11 + look[1] * 2, -8, -3 + look[1] * 2, -4)
    G.line(11 + look[1] * 2, -8, 3 + look[1] * 2, -4)
  end },
  { id = "cyclops", name = "Cyclops", unlock = { "wins", 5 }, draw = function(r, look, st)
    if st.blink or st.hurt then
      G.setLineWidth(3)
      G.line(-6, 0, 6, 0)
      return
    end
    G.push("all")
    local _, _, _, a = G.getColor()
    G.setColor(1, 1, 1, a)
    dot(look[1] * 2, look[2] * 2, r * 0.38)
    G.pop()
    dot(look[1] * 5, look[2] * 4, r * 0.18 * (st.firing and 1.3 or 1))
  end },
  { id = "visor", name = "Visor", unlock = { "picks", 100 }, draw = function(r, look, st)
    G.push("all")
    local _, _, _, a = G.getColor()
    G.setColor(st.hurt and 1 or 0.3, st.hurt and 0.3 or 0.9, 1, a)
    G.rectangle("fill", -r * 0.72 + look[1] * 3, -4, r * 1.44, 8, 4, 4)
    G.pop()
  end },
  { id = "wink", name = "Wink", unlock = { "hillWins", 1 }, draw = function(r, look, st)
    if st.hurt then return eyes(r, look, st, r * 0.13, 6) end
    dot(-6 + look[1] * 2, look[2] * 2, r * 0.13)
    G.setLineWidth(2)
    G.line(3 + look[1] * 2, 0, 9 + look[1] * 2, 0)
  end },
}

local function indexBy(list)
  local t = {}
  for i, c in ipairs(list) do t[c.id] = i end
  return t
end
Cosmetics.HAT_INDEX = indexBy(Cosmetics.HATS)
Cosmetics.FACE_INDEX = indexBy(Cosmetics.FACES)

function Cosmetics.unlocked(item)
  if not item.unlock then return true end
  local Profile = require "core.profile"
  return (Profile.stats[item.unlock[1]] or 0) >= item.unlock[2]
end

function Cosmetics.unlockText(item)
  if not item.unlock then return "" end
  local Profile = require "core.profile"
  return string.format(Cosmetics.STAT_TEXT[item.unlock[1]] or "%d", item.unlock[2]) ..
    "  (" .. math.min(Profile.stats[item.unlock[1]] or 0, item.unlock[2]) .. " / " .. item.unlock[2] .. ")"
end

-- This machine's chosen hat and face, as network indices. Locked choices fall back to the defaults.
function Cosmetics.mine()
  local v = require("core.settings").values
  local hat, face = Cosmetics.HAT_INDEX[v.hat] or 1, Cosmetics.FACE_INDEX[v.face] or 1
  if not Cosmetics.unlocked(Cosmetics.HATS[hat]) then hat = 1 end
  if not Cosmetics.unlocked(Cosmetics.FACES[face]) then face = 1 end
  return hat, face
end

-- Draws a character (menus). look = { x, y }.
function Cosmetics.drawPreview(x, y, r, color, hat, face, look)
  G.setColor(color)
  G.circle("fill", x, y, r)
  Cosmetics.drawFace(x, y - r * 0.25, r, face, look or { 0.5, 0 }, {}, 1)
  Cosmetics.drawHat(x, y - r * 0.92, r, hat, color)
end

function Cosmetics.drawFace(x, y, r, index, look, state, alpha)
  local f = Cosmetics.FACES[index or 1] or Cosmetics.FACES[1]
  G.push()
  G.translate(x, y)
  G.scale(r / 20)
  G.setColor(0.1, 0.1, 0.12, alpha)
  f.draw(20, look, state)
  G.pop()
end

function Cosmetics.drawHat(x, y, r, index, color, alpha)
  local h = Cosmetics.HATS[index or 1]
  if not h or not h.draw then return end
  G.push("all")
  G.translate(x, y)
  G.scale(r / 20)
  h.draw(20, color)
  G.pop()
end

return Cosmetics
