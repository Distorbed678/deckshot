-- Input sources. Each player reads an input state table:
--   left, right, up, down, fire, jumpHeld  (held this frame)
--   aim       (angle in radians for mouse aim, nil for keyboard aim)
--   meleeHeld (melee button held: a tap is a light swing, holding charges a heavy one)
--   jumpCount, blockCount, dashCount, meleeCount (press counters; a change means "pressed")
--   pickHover (card the player is hovering while picking, 0 = none; sent to the host)
-- Bindings come from Settings.values.binds and are read live, so rebinding applies at once.
local Input = {}

local function newState(kind)
  return {
    kind = kind,
    left = false, right = false, up = false, down = false, fire = false, jumpHeld = false,
    meleeHeld = false,
    aim = nil, jumpCount = 0, blockCount = 0, dashCount = 0, meleeCount = 0, pickHover = 0,
  }
end

-- Is a binding ("space", "mouse1", ...) held?
function Input.isDown(b)
  if not b then return false end
  local n = b:match("^mouse(%d)$")
  if n then return love.mouse.isDown(tonumber(n)) end
  local ok, down = pcall(love.keyboard.isDown, b)
  return ok and down
end

local KEY_NAMES = {
  space = "Space", lshift = "L-Shift", rshift = "R-Shift", lctrl = "L-Ctrl", rctrl = "R-Ctrl",
  lalt = "L-Alt", ralt = "R-Alt", ["return"] = "Enter", kpenter = "Num Enter", backspace = "Backspace",
  tab = "Tab", up = "Up", down = "Down", left = "Left", right = "Right", capslock = "Caps Lock",
  mouse1 = "LMB", mouse2 = "RMB", mouse3 = "MMB", mouse4 = "Mouse 4", mouse5 = "Mouse 5",
}

-- Display name of a binding, e.g. "lshift" -> "L-Shift", "mouse1" -> "LMB".
function Input.keyName(b)
  if not b then return "-" end
  if KEY_NAMES[b] then return KEY_NAMES[b] end
  if b:match("^kp") then return "Num " .. b:sub(3):upper() end
  if #b == 1 then return b:upper() end
  return b:sub(1, 1):upper() .. b:sub(2)
end

-- Shared-keyboard local player. binds: Settings.values.binds.p1 / p2.
function Input.keys(binds)
  local s = newState("keys")
  s.controls = binds
  return s
end

-- Online player on this machine: mouse aim plus Settings.values.binds.online.
function Input.mouse(binds)
  local s = newState("mouse")
  s.controls = binds
  s.aim = 0
  return s
end

-- A gamepad (LÖVE Joystick with a gamepad mapping). Left stick moves, right stick aims.
function Input.pad(joystick)
  local s = newState("pad")
  s.joystick = joystick
  s.aim = 0
  return s
end

-- Touch controls (core/touch.lua).
function Input.touch()
  local s = newState("touch")
  s.aim = 0
  return s
end

-- A bot: game/bot.lua fills this in every frame.
function Input.bot(difficulty)
  local s = newState("bot")
  s.difficulty = difficulty or 2
  s.aim = 0
  return s
end

-- Gamepad buttons: which action each one does.
Input.PAD = {
  jump = { "a" }, dash = { "b", "leftshoulder" }, melee = { "x" }, block = { "rightshoulder", "y" },
  fire = "triggerright", block2 = "triggerleft",
}
local DEAD = 0.3

-- Network player, filled in from received packets.
function Input.remote()
  local s = newState("remote")
  s.aim = 0
  return s
end

local function clearHeld(s)
  s.left, s.right, s.up, s.down, s.fire, s.jumpHeld = false, false, false, false, false, false
  s.meleeHeld, s.blockHeld = false, false
end

