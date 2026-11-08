-- The Deckshot logo: a fan of cards with a crosshair, and the name. Drawn from shapes, so it stays
-- sharp at any size.
local Logo = {}

local function card(x, y, a, w, h, stripe)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(a)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", -w / 2 + 4, -h / 2 + 5, w, h, 8, 8)
  love.graphics.setColor(0.93, 0.93, 0.97)
  love.graphics.rectangle("fill", -w / 2, -h / 2, w, h, 8, 8)
  love.graphics.setColor(stripe)
  love.graphics.rectangle("fill", -w / 2, -h / 2, w, h * 0.24, 8, 8)
  love.graphics.pop()
end

-- cx, cy: the centre. alpha fades the whole logo.
function Logo.draw(cx, cy, scale)
  local app = require "core.app"
  scale = scale or 1
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.scale(scale)
  local font = app.fonts.huge
  local text = "DECKSHOT"
  local tw = font:getWidth(text)
  local fanX = -tw / 2 - 66
  card(fanX - 26, 4, -0.34, 62, 90, { 0.3, 0.6, 1 })
  card(fanX + 26, 4, 0.34, 62, 90, { 0.75, 0.35, 1 })
  card(fanX, -4, 0, 66, 96, { 1, 0.55, 0.15 })
  love.graphics.setColor(0.1, 0.1, 0.13)
  love.graphics.setLineWidth(4)
  love.graphics.circle("line", fanX, 8, 15)
  love.graphics.line(fanX - 23, 8, fanX + 23, 8)
  love.graphics.line(fanX, 8 - 23, fanX, 8 + 23)
  local top = -font:getHeight() / 2
  love.graphics.setFont(font)
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.print(text, -tw / 2 + 26 + 5, top + 6)
  love.graphics.setColor(1, 0.55, 0.15)
  love.graphics.print(text, -tw / 2 + 26 + 2, top + 3)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print(text, -tw / 2 + 26, top)
  love.graphics.pop()
end

-- The logo over a loading bar (start-up and before a match). progress 0-1, alpha fades everything.
function Logo.drawLoading(label, progress, alpha)
  local app = require "core.app"
  love.graphics.push("all")
  Logo.draw(app.W / 2, app.H / 2 - 50, 1)
  love.graphics.pop()
  local cover = 1 - alpha
  if cover > 0 then
    love.graphics.setColor(0.09, 0.09, 0.12, cover)
    love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  end
  local w, h, x, y = 460, 10, (app.W - 460) / 2, app.H / 2 + 60
  love.graphics.setColor(1, 1, 1, 0.12 * alpha)
  love.graphics.rectangle("fill", x, y, w, h, 5, 5)
  if progress > 0.01 then
    love.graphics.setColor(1, 0.55, 0.15, alpha)
    love.graphics.rectangle("fill", x, y, math.max(h, w * progress), h, 5, 5)
  end
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.65 * alpha)
  love.graphics.printf(label, 0, y + 22, app.W, "center")
end

return Logo
