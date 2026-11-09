-- Hats, eyes, mouths and details. Purely visual. Each is identified on the network by its position
-- in these lists (append only). Locked ones are unlocked by the achievements in
-- core/achievements.lua, assigned in order at the bottom of this file.
local Cosmetics = {}

local Assets = require "core.assets"
local G = love.graphics


---------------------------------------------------------------- hats ((0, 0) is the top of the head)

Cosmetics.HATS = {
  { id = "none", name = "No hat" },
  { tint = true, id = "cap", name = "Cap" },
  { id = "party", name = "Party Hat" },
  { id = "beanie", name = "Beanie" },
  { id = "headband", name = "Headband" },
  { id = "horns", name = "Horns", lock = true },
  { id = "tophat", name = "Top Hat", lock = true },
  { id = "viking", name = "Viking Helm", lock = true },
  { id = "wizard", name = "Wizard Hat", lock = true },
  { id = "halo", name = "Halo", lock = true },
  { id = "antenna", name = "Antenna", lock = true },
  { id = "crown", name = "Crown", lock = true },
  { id = "laurel", name = "Laurels", lock = true },
  { id = "cowboy", name = "Cowboy Hat", lock = true },
  { id = "fez", name = "Fez", lock = true },
  { id = "chef", name = "Chef Hat", lock = true },
  { id = "mohawk", name = "Mohawk", lock = true },
  { id = "bow", name = "Big Bow", lock = true },
  { id = "pirate", name = "Pirate Hat", lock = true },
  { id = "propeller", name = "Propeller Cap", lock = true },
}




Cosmetics.EYES = {
  { id = "classic", name = "Classic" },
  { id = "round", name = "Wide Eyes" },
  { id = "dots", name = "Tiny Dots" },
  { id = "sleepy", name = "Sleepy" },
  { id = "angry", name = "Scowl", lock = true },
  { id = "cyclops", name = "Cyclops", lock = true },
  { id = "visor", name = "Visor", lock = true },
  { id = "wink", name = "Wink", lock = true },
  { id = "shades", name = "Shades", lock = true },
  { id = "xeyes", name = "Knocked Out", lock = true },
  { id = "cat", name = "Cat Eyes", lock = true },
  { id = "goggles", name = "Goggles", lock = true },
  { id = "stars", name = "Starry", lock = true },
  { id = "hearts", name = "Smitten", lock = true },
  { id = "robot", name = "Robot", lock = true },
}

---------------------------------------------------------------- mouths ((0, 0) is the middle of the face)

Cosmetics.MOUTHS = {
  { id = "smile", name = "Smile" },
  { id = "none", name = "No mouth" },
  { id = "flat", name = "Unimpressed" },
  { id = "grin", name = "Big Grin" },
  { id = "open", name = "Surprised", lock = true },
  { id = "tongue", name = "Tongue Out", lock = true },
  { id = "fangs", name = "Fangs", lock = true },
  { id = "mustache", name = "Mustache", lock = true },
  { id = "zipper", name = "Zipper", lock = true },
  { id = "smirk", name = "Smirk", lock = true },
  { id = "wavy", name = "Nervous", lock = true },
  { id = "grille", name = "Grille", lock = true },
  { id = "beard", name = "Beard", lock = true },
  { id = "buck", name = "Buck Teeth", lock = true },
  { id = "kitty", name = "Kitty Mouth", lock = true },
}

---------------------------------------------------------------- details (on the face)
Cosmetics.DETAILS = {
  { id = "none", name = "No detail" },
  { id = "blush", name = "Blush" },
  { id = "freckles", name = "Freckles" },
  { id = "scar", name = "Scar", lock = true },
  { id = "bandage", name = "Bandage", lock = true },
  { id = "monocle", name = "Monocle", lock = true },
  { id = "warpaint", name = "Warpaint", lock = true },
  { id = "stitches", name = "Stitches", lock = true },
  { id = "tear", name = "Teardrop", lock = true },
  { id = "gem", name = "Forehead Gem", lock = true },
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

local SIZE = 120 -- sprites are drawn for a body of radius 20, in a 120 by 120 frame

local function stateName(st)
  return st.hurt and "hurt" or st.blink and "blink" or st.firing and "firing" or st.expr or "normal"
end

function Cosmetics.drawFace(x, y, r, look, state, alpha, eyes_, mouth, detail)
  local e = Cosmetics.EYES[eyes_ or 1] or Cosmetics.EYES[1]
  local m = Cosmetics.MOUTHS[mouth or 1] or Cosmetics.MOUTHS[1]
  local d = Cosmetics.DETAILS[detail or 1]
  local s = r / 20
  local size = SIZE * s
  local st = stateName(state)
  G.setColor(1, 1, 1, alpha)
  -- The face turns a little towards where you look.
  local px, py = look[1] * 2.4 * s, look[2] * 2 * s
  if d and d.id ~= "none" then Assets.center("detail_" .. d.id, x, y, size, size) end
  if m.id ~= "none" then Assets.center("mouth_" .. m.id .. "_" .. st, x + px * 0.5, y + py * 0.3, size, size) end
  Assets.center("eye_" .. e.id .. "_" .. st, x + px, y + py, size, size)
end

function Cosmetics.drawHat(x, y, r, index, color)
  local h = Cosmetics.HATS[index or 1]
  if not h or h.id == "none" then return end
  local size = SIZE * r / 20
  if h.tint then G.setColor(color) else G.setColor(1, 1, 1) end
  Assets.center("hat_" .. h.id, x, y, size, size)
end

return Cosmetics
