-- Tiny immediate-mode UI: widgets are declared while drawing and return what happened.
-- Mouse: hover + click. Keyboard: Up/Down (or Tab) to move, Enter to activate,
-- Left/Right to change option values.
local utf8 = require "utf8"

local ui = {
  active = true,   -- only the top screen's widgets react to input
  focus = 1,
  count = 0,
  lastCount = 0,
  click = nil,     -- { x, y } of a left click this frame
  key = nil,       -- "activate" | "left" | "right" | "backspace" | "paste"
  text = "",       -- typed characters this frame
  mouseMoved = false,
  capturing = false, -- a screen is waiting for a key to bind: navigation keys go to it instead
  readOnly = false,  -- widgets show their values but can't change them (a client viewing the host's settings)
  clip = nil,        -- the scrolling region being drawn: { x, y, w, h, state }
}

-- The shared look. Screens use these instead of their own colours.
ui.ACCENT = { 1, 0.55, 0.15 }
ui.GOOD = { 0.4, 1, 0.5 }
ui.BAD = { 1, 0.6, 0.45 }
ui.GOLD = { 1, 0.85, 0.4 }
ui.INK = { 0.09, 0.09, 0.12 }
ui.PANEL = { 0.13, 0.13, 0.17 }
ui.WIDGET = { 0.17, 0.17, 0.22 }
ui.WIDGET_ON = { 0.24, 0.24, 0.32 }

local function app() return require "core.app" end
local function sound(name)
  local sfx = package.loaded["gfx.sfx"]
  if sfx then sfx.ui(name) end
end
local prevFocus = 1

-- Per-widget animation state, by widget number (hover and press ease in and out).
local anims = {}
local enterT = 1
local keyMoved = false

function ui.reset()
  ui.capturing = false
  ui.focus = 1
  ui.click = nil
  ui.key = nil
  ui.text = ""
  ui.readOnly = false
  anims = {}
  enterT = 0
end

function ui.beginFrame()
  ui.count = 0
  ui.dt = math.min(1 / 20, love.timer.getDelta())
  enterT = enterT + ui.dt
end

function ui.endFrame()
  ui.textWasActive, ui.textActive = ui.textActive, false
  if ui.focus ~= prevFocus and ui.count > 0 then sound("uiHover") end
  prevFocus = ui.focus
  ui.lastCount = ui.count
  if ui.lastCount > 0 and ui.focus > ui.lastCount then ui.focus = ui.lastCount end
  ui.click = nil
  ui.key = nil
  ui.text = ""
  ui.mouseMoved = false
  keyMoved = false
end

function ui.keypressed(key)
  if ui.capturing then return end
  local ctrl = love.keyboard.isDown("lctrl", "rctrl")
  if key == "up" or (key == "tab" and love.keyboard.isDown("lshift", "rshift")) then
    if ui.lastCount > 0 then ui.focus = (ui.focus - 2) % ui.lastCount + 1 end
    keyMoved = true
  elseif key == "down" or key == "tab" then
    if ui.lastCount > 0 then ui.focus = ui.focus % ui.lastCount + 1 end
    keyMoved = true
  elseif key == "return" or key == "kpenter" then
    ui.key = "activate"
  elseif key == "left" or key == "right" or key == "backspace" then
    ui.key = key
  elseif key == "v" and ctrl then
    ui.key = "paste"
  end
end

function ui.mousepressed(x, y, button)
  if ui.capturing then return end
  if button == 1 then ui.click = { x, y } end
end

function ui.textinput(t)
  ui.text = ui.text .. t
end

local function inClip(px, py)
  local c = ui.clip
  return not c or (px >= c.x and px <= c.x + c.w and py >= c.y and py <= c.y + c.h)
end

