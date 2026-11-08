-- Tiny immediate-mode UI: widgets are declared while drawing and return what happened.
-- Mouse: hover + click. Keyboard: Up/Down (or Tab) to move, Enter to activate,
-- Left/Right to change option values.
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
}

ui.ACCENT = { 1, 0.55, 0.15 }

local function app() return require "core.app" end
local function sound(name)
  local sfx = package.loaded["gfx.sfx"]
  if sfx then sfx.ui(name) end
end
local prevFocus = 1

function ui.reset()
  ui.capturing = false
  ui.focus = 1
  ui.click = nil
  ui.key = nil
  ui.text = ""
end

function ui.beginFrame()
  ui.count = 0
end

function ui.endFrame()
  if ui.focus ~= prevFocus and ui.count > 0 then sound("uiHover") end
  prevFocus = ui.focus
  ui.lastCount = ui.count
  if ui.lastCount > 0 and ui.focus > ui.lastCount then ui.focus = ui.lastCount end
  ui.click = nil
  ui.key = nil
  ui.text = ""
  ui.mouseMoved = false
end

function ui.keypressed(key)
  if ui.capturing then return end
  local ctrl = love.keyboard.isDown("lctrl", "rctrl")
  if key == "up" or (key == "tab" and love.keyboard.isDown("lshift", "rshift")) then
    if ui.lastCount > 0 then ui.focus = (ui.focus - 2) % ui.lastCount + 1 end
  elseif key == "down" or key == "tab" then
    if ui.lastCount > 0 then ui.focus = ui.focus % ui.lastCount + 1 end
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

-- Registers a focusable widget; returns its id and whether it is hovered/focused.
local function widget(x, y, w, h)
  if not ui.active then return nil, false, false end
  ui.count = ui.count + 1
  local id = ui.count
  local mx, my = app().mouse()
  local over = mx >= x and mx <= x + w and my >= y and my <= y + h
  if over and ui.mouseMoved then ui.focus = id end
  return id, over, ui.focus == id
end

local function clickedInside(x, y, w, h)
  local c = ui.click
  return c and c[1] >= x and c[1] <= x + w and c[2] >= y and c[2] <= y + h
end

local function panelColors(focused, disabled)
  if disabled then return { 0.14, 0.14, 0.18 }, { 1, 1, 1, 0.1 }, { 1, 1, 1, 0.3 } end
  if focused then return { 0.24, 0.24, 0.32 }, ui.ACCENT, { 1, 1, 1 } end
  return { 0.17, 0.17, 0.22 }, { 1, 1, 1, 0.12 }, { 1, 1, 1, 0.85 }
end

function ui.panel(x, y, w, h, alpha)
  love.graphics.setColor(0.13, 0.13, 0.17, alpha or 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 12, 12)
  love.graphics.setColor(1, 1, 1, 0.08)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, w, h, 12, 12)
end

-- Returns true when clicked / activated.
function ui.button(label, x, y, w, h, opts)
  opts = opts or {}
  local id, _, focused = widget(x, y, w, h)
  local pressed = false
  if id and not opts.disabled then
    if clickedInside(x, y, w, h) then
      pressed = true
      ui.focus = id
      ui.click = nil
    elseif focused and ui.key == "activate" then
      pressed = true
      ui.key = nil
    end
  end
  if pressed then sound(opts.back and "uiBack" or "uiClick") end
  local bg, border, fg = panelColors(focused, opts.disabled)
  if opts.color and not opts.disabled then border = opts.color end
  love.graphics.setColor(bg)
  love.graphics.rectangle("fill", x, y, w, h, 10, 10)
  love.graphics.setColor(border)
  love.graphics.setLineWidth(focused and 3 or 2)
  love.graphics.rectangle("line", x, y, w, h, 10, 10)
  local font = opts.font or app().fonts.button
  love.graphics.setFont(font)
  love.graphics.setColor(fg)
  love.graphics.printf(label, x, y + (h - font:getHeight()) / 2, w, "center")
  return pressed
end

-- "Label   < value >". Returns -1, 0 or +1.
function ui.cycler(label, value, x, y, w, h)
  local id, _, focused = widget(x, y, w, h)
  local delta = 0
  local valueX = x + w * 0.55
  local valueW = w * 0.45 - 10
  if id then
    if clickedInside(valueX, y, valueW / 2, h) then
      delta = -1
    elseif clickedInside(valueX + valueW / 2, y, valueW / 2, h) or clickedInside(x, y, w, h) then
      delta = 1
    end
    if delta ~= 0 then
      ui.focus = id
      ui.click = nil
    elseif focused then
      if ui.key == "left" then delta = -1 elseif ui.key == "right" or ui.key == "activate" then delta = 1 end
      if delta ~= 0 then ui.key = nil end
    end
  end
  local bg, border, fg = panelColors(focused, false)
  love.graphics.setColor(bg)
  love.graphics.rectangle("fill", x, y, w, h, 10, 10)
  love.graphics.setColor(border)
  love.graphics.setLineWidth(focused and 3 or 2)
  love.graphics.rectangle("line", x, y, w, h, 10, 10)
  local font = app().fonts.med
  love.graphics.setFont(font)
  local ty = y + (h - font:getHeight()) / 2
  love.graphics.setColor(fg)
  love.graphics.print(label, x + 18, ty)
  love.graphics.setColor(focused and ui.ACCENT or { 1, 1, 1, 0.5 })
  love.graphics.print("<", valueX, ty)
  love.graphics.printf(">", valueX, ty, valueW, "right")
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(value, valueX, ty, valueW, "center")
  return delta
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
    if focused then
      local add = ui.text
      if ui.key == "paste" then
        add = add .. (love.system.getClipboardText() or "")
        ui.key = nil
      end
      if opts.filter then add = opts.filter(add) end
      if #add > 0 then
        text = (text .. add):sub(1, opts.maxLength or 64)
        ui.text = ""
      end
      if ui.key == "backspace" then
        text = text:sub(1, -2)
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
  love.graphics.setFont(font)
  local ty = y + (h - font:getHeight()) / 2
  if text == "" and not focused then
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.printf(opts.placeholder or "", x, ty, w, "center")
  else
    love.graphics.setColor(1, 1, 1)
    local shown = text
    if focused and love.timer.getTime() % 1 < 0.5 then shown = shown .. "_" else shown = shown .. " " end
    love.graphics.printf(shown, x, ty, w, "center")
  end
  return text, submitted
end

return ui
