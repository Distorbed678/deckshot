-- Hats, eyes, mouths and details. Purely visual. Each is identified on the network by its position
-- in these lists (append only). Locked ones are unlocked by the achievements in
-- core/achievements.lua, assigned in order at the bottom of this file.
local Cosmetics = {}

local G = love.graphics

local function dot(x, y, s) G.circle("fill", x, y, s) end

---------------------------------------------------------------- hats ((0, 0) is the top of the head)
local function col(r, g, b) G.setColor(r, g, b) end

Cosmetics.HATS = {
  { id = "none", name = "No hat" },
  { id = "cap", name = "Cap", draw = function(r, c)
    col(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45)
    G.arc("fill", 0, 3, r * 0.68, math.pi, math.pi * 2)
    G.rectangle("fill", r * 0.1, 0, r * 0.95, 4, 2, 2)
  end },
  { id = "party", name = "Party Hat", draw = function(r)
    col(1, 0.4, 0.75)
    G.polygon("fill", -r * 0.42, 4, r * 0.42, 4, 0, -r * 1.05)
    col(1, 0.95, 0.4)
    dot(0, -r * 1.05, 3.5)
  end },
  { id = "beanie", name = "Beanie", draw = function(r)
    col(0.3, 0.55, 0.85)
    G.arc("fill", 0, 5, r * 0.72, math.pi, math.pi * 2)
    col(0.9, 0.9, 0.95)
    G.rectangle("fill", -r * 0.74, 1, r * 1.48, 6, 3, 3)
    dot(0, -r * 0.68, 4)
  end },
  { id = "headband", name = "Headband", draw = function(r)
    col(0.95, 0.2, 0.2)
    G.rectangle("fill", -r * 0.8, r * 0.15, r * 1.6, 5, 2, 2)
    G.polygon("fill", -r * 0.8, r * 0.2, -r * 1.25, r * 0.05, -r * 1.2, r * 0.5)
  end },
  { id = "horns", name = "Horns", lock = true, draw = function(r)
    col(0.92, 0.9, 0.8)
    G.polygon("fill", -r * 0.7, 6, -r * 0.25, 2, -r * 0.8, -r * 0.65)
    G.polygon("fill", r * 0.7, 6, r * 0.25, 2, r * 0.8, -r * 0.65)
  end },
  { id = "tophat", name = "Top Hat", lock = true, draw = function(r)
    col(0.12, 0.12, 0.15)
    G.rectangle("fill", -r * 0.85, 0, r * 1.7, 5, 2, 2)
    G.rectangle("fill", -r * 0.52, -r * 0.95, r * 1.04, r * 0.98)
    col(0.8, 0.15, 0.2)
    G.rectangle("fill", -r * 0.52, -r * 0.22, r * 1.04, 5)
  end },
  { id = "viking", name = "Viking Helm", lock = true, draw = function(r)
    col(0.65, 0.66, 0.72)
    G.arc("fill", 0, 5, r * 0.75, math.pi, math.pi * 2)
    col(0.92, 0.9, 0.8)
    G.polygon("fill", -r * 0.72, 2, -r * 1.3, -r * 0.7, -r * 0.42, -r * 0.3)
    G.polygon("fill", r * 0.72, 2, r * 1.3, -r * 0.7, r * 0.42, -r * 0.3)
  end },
  { id = "wizard", name = "Wizard Hat", lock = true, draw = function(r)
    col(0.35, 0.22, 0.75)
    G.polygon("fill", -r * 0.85, 4, r * 0.85, 4, r * 0.3, -r * 1.3)
    col(1, 0.9, 0.3)
    dot(r * 0.05, -r * 0.3, 3)
  end },
  { id = "halo", name = "Halo", lock = true, draw = function(r)
    col(1, 0.92, 0.45)
    G.setLineWidth(3)
    G.ellipse("line", 0, -r * 0.42, r * 0.65, r * 0.2)
  end },
  { id = "antenna", name = "Antenna", lock = true, draw = function(r)
    col(0.8, 0.8, 0.86)
    G.setLineWidth(2)
    G.line(0, 3, 0, -r * 0.8)
    G.setColor(1, 0.3, 0.3, 0.6 + 0.4 * math.sin(love.timer.getTime() * 6))
    dot(0, -r * 0.85, 4)
  end },
  { id = "crown", name = "Crown", lock = true, draw = function(r)
    col(1, 0.8, 0.25)
    G.polygon("fill", -r * 0.65, 4, -r * 0.65, -r * 0.5, -r * 0.3, -r * 0.1, 0, -r * 0.65, r * 0.3, -r * 0.1,
      r * 0.65, -r * 0.5, r * 0.65, 4)
  end },
  { id = "laurel", name = "Laurels", lock = true, draw = function(r)
    col(0.45, 0.8, 0.35)
    for i = -3, 3 do
      if i ~= 0 then
        local a = -math.pi / 2 + i * 0.42
        G.ellipse("fill", math.cos(a) * r * 0.72, r * 0.45 + math.sin(a) * r * 0.6, 5, 3)
      end
    end
  end },
  { id = "cowboy", name = "Cowboy Hat", lock = true, draw = function(r)
    col(0.55, 0.36, 0.2)
    G.ellipse("fill", 0, 3, r * 1.25, 5)
    G.rectangle("fill", -r * 0.5, -r * 0.65, r, r * 0.7, 6, 6)
  end },
  { id = "fez", name = "Fez", lock = true, draw = function(r)
    col(0.75, 0.15, 0.18)
    G.polygon("fill", -r * 0.42, 4, r * 0.42, 4, r * 0.32, -r * 0.65, -r * 0.32, -r * 0.65)
    col(1, 0.8, 0.3)
    G.setLineWidth(2)
    G.line(0, -r * 0.65, r * 0.42, -r * 0.3, r * 0.45, 0)
  end },
  { id = "chef", name = "Chef Hat", lock = true, draw = function(r)
    col(0.95, 0.95, 0.97)
    G.rectangle("fill", -r * 0.5, -r * 0.4, r, r * 0.45)
    dot(-r * 0.32, -r * 0.55, r * 0.34)
    dot(0, -r * 0.7, r * 0.38)
    dot(r * 0.32, -r * 0.55, r * 0.34)
  end },
  { id = "mohawk", name = "Mohawk", lock = true, draw = function(r)
    col(0.95, 0.25, 0.65)
    for i = -3, 3 do G.polygon("fill", i * r * 0.2 - 4, 6, i * r * 0.2 + 4, 6, i * r * 0.2, -r * 0.75 + math.abs(i) * 3) end
  end },
  { id = "bow", name = "Big Bow", lock = true, draw = function(r)
    col(1, 0.45, 0.65)
    G.polygon("fill", 0, 0, -r * 0.7, -r * 0.45, -r * 0.7, r * 0.45)
    G.polygon("fill", 0, 0, r * 0.7, -r * 0.45, r * 0.7, r * 0.45)
    col(0.85, 0.25, 0.45)
    dot(0, 0, 4)
  end },
  { id = "pirate", name = "Pirate Hat", lock = true, draw = function(r)
    col(0.1, 0.1, 0.13)
    G.polygon("fill", -r * 1.05, 5, r * 1.05, 5, r * 0.55, -r * 0.7, -r * 0.55, -r * 0.7)
    col(0.95, 0.95, 0.95)
    dot(0, -r * 0.28, 4)
  end },
  { id = "propeller", name = "Propeller Cap", lock = true, draw = function(r)
    col(0.9, 0.3, 0.25)
    G.arc("fill", 0, 3, r * 0.66, math.pi, math.pi * 2)
    col(1, 0.85, 0.3)
    local w = math.sin(love.timer.getTime() * 20) * r * 0.6
    G.setLineWidth(3)
    G.line(-w, -r * 0.7, w, -r * 0.7)
    G.line(0, -r * 0.7, 0, -r * 0.5)
  end },
}