-- Registers a focusable widget; returns its id and whether it is hovered/focused.
local function widget(x, y, w, h)
  if not ui.active then return nil, false, false end
  ui.count = ui.count + 1
  local id = ui.count
  local mx, my = app().mouse()
  local over = mx >= x and mx <= x + w and my >= y and my <= y + h and inClip(mx, my)
  if over and ui.mouseMoved then ui.focus = id end
  local focused = ui.focus == id
  -- Keyboard / gamepad navigation brings the focused widget into view.
  local c = ui.clip
  if focused and keyMoved and c then
    if y < c.y then c.state.y = c.state.y - (c.y - y) - 8
    elseif y + h > c.y + c.h then c.state.y = c.state.y + (y + h - c.y - c.h) + 8 end
  end
  return id, over, focused
end

local function clickedInside(x, y, w, h)
  local c = ui.click
  return c and c[1] >= x and c[1] <= x + w and c[2] >= y and c[2] <= y + h and inClip(c[1], c[2])
end

local function panelColors(focused, disabled)
  if disabled then return { 0.14, 0.14, 0.18 }, { 1, 1, 1, 0.1 }, { 1, 1, 1, 0.3 } end
  if focused then return ui.WIDGET_ON, ui.ACCENT, { 1, 1, 1 } end
  return ui.WIDGET, { 1, 1, 1, 0.12 }, { 1, 1, 1, 0.85 }
end

function ui.panel(x, y, w, h, alpha)
  love.graphics.setColor(ui.PANEL[1], ui.PANEL[2], ui.PANEL[3], alpha or 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 12, 12)
  love.graphics.setColor(1, 1, 1, 0.08)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, w, h, 12, 12)
end

-- Prints text in `font`, shrunk horizontally and vertically if it wouldn't fit in `w`.
function ui.printFit(text, font, x, y, w, align)
  love.graphics.setFont(font)
  text = tostring(text)
  local tw = font:getWidth(text)
  local s = (tw > w and tw > 0) and (w / tw) or 1
  local px = x
  if align == "center" then px = x + (w - tw * s) / 2 elseif align == "right" then px = x + w - tw * s end
  love.graphics.print(text, px, y + font:getHeight() * (1 - s) / 2, 0, s, s)
end

-- Eases this widget's hover and press, and applies its entrance and size. Returns the alpha;
-- the caller pops the transform.
local function animate(id, x, y, w, h, focused)
  love.graphics.push()
  local a = 1
  if not id then return a end
  local st = anims[id]
  if not st then st = { hover = 0, press = 0 }; anims[id] = st end
  local dt = ui.dt or 0.016
  st.hover = st.hover + ((focused and 1 or 0) - st.hover) * math.min(1, dt * 18)
  st.press = math.max(0, st.press - dt * 7)
  local scale = 1 + 0.018 * st.hover - 0.035 * st.press
  local dy = 0
  if not app().noSlide then
    local k = math.max(0, math.min(1, (enterT - math.min(0.22, (id - 1) * 0.016)) / 0.2))
    local e = 1 - (1 - k) ^ 3
    dy, a = (1 - e) * 16, e
  end
  local cx, cy = x + w / 2, y + h / 2 + dy
  love.graphics.translate(cx, cy)
  love.graphics.scale(scale, scale)
  love.graphics.translate(-(x + w / 2), -(y + h / 2))
  return a
end

local function tint(c, a)
  love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * a)
end

local function pressAnim(id)
  if id and anims[id] then anims[id].press = 1 end
end