-- Refresh held state. (px, py) is the player's position, used for mouse aim.
-- mx, my are the mouse position in game coordinates.
function Input.poll(s, suppressed, px, py, mx, my)
  if suppressed then
    clearHeld(s)
    return
  end
  local down = Input.isDown
  local c = s.controls
  if s.kind == "keys" then
    s.left, s.right, s.up, s.down, s.fire = down(c.left), down(c.right), down(c.up), down(c.down), down(c.fire)
    s.jumpHeld = s.up
    s.meleeHeld = down(c.melee)
    s.blockHeld = down(c.block) -- Bunker: holding block keeps it up
  elseif s.kind == "touch" then
    require("core.touch").apply(s, love.timer.getDelta())
  elseif s.kind == "pad" then
    local j = s.joystick
    if not j or not j:isConnected() then return clearHeld(s) end
    local lx, ly = j:getGamepadAxis("leftx"), j:getGamepadAxis("lefty")
    s.left = lx < -DEAD or j:isGamepadDown("dpleft")
    s.right = lx > DEAD or j:isGamepadDown("dpright")
    s.up = ly < -0.6 or j:isGamepadDown("dpup")
    s.down = ly > 0.6 or j:isGamepadDown("dpdown")
    s.jumpHeld = j:isGamepadDown("a")
    s.meleeHeld = j:isGamepadDown("x")
    s.blockHeld = j:getGamepadAxis("triggerleft") > 0.4 or j:isGamepadDown("rightshoulder")
    s.fire = j:getGamepadAxis("triggerright") > 0.4
    local rx, ry = j:getGamepadAxis("rightx"), j:getGamepadAxis("righty")
    if rx * rx + ry * ry > DEAD * DEAD then
      s.aim = math.atan2(ry, rx)
      s.aimDist = 140 + 360 * math.min(1, math.sqrt(rx * rx + ry * ry)) -- Joystick steers toward this point
    elseif s.left ~= s.right then
      s.aim = s.left and math.pi or 0 -- aim where you're moving when the right stick is idle
    end
    -- Triggers fire / block like buttons (block on the press).
    local lt = j:getGamepadAxis("triggerleft") > 0.4
    if lt and not s.ltWasDown then s.blockCount = s.blockCount + 1 end
    s.ltWasDown = lt
  elseif s.kind == "mouse" then
    s.left, s.right, s.down = down(c.left), down(c.right), down(c.down)
    s.jumpHeld = down(c.jump) or down(c.jump2)
    s.fire = down(c.fire)
    s.meleeHeld = down(c.melee)
    s.blockHeld = down(c.block)
    if px and mx then
      s.aim = math.atan2(my - py, mx - px)
      s.aimDist = math.sqrt((mx - px) ^ 2 + (my - py) ^ 2) -- how far away the cursor is (Joystick)
    end
  end
end

-- A key or mouse button ("mouse1"...) was pressed.
local function pressed(s, b)
  local c = s.controls
  if not c or (s.kind ~= "keys" and s.kind ~= "mouse") then return end
  if b == c.dash then s.dashCount = s.dashCount + 1 end
  if b == c.melee then s.meleeCount = s.meleeCount + 1 end
  if s.kind == "keys" then
    if b == c.up then s.jumpCount = s.jumpCount + 1 end
    if b == c.block then s.blockCount = s.blockCount + 1 end
  elseif s.kind == "mouse" then
    if b == c.jump or b == c.jump2 then s.jumpCount = s.jumpCount + 1 end
    if b == c.block then s.blockCount = s.blockCount + 1 end
  end
end

function Input.keypressed(s, key)
  pressed(s, key)
end

function Input.mousepressed(s, button)
  pressed(s, "mouse" .. button)
end

-- A gamepad button was pressed on joystick j.
function Input.gamepadpressed(s, j, button)
  if s.kind ~= "pad" or s.joystick ~= j then return end
  local P = Input.PAD
  local function is(list) for _, b in ipairs(list) do if b == button then return true end end end
  if is(P.jump) then s.jumpCount = s.jumpCount + 1 end
  if is(P.dash) then s.dashCount = s.dashCount + 1 end
  if is(P.melee) then s.meleeCount = s.meleeCount + 1 end
  if is(P.block) then s.blockCount = s.blockCount + 1 end
end

-- Connected gamepads, in order.
function Input.pads()
  local out = {}
  if not love.joystick then return out end
  for _, j in ipairs(love.joystick.getJoysticks()) do
    if j:isGamepad() then out[#out + 1] = j end
  end
  return out
end

return Input
