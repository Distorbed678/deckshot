-- Controller button icons (sprites) and which device the player last touched.
-- Glyphs.print writes text with {tokens} in it: {a} {b} {x} {y} {lb} {rb} {lt} {rt} {back} {start}
-- {ls} {rs} {dpad} {dlr} (d-pad left/right) {dud} (d-pad up/down).
local app = require "core.app"
local Assets = require "core.assets"

local Glyphs = { device = "keys", joystick = nil }

function Glyphs.use(device, joystick)
  Glyphs.device = device
  require("core.ui").hideFocus = device == "touch"
  if joystick then Glyphs.joystick = joystick end
end

-- "xbox", "ps" or "nintendo", from the controller's name.
function Glyphs.style()
  local j = Glyphs.joystick
  if not j and love.joystick then
    for _, c in ipairs(love.joystick.getJoysticks()) do
      if c:isGamepad() then j = c break end
    end
  end
  local name = j and j:getName():lower() or ""
  for _, w in ipairs({ "dualsense", "dualshock", "playstation", "ps3", "ps4", "ps5", "sony" }) do
    if name:find(w, 1, true) then return "ps" end
  end
  if name == "wireless controller" then return "ps" end -- what a DualShock 4 calls itself
  for _, w in ipairs({ "nintendo", "switch", "pro controller", "joy-con" }) do
    if name:find(w, 1, true) then return "nintendo" end
  end
  return "xbox"
end

local FACE_XBOX = { a = true, b = true, x = true, y = true } -- the face buttons; every pad has these four
local SHOULDER = {
  xbox = { lb = "LB", rb = "RB", lt = "LT", rt = "RT", back = "VIEW", start = "MENU" },
  ps = { lb = "L1", rb = "R1", lt = "L2", rt = "R2", back = "SHARE", start = "OPTIONS" },
  nintendo = { lb = "L", rb = "R", lt = "ZL", rt = "ZR", back = "-", start = "+" },
}
local PILL = { 0.3, 0.31, 0.38 }

local function label(text, cx, cy, size, color)
  local font = app.fonts.small
  local s = size / font:getHeight()
  love.graphics.setFont(font)
  love.graphics.setColor(color)
  love.graphics.print(text, cx - font:getWidth(text) * s / 2, cy - size / 2, 0, s, s)
end

local function pillWidth(text, s)
  return math.max(s * 1.4, app.fonts.small:getWidth(text) * (s * 0.62 / app.fonts.small:getHeight()) + s * 0.6)
end

function Glyphs.width(name, s)
  if name == "dpad" or name == "dlr" or name == "dud" or name == "ls" or name == "rs" or FACE_XBOX[name] then return s end
  local text = SHOULDER[Glyphs.style()][name]
  return text and pillWidth(text, s) or 0
end

local function icon(name, cx, cy, s)
  love.graphics.setColor(1, 1, 1)
  Assets.center(name, cx, cy, s, s)
end

-- One icon with its left edge at x, vertically centred on cy. Returns its width.
function Glyphs.draw(name, x, cy, s)
  local style = Glyphs.style()
  local w = Glyphs.width(name, s)
  local cx = x + w / 2
  if FACE_XBOX[name] then
    icon("glyph_" .. style .. "_" .. name, cx, cy, s)
  elseif name == "dpad" or name == "dlr" or name == "dud" or name == "ls" or name == "rs" then
    icon("glyph_" .. name, cx, cy, s)
  else
    local text = SHOULDER[style][name]
    if not text then return 0 end
    local h = (name == "lt" or name == "rt") and s or s * 0.82
    love.graphics.setColor(PILL)
    Assets.round("fill", x, cy - h / 2, w, h)
    label(text, cx, cy, s * 0.62, { 1, 1, 1 })
  end
  love.graphics.setColor(1, 1, 1)
  return w
end

local function split(text)
  local parts = {}
  local pos = 1
  while true do
    local a, b, name = text:find("{(%w+)}", pos)
    if not a then
      if pos <= #text then parts[#parts + 1] = { text = text:sub(pos) } end
      break
    end
    if a > pos then parts[#parts + 1] = { text = text:sub(pos, a - 1) } end
    parts[#parts + 1] = { glyph = name }
    pos = b + 1
  end
  return parts
end

-- Print text with {tokens} on one line in width w (shrunk to fit), aligned left, center or right.
-- color (optional) is the text's colour; the current colour is used otherwise.
function Glyphs.print(text, font, x, y, w, align, color)
  local parts = split(text)
  local s = font:getHeight() * 0.92
  local total = 0
  for _, p in ipairs(parts) do
    p.w = p.text and font:getWidth(p.text) or Glyphs.width(p.glyph, s) + 3
    total = total + p.w
  end
  local col = color or { love.graphics.getColor() }
  local k = (total > w and total > 0) and w / total or 1
  local px = x
  if align == "center" then px = x + (w - total * k) / 2 elseif align == "right" then px = x + w - total * k end
  local cy = y + font:getHeight() / 2
  love.graphics.setFont(font)
  for _, p in ipairs(parts) do
    if p.text then
      love.graphics.setColor(col)
      love.graphics.print(p.text, px, cy - font:getHeight() * k / 2, 0, k, k)
    else
      Glyphs.draw(p.glyph, px, cy, s * k)
    end
    px = px + p.w * k
  end
  love.graphics.setColor(col)
end

-- Bottom right of menus while a controller is the last thing touched. Screens opt out with noPadHints.
function Glyphs.drawMenuHints()
  if Glyphs.device ~= "pad" then return end
  local top = app.top()
  if not top or top.noPadHints or require("core.ui").capturing then return end
  Glyphs.print("{dpad} Move     {a} Select     {b} Back", app.fonts.small, app.W - 420, 698, 408, "right", { 1, 1, 1, 0.65 })
end

return Glyphs