-- Returns true when clicked / activated.
-- opts: font, color, back (cancel sound), disabled, viewOnly (still works while ui.readOnly).
function ui.button(label, x, y, w, h, opts)
  opts = opts or {}
  local disabled = opts.disabled or (ui.readOnly and not opts.viewOnly)
  local id, _, focused = widget(x, y, w, h)
  local pressed = false
  if id and not disabled then
    if clickedInside(x, y, w, h) then
      pressed = true
      ui.focus = id
      ui.click = nil
    elseif focused and ui.key == "activate" then
      pressed = true
      ui.key = nil
    end
  end
  if pressed then
    sound(opts.back and "uiBack" or "uiClick")
    pressAnim(id)
  end
  local bg, border, fg = panelColors(focused, disabled)
  if opts.color and not disabled then border = opts.color end
  local a = animate(id, x, y, w, h, focused and not disabled)
  tint(bg, a)
  love.graphics.rectangle("fill", x, y, w, h, 10, 10)
  tint(border, a)
  love.graphics.setLineWidth(focused and 3 or 2)
  love.graphics.rectangle("line", x, y, w, h, 10, 10)
  local font = opts.font or app().fonts.button
  tint(fg, a)
  if label ~= "" then ui.printFit(label, font, x + 8, y + (h - font:getHeight()) / 2, w - 16, "center") end
  love.graphics.pop()
  return pressed
end

-- "Label   < value >". Returns -1, 0 or +1. opts: disabled.
function ui.cycler(label, value, x, y, w, h, opts)
  local locked = ui.readOnly or (opts and opts.disabled)
  local id, _, focused = widget(x, y, w, h)
  local delta = 0
  local valueX = x + w * 0.55
  local valueW = w * 0.45 - 10
  if id and not locked then
    if clickedInside(valueX, y, valueW / 2, h) then
      delta = -1
    elseif clickedInside(valueX + valueW / 2, y, valueW / 2, h) or clickedInside(x, y, w, h) then
      delta = 1
    end
    if delta ~= 0 then
      ui.focus = id
      ui.click = nil
      pressAnim(id)
      sound("uiClick")
    elseif focused then
      if ui.key == "left" then delta = -1 elseif ui.key == "right" or ui.key == "activate" then delta = 1 end
      if delta ~= 0 then
        ui.key = nil
        pressAnim(id)
        sound("uiClick")
      end
    end
  end
  local bg, border, fg = panelColors(focused and not locked, false)
  if locked then fg = { 1, 1, 1, 0.6 } end
  local a = animate(id, x, y, w, h, focused and not locked)
  tint(bg, a)
  love.graphics.rectangle("fill", x, y, w, h, 10, 10)
  tint(border, a)
  love.graphics.setLineWidth(focused and not locked and 3 or 2)
  love.graphics.rectangle("line", x, y, w, h, 10, 10)
  local font = app().fonts.med
  local ty = y + (h - font:getHeight()) / 2
  tint(fg, a)
  ui.printFit(label, font, x + 18, ty, valueX - x - 26, "left")
  if not locked then
    tint(focused and ui.ACCENT or { 1, 1, 1, 0.5 }, a)
    love.graphics.setFont(font)
    love.graphics.print("<", valueX, ty)
    love.graphics.printf(">", valueX, ty, valueW, "right")
  end
  tint({ 1, 1, 1, locked and 0.8 or 1 }, a)
  ui.printFit(value, font, valueX + 16, ty, valueW - 32, "center")
  love.graphics.pop()
  return delta
end

-- Removes the last UTF-8 character.
function ui.dropLastChar(text)
  local at = utf8.offset(text, -1)
  return at and text:sub(1, at - 1) or ""
end

-- Keeps at most `maxBytes` bytes without cutting a UTF-8 character in half.
function ui.limitText(text, maxBytes)
  if #text <= maxBytes then return text end
  text = text:sub(1, maxBytes)
  while #text > 0 and not utf8.len(text) do text = text:sub(1, -2) end
  return text
end