---------------------------------------------------------------- eyes ((0, 0) is the middle of the face)
local function brow(look, st)
  if st.expr == "angry" then
    G.setLineWidth(3)
    G.line(-11 + look[1] * 2, -9, -3 + look[1] * 2, -5)
    G.line(11 + look[1] * 2, -9, 3 + look[1] * 2, -5)
  end
end

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
  local k = st.firing and 1.3 or (st.expr == "shock" and 1.35 or 1)
  dot(-gap + px, py, size * k)
  dot(gap + px, py, size * k)
end

local function white(a) local _, _, _, alpha = G.getColor(); G.setColor(1, 1, 1, alpha) return a end
local function dark() local _, _, _, a = G.getColor(); G.setColor(0.1, 0.1, 0.12, a) end

Cosmetics.EYES = {
  { id = "classic", name = "Classic", draw = function(r, l, s) eyes(r, l, s, r * 0.13, 5); brow(l, s) end },
  { id = "round", name = "Wide Eyes", draw = function(r, l, s)
    if not (s.hurt or s.blink) then
      white(); dot(-6, 0, r * 0.26); dot(6, 0, r * 0.26); dark()
    end
    eyes(r, l, s, r * 0.12, 6); brow(l, s)
  end },
  { id = "dots", name = "Tiny Dots", draw = function(r, l, s) eyes(r, l, s, r * 0.08, 7); brow(l, s) end },
  { id = "sleepy", name = "Sleepy", draw = function(r, l, s) eyes(r, l, { blink = true, hurt = s.hurt }, r * 0.13, 6) end },
  { id = "angry", name = "Scowl", lock = true, draw = function(r, l, s)
    eyes(r, l, s, r * 0.12, 6)
    G.setLineWidth(3)
    G.line(-11 + l[1] * 2, -8, -3 + l[1] * 2, -4)
    G.line(11 + l[1] * 2, -8, 3 + l[1] * 2, -4)
  end },
  { id = "cyclops", name = "Cyclops", lock = true, draw = function(r, l, s)
    if s.blink or s.hurt then
      G.setLineWidth(3)
      G.line(-6, 0, 6, 0)
      return
    end
    white(); dot(l[1] * 2, l[2] * 2, r * 0.38); dark()
    dot(l[1] * 5, l[2] * 4, r * 0.18 * (s.firing and 1.3 or 1))
  end },
  { id = "visor", name = "Visor", lock = true, draw = function(r, l, s)
    local _, _, _, a = G.getColor()
    G.setColor(s.hurt and 1 or 0.3, s.hurt and 0.3 or 0.9, 1, a)
    G.rectangle("fill", -r * 0.72 + l[1] * 3, -4, r * 1.44, 8, 4, 4)
    dark()
  end },
  { id = "wink", name = "Wink", lock = true, draw = function(r, l, s)
    if s.hurt then return eyes(r, l, s, r * 0.13, 6) end
    dot(-6 + l[1] * 2, l[2] * 2, r * 0.13)
    G.setLineWidth(2)
    G.line(3 + l[1] * 2, 0, 9 + l[1] * 2, 0)
  end },
  { id = "shades", name = "Shades", lock = true, draw = function(r, l)
    local x = l[1] * 2
    G.rectangle("fill", -12 + x, -4, 10, 8, 2, 2)
    G.rectangle("fill", 2 + x, -4, 10, 8, 2, 2)
    G.setLineWidth(2)
    G.line(-2 + x, -2, 2 + x, -2)
  end },
  { id = "xeyes", name = "Knocked Out", lock = true, draw = function(r, l)
    G.setLineWidth(2)
    for _, s in ipairs({ -6, 6 }) do
      local x = s + l[1] * 2
      G.line(x - 3, -3, x + 3, 3)
      G.line(x + 3, -3, x - 3, 3)
    end
  end },
  { id = "cat", name = "Cat Eyes", lock = true, draw = function(r, l, s)
    if s.blink or s.hurt then return eyes(r, l, s, r * 0.13, 6) end
    local _, _, _, a = G.getColor()
    G.setColor(0.7, 0.9, 0.3, a); G.ellipse("fill", -6, 0, 4.5, 5); G.ellipse("fill", 6, 0, 4.5, 5); dark()
    G.ellipse("fill", -6 + l[1] * 2, 0, 1.2, 4.5)
    G.ellipse("fill", 6 + l[1] * 2, 0, 1.2, 4.5)
  end },
  { id = "goggles", name = "Goggles", lock = true, draw = function(r, l, s)
    local _, _, _, a = G.getColor()
    G.setColor(0.8, 0.55, 0.25, a); dot(-6, 0, 7); dot(6, 0, 7)
    G.setColor(0.6, 0.85, 1, a); dot(-6, 0, 5); dot(6, 0, 5); dark()
    if not s.blink then dot(-6 + l[1] * 2, l[2] * 2, 2); dot(6 + l[1] * 2, l[2] * 2, 2) end
  end },
  { id = "stars", name = "Starry", lock = true, draw = function(r, l)
    local _, _, _, a = G.getColor()
    G.setColor(1, 0.85, 0.3, a)
    for _, s in ipairs({ -6, 6 }) do
      G.polygon("fill", s, -5, s + 1.5, -1.5, s + 5, 0, s + 1.5, 1.5, s, 5, s - 1.5, 1.5, s - 5, 0, s - 1.5, -1.5)
    end
    dark()
  end },
  { id = "hearts", name = "Smitten", lock = true, draw = function()
    local _, _, _, a = G.getColor()
    G.setColor(1, 0.3, 0.45, a)
    for _, s in ipairs({ -6, 6 }) do
      dot(s - 2, -1, 2.6); dot(s + 2, -1, 2.6)
      G.polygon("fill", s - 4.5, 0, s + 4.5, 0, s, 5.5)
    end
    dark()
  end },
  { id = "robot", name = "Robot", lock = true, draw = function(r, l, s)
    if s.blink then return eyes(r, l, s, r * 0.13, 6) end
    local _, _, _, a = G.getColor()
    G.setColor(0.2, 1, 0.5, a)
    G.rectangle("fill", -10 + l[1] * 2, -3, 7, 6)
    G.rectangle("fill", 3 + l[1] * 2, -3, 7, 6)
    dark()
  end },
}

