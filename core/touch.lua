-- Touch controls (phones / tablets, mostly through the browser build).
--   Left half: a floating move stick (up = jump, down = fast fall / drop through).
--   Right half: a floating aim stick that fires while held (a tap fires once).
--   Buttons: Jump, Block, Dash, Melee (hold for heavy), plus a pause button.
-- Turned on by the first touch (Settings: touchControls = auto / on / off). Positions are in
-- 1280x720 units and can be changed in the touch layout editor (screens/touchlayout.lua).
local Touch = { enabled = false, touches = {}, move = nil, aim = nil, held = {}, pressedOnce = {} }

Touch.DEFAULT_LAYOUT = {
  jump = { 1160, 590, 62 }, block = { 1036, 640, 48 }, dash = { 1180, 455, 46 }, melee = { 1050, 515, 46 },
  pause = { 776, 32, 26 }, -- just right of the round timer
}
Touch.BUTTONS = { "jump", "block", "dash", "melee", "pause" }
Touch.LABELS = { jump = "JUMP", block = "BLOCK", dash = "DASH", melee = "MELEE", pause = "II" }
Touch.layout = {}
Touch.opacity = 0.5
local STICK_R = 70

function Touch.setLayout(text, opacity)
  Touch.layout = {}
  for k, v in pairs(Touch.DEFAULT_LAYOUT) do Touch.layout[k] = { v[1], v[2], v[3] } end
  for name, x, y, r in (text or ""):gmatch("(%a+)=([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)") do
    if Touch.layout[name] and not (name == "pause" and x == "640" and y == "32") then -- the old default sat on the timer
      Touch.layout[name] = { tonumber(x), tonumber(y), tonumber(r) }
    end
  end
  Touch.opacity = opacity or Touch.opacity
end

function Touch.layoutString()
  local parts = {}
  for _, name in ipairs(Touch.BUTTONS) do
    local b = Touch.layout[name]
    parts[#parts + 1] = string.format("%s=%d,%d,%d", name, b[1], b[2], b[3])
  end
  return table.concat(parts, ";")
end

Touch.setLayout()

local function toVirtual(x, y)
  local app = require "core.app"
  return (x - app.ox) / app.scale, (y - app.oy) / app.scale
end

local function buttonAt(x, y)
  for _, name in ipairs(Touch.BUTTONS) do
    local b = Touch.layout[name]
    if (x - b[1]) ^ 2 + (y - b[2]) ^ 2 < (b[3] + 10) ^ 2 then return name end
  end
end

-- Raw events from love.touch* (window pixels). Only used while a match uses touch input.
function Touch.pressed(id, px, py)
  local settings = require("core.settings").values
  if settings.touchControls ~= "off" then Touch.enabled = true end
  local x, y = toVirtual(px, py)
  local t = { id = id, x = x, y = y, x0 = x, y0 = y, start = love.timer.getTime() }
  local b = buttonAt(x, y)
  if b then
    t.button = b
    Touch.held[b] = true
    Touch.pressedOnce[b] = (Touch.pressedOnce[b] or 0) + 1
  elseif x < 640 and not Touch.move then
    t.stick = "move"
    Touch.move = t
  elseif x >= 640 and not Touch.aim then
    t.stick = "aim"
    Touch.aim = t
  end
  Touch.touches[id] = t
end

function Touch.moved(id, px, py)
  local t = Touch.touches[id]
  if not t then return end
  t.x, t.y = toVirtual(px, py)
end

function Touch.released(id)
  local t = Touch.touches[id]
  if not t then return end
  if t.button then Touch.held[t.button] = false end
  if t.stick == "move" then Touch.move = nil end
  if t.stick == "aim" then
    -- A quick tap without dragging fires a single shot.
    if love.timer.getTime() - t.start < 0.25 and (t.x - t.x0) ^ 2 + (t.y - t.y0) ^ 2 < 20 * 20 then
      Touch.tapShot = 0.08
    end
    Touch.aim = nil
  end
  Touch.touches[id] = nil
end

-- Fill a touch input state (core/input.lua kind "touch") from the current touches.
function Touch.apply(s, dt)
  local m = Touch.move
  s.left, s.right, s.up, s.down = false, false, false, false
  if m then
    local dx, dy = m.x - m.x0, m.y - m.y0
    s.left, s.right = dx < -18, dx > 18
    s.down = dy > 40
    local up = dy < -45
    if up and not s.stickJump then s.jumpCount = s.jumpCount + 1 end
    s.stickJump = up
  else
    s.stickJump = false
  end
  s.jumpHeld = (Touch.held.jump or s.stickJump) and true or false
  local a = Touch.aim
  if a then
    local dx, dy = a.x - a.x0, a.y - a.y0
    if dx * dx + dy * dy > 14 * 14 then
      s.aim = math.atan2(dy, dx)
      s.fire = true
    else
      s.fire = false
    end
  else
    s.fire = false
  end
  if (Touch.tapShot or 0) > 0 then
    Touch.tapShot = Touch.tapShot - (dt or 0.016)
    s.fire = true
  end
  if not a and s.left ~= s.right then s.aim = s.left and math.pi or 0 end
  s.meleeHeld = Touch.held.melee and true or false
  for field, button in pairs({ jumpCount = "jump", blockCount = "block", dashCount = "dash", meleeCount = "melee" }) do
    local n = Touch.pressedOnce[button] or 0
    if n > 0 then
      s[field] = s[field] + n
      Touch.pressedOnce[button] = 0
    end
  end
end

-- Pause button pressed since last asked?
function Touch.takePause()
  local n = Touch.pressedOnce.pause or 0
  Touch.pressedOnce.pause = 0
  return n > 0
end

function Touch.reset()
  Touch.touches, Touch.move, Touch.aim, Touch.held, Touch.pressedOnce = {}, nil, nil, {}, {}
end

-- Draw the controls (in the 1280x720 canvas).
function Touch.draw()
  local app = require "core.app"
  local A = Touch.opacity
  for _, name in ipairs(Touch.BUTTONS) do
    local b = Touch.layout[name]
    local down = Touch.held[name]
    love.graphics.setColor(1, 1, 1, (down and 0.35 or 0.15) * A * 2)
    love.graphics.circle("fill", b[1], b[2], b[3])
    love.graphics.setColor(1, 1, 1, 0.6 * A * 2)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", b[1], b[2], b[3])
    love.graphics.setFont(name == "pause" and app.fonts.med or app.fonts.small)
    love.graphics.printf(Touch.LABELS[name], b[1] - b[3], b[2] - 9, b[3] * 2, "center")
  end
  for _, st in ipairs({ Touch.move, Touch.aim }) do
    if st then
      love.graphics.setColor(1, 1, 1, 0.12 * A * 2)
      love.graphics.circle("fill", st.x0, st.y0, STICK_R)
      local dx, dy = st.x - st.x0, st.y - st.y0
      local d = math.sqrt(dx * dx + dy * dy)
      if d > STICK_R then dx, dy = dx / d * STICK_R, dy / d * STICK_R end
      love.graphics.setColor(1, 1, 1, 0.45 * A * 2)
      love.graphics.circle("fill", st.x0 + dx, st.y0 + dy, 30)
    end
  end
end

return Touch