-- Single-line text field. Returns newText, submitted.
function ui.textField(text, x, y, w, h, opts)
  opts = opts or {}
  local id, _, focused = widget(x, y, w, h)
  local submitted = false
  if id then
    if clickedInside(x, y, w, h) then
      ui.focus = id
      focused = true
      ui.click = nil
    end
    if opts.forceFocus then
      ui.focus = id
      focused = true
    end
    if focused then
      ui.textActive = true
      local add = ui.text
      if ui.key == "paste" then
        add = add .. (love.system.getClipboardText() or "")
        ui.key = nil
      end
      if not utf8.len(add) then add = "" end
      add = add:gsub("[%z\1-\31\127]", "")
      if opts.filter then add = opts.filter(add) end
      if #add > 0 then
        text = ui.limitText(text .. add, opts.maxLength or 64)
        ui.text = ""
      end
      if ui.key == "backspace" then
        text = ui.dropLastChar(text)
        ui.key = nil
      elseif ui.key == "activate" then
        submitted = true
        ui.key = nil
      end
    end
  end
  local bg, border = panelColors(focused, false)
  love.graphics.setColor(bg)
  love.graphics.rectangle("fill", x, y, w, h, 10, 10)
  love.graphics.setColor(border)
  love.graphics.setLineWidth(focused and 3 or 2)
  love.graphics.rectangle("line", x, y, w, h, 10, 10)
  local font = opts.font or app().fonts.title
  local ty = y + (h - font:getHeight()) / 2
  if text == "" and not focused then
    love.graphics.setColor(1, 1, 1, 0.3)
    ui.printFit(opts.placeholder or "", font, x + 10, ty, w - 20, "center")
  else
    love.graphics.setColor(1, 1, 1)
    local shown = text
    if focused and love.timer.getTime() % 1 < 0.5 then shown = shown .. "_" else shown = shown .. " " end
    ui.printFit(shown, font, x + 10, ty, w - 20, opts.align or "center")
  end
  return text, submitted
end

---------------------------------------------------------------- scrolling
-- state = { y = 0 } kept by the screen. Between beginScroll and endScroll, lay widgets out from
-- the returned top coordinate; they are clipped to the region and scroll into view on keyboard
-- focus. Screens feed the mouse wheel to ui.wheel(state, dy).
function ui.beginScroll(state, x, y, w, h, contentH)
  state.y = math.max(0, math.min(math.max(0, contentH - h), state.y or 0))
  state.contentH = contentH
  ui.clip = { x = x, y = y, w = w, h = h, state = state }
  love.graphics.setScissor(x, y, w, h)
  return y - state.y
end

function ui.wheel(state, dy)
  state.y = (state.y or 0) - dy * 48
end

function ui.endScroll(state)
  local c = ui.clip
  ui.clip = nil
  love.graphics.setScissor()
  if not c or state.contentH <= c.h then return end
  -- Scrollbar. Dragged with the mouse or a finger (touches arrive as mouse events).
  local barX, barW = c.x + c.w + 6, 12
  local thumbH = math.max(40, c.h * c.h / state.contentH)
  local range = state.contentH - c.h
  local thumbY = c.y + (c.h - thumbH) * (state.y / range)
  local mx, my = app().mouse()
  local cl = ui.click
  if ui.active and cl and cl[1] >= barX - 6 and cl[1] <= barX + barW + 6 and cl[2] >= c.y and cl[2] <= c.y + c.h then
    state.drag = thumbH / 2
    if cl[2] >= thumbY and cl[2] <= thumbY + thumbH then state.drag = cl[2] - thumbY end
    ui.click = nil
  end
  if state.drag then
    if love.mouse.isDown(1) then
      state.y = math.max(0, math.min(range, (my - state.drag - c.y) / (c.h - thumbH) * range))
      thumbY = c.y + (c.h - thumbH) * (state.y / range)
    else
      state.drag = nil
    end
  end
  love.graphics.setColor(1, 1, 1, 0.08)
  love.graphics.rectangle("fill", barX, c.y, barW, c.h, 6, 6)
  local over = mx >= barX and mx <= barX + barW and my >= thumbY and my <= thumbY + thumbH
  love.graphics.setColor(1, 1, 1, (state.drag or over) and 0.55 or 0.3)
  love.graphics.rectangle("fill", barX, thumbY, barW, thumbH, 6, 6)
end

return ui