---------------------------------------------------------------- mouths ((0, 0) is the middle of the face)
local function smile(r, l, wide)
  G.setLineWidth(2)
  G.arc("line", "open", l[1] * 2, r * 0.32, r * (wide and 0.32 or 0.22), 0.25, math.pi - 0.25)
end

Cosmetics.MOUTHS = {
  { id = "smile", name = "Smile", draw = function(r, l, s)
    if s.expr == "grin" then
      smile(r, l, true)
    elseif s.expr == "angry" then
      G.setLineWidth(2)
      G.arc("line", "open", l[1] * 2, r * 0.72, r * 0.22, math.pi + 0.3, math.pi * 2 - 0.3)
    elseif s.expr == "shock" then
      dot(l[1] * 2, r * 0.5, r * 0.14)
    else
      smile(r, l)
    end
  end },
  { id = "none", name = "No mouth" },
  { id = "flat", name = "Unimpressed", draw = function(r, l) G.setLineWidth(2); G.line(-5 + l[1] * 2, r * 0.5, 5 + l[1] * 2, r * 0.5) end },
  { id = "grin", name = "Big Grin", draw = function(r, l)
    local x = l[1] * 2
    white(); G.arc("fill", x, r * 0.32, r * 0.32, 0, math.pi); dark()
    G.setLineWidth(1.5); G.arc("line", x, r * 0.32, r * 0.32, 0, math.pi)
  end },
  { id = "open", name = "Surprised", lock = true, draw = function(r, l) G.ellipse("fill", l[1] * 2, r * 0.52, 4, 6) end },
  { id = "tongue", name = "Tongue Out", lock = true, draw = function(r, l)
    smile(r, l)
    local _, _, _, a = G.getColor(); G.setColor(1, 0.45, 0.55, a)
    G.ellipse("fill", l[1] * 2 + 2, r * 0.62, 3.5, 5); dark()
  end },
  { id = "fangs", name = "Fangs", lock = true, draw = function(r, l)
    local x = l[1] * 2
    G.setLineWidth(2); G.line(x - 8, r * 0.45, x + 8, r * 0.45)
    white()
    G.polygon("fill", x - 6, r * 0.45, x - 2, r * 0.45, x - 4, r * 0.8)
    G.polygon("fill", x + 2, r * 0.45, x + 6, r * 0.45, x + 4, r * 0.8)
    dark()
  end },
  { id = "mustache", name = "Mustache", lock = true, draw = function(r, l)
    local x = l[1] * 2
    G.ellipse("fill", x - 5, r * 0.42, 6, 2.6)
    G.ellipse("fill", x + 5, r * 0.42, 6, 2.6)
  end },
  { id = "zipper", name = "Zipper", lock = true, draw = function(r, l)
    local x = l[1] * 2
    G.setLineWidth(2); G.line(x - 9, r * 0.5, x + 9, r * 0.5)
    for i = -8, 8, 4 do G.line(x + i, r * 0.5 - 2, x + i, r * 0.5 + 2) end
  end },
  { id = "smirk", name = "Smirk", lock = true, draw = function(r, l)
    G.setLineWidth(2)
    local x = l[1] * 2
    G.line(x - 6, r * 0.5, x + 3, r * 0.5, x + 7, r * 0.36)
  end },
  { id = "wavy", name = "Nervous", lock = true, draw = function(r, l)
    G.setLineWidth(2)
    local x = l[1] * 2
    G.line(x - 9, r * 0.5, x - 6, r * 0.42, x - 3, r * 0.5, x, r * 0.42, x + 3, r * 0.5, x + 6, r * 0.42, x + 9, r * 0.5)
  end },
  { id = "grille", name = "Grille", lock = true, draw = function(r, l)
    local x = l[1] * 2
    G.rectangle("fill", x - 9, r * 0.36, 18, 7, 2, 2)
    white()
    for i = -6, 6, 4 do G.rectangle("fill", x + i - 0.7, r * 0.36 + 1.2, 1.4, 4.6) end
    dark()
  end },
  { id = "beard", name = "Beard", lock = true, draw = function(r, l)
    local _, _, _, a = G.getColor(); G.setColor(0.4, 0.26, 0.15, a)
    G.arc("fill", l[1], r * 0.3, r * 0.56, 0.1, math.pi - 0.1); dark()
  end },
  { id = "buck", name = "Buck Teeth", lock = true, draw = function(r, l)
    local x = l[1] * 2
    smile(r, l)
    white(); G.rectangle("fill", x - 4, r * 0.52, 3.6, 5); G.rectangle("fill", x + 0.4, r * 0.52, 3.6, 5); dark()
  end },
  { id = "kitty", name = "Kitty Mouth", lock = true, draw = function(r, l)
    local x = l[1] * 2
    G.setLineWidth(2)
    G.arc("line", "open", x - 3.5, r * 0.42, 3.5, 0, math.pi)
    G.arc("line", "open", x + 3.5, r * 0.42, 3.5, 0, math.pi)
  end },
}

---------------------------------------------------------------- details (on the face)
Cosmetics.DETAILS = {
  { id = "none", name = "No detail" },
  { id = "blush", name = "Blush", draw = function(r)
    local _, _, _, a = G.getColor(); G.setColor(1, 0.45, 0.5, 0.55 * a)
    G.ellipse("fill", -11, 6, 4, 2.6); G.ellipse("fill", 11, 6, 4, 2.6)
  end },
  { id = "freckles", name = "Freckles", draw = function()
    for _, p in ipairs({ { -11, 5 }, { -8, 7 }, { -12, 8 }, { 11, 5 }, { 8, 7 }, { 12, 8 } }) do dot(p[1], p[2], 0.9) end
  end },
  { id = "scar", name = "Scar", lock = true, draw = function()
    G.setLineWidth(1.5)
    G.line(8, -9, 13, 3)
    G.line(9, -6, 13, -7); G.line(10.5, -2, 14.5, -3)
  end },
  { id = "bandage", name = "Bandage", lock = true, draw = function()
    local _, _, _, a = G.getColor(); G.setColor(0.95, 0.85, 0.7, a)
    G.push(); G.translate(-11, -7); G.rotate(-0.5); G.rectangle("fill", -6, -2, 12, 4, 1, 1); G.pop()
  end },
  { id = "monocle", name = "Monocle", lock = true, draw = function()
    local _, _, _, a = G.getColor(); G.setColor(1, 0.85, 0.35, a)
    G.setLineWidth(1.5); G.circle("line", 6, 0, 7); G.line(11, 5, 12, 16)
  end },
  { id = "warpaint", name = "Warpaint", lock = true, draw = function()
    local _, _, _, a = G.getColor(); G.setColor(1, 1, 1, 0.8 * a)
    for i = 0, 1 do
      G.rectangle("fill", -15, 4 + i * 4, 7, 2)
      G.rectangle("fill", 8, 4 + i * 4, 7, 2)
    end
  end },
  { id = "stitches", name = "Stitches", lock = true, draw = function()
    G.setLineWidth(1.5)
    G.line(-16, -2, -7, -8)
    for i = 0, 3 do local t = i / 3; G.line(-16 + 9 * t - 1.5, -2 - 6 * t - 2, -16 + 9 * t + 1.5, -2 - 6 * t + 2) end
  end },
  { id = "tear", name = "Teardrop", lock = true, draw = function()
    local _, _, _, a = G.getColor(); G.setColor(0.45, 0.75, 1, a)
    G.polygon("fill", 8, 5, 5.5, 10, 10.5, 10); dot(8, 10, 2.5)
  end },
  { id = "gem", name = "Forehead Gem", lock = true, draw = function()
    local _, _, _, a = G.getColor(); G.setColor(0.45, 1, 0.85, a)
    G.polygon("fill", 0, -14, 4, -10, 0, -6, -4, -10)
  end },
}

local function indexBy(list)
  local t = {}
  for i, c in ipairs(list) do t[c.id] = i end
  return t
end
Cosmetics.HAT_INDEX = indexBy(Cosmetics.HATS)
Cosmetics.EYE_INDEX = indexBy(Cosmetics.EYES)
Cosmetics.MOUTH_INDEX = indexBy(Cosmetics.MOUTHS)
Cosmetics.DETAIL_INDEX = indexBy(Cosmetics.DETAILS)

-- Slot name -> list, index and the setting that stores it.
Cosmetics.SLOTS = {
  { key = "hat", name = "Hats", list = Cosmetics.HATS, index = Cosmetics.HAT_INDEX },
  { key = "eyes", name = "Eyes", list = Cosmetics.EYES, index = Cosmetics.EYE_INDEX },
  { key = "mouth", name = "Mouths", list = Cosmetics.MOUTHS, index = Cosmetics.MOUTH_INDEX },
  { key = "detail", name = "Details", list = Cosmetics.DETAILS, index = Cosmetics.DETAIL_INDEX },
}

-- Every locked cosmetic is the reward for one achievement, shared out across the slots in turn.
local Achievements = require "core.achievements"
do
  local queues, i = {}, 0
  for _, s in ipairs(Cosmetics.SLOTS) do
    local q = {}
    for _, item in ipairs(s.list) do if item.lock then q[#q + 1] = item end end
    queues[#queues + 1] = q
  end
  local a = 1
  while a <= Achievements.count() do
    i = i % #queues + 1
    local item = table.remove(queues[i], 1)
    if item then
      local ach = Achievements[a]
      item.ach, ach.reward = ach, item.name
      a = a + 1
    else
      local left = 0
      for _, q in ipairs(queues) do left = left + #q end
      if left == 0 then break end
    end
  end
end

function Cosmetics.unlocked(item)
  if not item.lock then return true end
  return item.ach == nil or Achievements.earned(item.ach.id)
end

function Cosmetics.unlockText(item)
  if not item.ach then return "" end
  return item.ach.name .. ": " .. item.ach.desc .. "  (" .. Achievements.progress(item.ach) .. " / " .. item.ach.n .. ")"
end

-- This machine's chosen look, as network indices: hat, eyes, mouth, detail. Locked ones become defaults.
function Cosmetics.mine()
  local v = require("core.settings").values
  local out = {}
  for i, s in ipairs(Cosmetics.SLOTS) do
    local idx = s.index[v[s.key]] or 1
    if not Cosmetics.unlocked(s.list[idx]) then idx = 1 end
    out[i] = idx
  end
  return out[1], out[2], out[3], out[4]
end

function Cosmetics.drawFace(x, y, r, look, state, alpha, eyes_, mouth, detail)
  local e = Cosmetics.EYES[eyes_ or 1] or Cosmetics.EYES[1]
  local m = Cosmetics.MOUTHS[mouth or 1] or Cosmetics.MOUTHS[1]
  local d = Cosmetics.DETAILS[detail or 1]
  G.push("all")
  G.translate(x, y)
  G.scale(r / 20)
  G.setColor(0.1, 0.1, 0.12, alpha)
  if d and d.draw then d.draw(20) end
  G.setColor(0.1, 0.1, 0.12, alpha)
  if m.draw then m.draw(20, look, state) end
  G.setColor(0.1, 0.1, 0.12, alpha)
  e.draw(20, look, state)
  G.pop()
end

function Cosmetics.drawHat(x, y, r, index, color)
  local h = Cosmetics.HATS[index or 1]
  if not h or not h.draw then return end
  G.push("all")
  G.translate(x, y)
  G.scale(r / 20)
  h.draw(20, color)
  G.pop()
end

return Cosmetics
