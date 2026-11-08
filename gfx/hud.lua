-- Shared drawing helpers for the match: score panels, cards, black holes, crosshair.
local app = require "core.app"
local Cards = require "game.cards"

local hud = {}

-- Lay out a player's cards as "Name x2, Name, ..." wrapped to width w, aligned left or right.
-- Returns the items { card, count, text, x, y, w, h } and the total height.
function hud.cardChips(p, x, y, w, align, font)
  local order, counts = {}, {}
  for _, c in ipairs(p.cards) do
    if not counts[c] then
      counts[c] = 0
      table.insert(order, c)
    end
    counts[c] = counts[c] + 1
  end
  local sepW, fh = font:getWidth(", "), font:getHeight()
  local lines, widths = { {} }, { 0 }
  for _, c in ipairs(order) do
    local text = c.name .. (counts[c] > 1 and (" x" .. counts[c]) or "")
    local tw = font:getWidth(text)
    local li = #lines
    local need = (#lines[li] > 0 and sepW or 0) + tw
    if #lines[li] > 0 and widths[li] + need > w then
      li = li + 1
      lines[li], widths[li] = {}, 0
      need = tw
    end
    table.insert(lines[li], { card = c, count = counts[c], text = text, w = tw, h = fh })
    widths[li] = widths[li] + need
  end
  local items = {}
  for li, line in ipairs(lines) do
    local cx = align == "right" and (x + w - widths[li]) or x
    for k, item in ipairs(line) do
      if k > 1 then cx = cx + sepW end
      item.x, item.y = cx, y + (li - 1) * fh
      cx = cx + item.w
      items[#items + 1] = item
    end
  end
  return items, #order > 0 and #lines * fh or 0
end

-- One panel per player across the top of the screen. Returns the card name items
-- (see hud.cardChips, plus `bottom`, the end of that player's list) for hover tooltips.
function hud.drawScores(players, winScore)
  local hover = {}
  local n = #players
  local W = app.W
  local pw = n <= 2 and 320 or math.floor((W - 48 - (n - 1) * 16) / n)
  for i, p in ipairs(players) do
    local x, align
    if n <= 2 then
      x = i == 1 and 24 or W - 24 - pw
      align = i == 1 and "left" or "right"
    else
      x = 24 + (i - 1) * (pw + 16)
      align = "left"
    end
    local a = p.disconnected and 0.35 or 1
    local c = p.color

    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(c[1], c[2], c[3], a)
    local name = (p.name or ("PLAYER " .. i)):upper()
    if p.disconnected then name = name .. " (LEFT)" end
    love.graphics.printf(name, x, 14, pw, align)

    local spacing = 22
    if winScore * spacing <= pw then
      for k = 1, winScore do
        local px
        if align == "left" then px = x + 8 + (k - 1) * spacing else px = x + pw - 8 - (k - 1) * spacing end
        if k <= p.score then
          love.graphics.setColor(c[1], c[2], c[3], a)
          love.graphics.circle("fill", px, 48, 7)
        else
          love.graphics.setColor(1, 1, 1, 0.25 * a)
          love.graphics.setLineWidth(2)
          love.graphics.circle("line", px, 48, 7)
        end
      end
    else
      love.graphics.setColor(c[1], c[2], c[3], a)
      love.graphics.printf(p.score .. " / " .. winScore, x, 38, pw, align)
    end

    if #p.cards > 0 then
      local font = app.fonts.small
      love.graphics.setFont(font)
      local items, height = hud.cardChips(p, x, 62, pw, align, font)
      for k, item in ipairs(items) do
        local rc = Cards.rarity[item.card.rarity].color
        if k > 1 and item.y == items[k - 1].y then
          love.graphics.setColor(1, 1, 1, 0.4 * a)
          love.graphics.print(",", item.x - font:getWidth(", "), item.y)
        end
        love.graphics.setColor(rc[1], rc[2], rc[3], 0.75 * a)
        love.graphics.print(item.text, item.x, item.y)
        item.bottom = 62 + height
        hover[#hover + 1] = item
      end
    end
  end
  return hover
end

-- Which card name (from hud.drawScores) is under the point, if any.
function hud.cardAt(items, mx, my)
  for _, item in ipairs(items or {}) do
    if mx >= item.x - 2 and mx <= item.x + item.w + 2 and my >= item.y and my <= item.y + item.h then return item end
  end
end

-- What a card does, in a box just below the hovered player's card list.
function hud.drawCardTooltip(item)
  local c = item.card
  local rarity = Cards.rarity[c.rarity]
  local rc = rarity.color
  local w, pad = 320, 14
  local body = app.fonts.med
  local small = app.fonts.small
  local title = app.fonts.button

  local function wrapped(font, text) local _, ls = font:getWrap(text, w - pad * 2); return #ls * font:getHeight() end
  local h = pad + title:getHeight() + 4 + small:getHeight() + 10
  for _, line in ipairs(c.lines) do h = h + wrapped(body, line) + 4 end
  if c.stack then h = h + 6 + wrapped(small, "Stacking: " .. c.stack) end
  h = h + pad

  local x = math.max(10, math.min(app.W - w - 10, item.x - 20))
  local y = math.min(app.H - h - 10, item.bottom + 8)
  love.graphics.setColor(0.09, 0.09, 0.12, 0.97)
  love.graphics.rectangle("fill", x, y, w, h, 10, 10)
  love.graphics.setColor(rc)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, w, h, 10, 10)

  local ty = y + pad
  love.graphics.setFont(title)
  love.graphics.printf(c.name .. (item.count > 1 and ("  x" .. item.count) or ""), x + pad, ty, w - pad * 2, "left")
  ty = ty + title:getHeight() + 4
  love.graphics.setFont(small)
  love.graphics.printf(rarity.name:upper() .. (c.block and "  -  BLOCK" or ""), x + pad, ty, w - pad * 2, "left")
  ty = ty + small:getHeight() + 10
  love.graphics.setFont(body)
  for _, line in ipairs(c.lines) do
    local first = line:sub(1, 1)
    if first == "+" then
      love.graphics.setColor(0.5, 1, 0.5)
    elseif first == "-" then
      love.graphics.setColor(1, 0.45, 0.45)
    else
      love.graphics.setColor(1, 1, 1, 0.85)
    end
    love.graphics.printf(line, x + pad, ty, w - pad * 2, "left")
    ty = ty + wrapped(body, line) + 4
  end
  if c.stack then
    love.graphics.setFont(small)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.printf("Stacking: " .. c.stack, x + pad, ty + 6, w - pad * 2, "left")
  end
end

-- Card layout used for both drawing and mouse hit-testing.
-- Cards shrink so that up to 6 fit across the screen.
function hud.cardRects(n, selected)
  local ch = 360
  local gap = n <= 3 and 36 or 18
  local cw = math.min(290, math.floor((app.W - 60 - (n - 1) * gap) / math.max(1, n)))
  local startX = (app.W - (n * cw + (n - 1) * gap)) / 2
  local rects = {}
  for i = 1, n do
    rects[i] = { startX + (i - 1) * (cw + gap), i == selected and 195 or 220, cw, ch }
  end
  return rects
end

-- The back of a face-down card (rarity hidden until it is turned over).
function hud.drawCardBack(x, y, w, h, selected, ownerColor)
  love.graphics.setColor(0.16, 0.16, 0.22)
  love.graphics.rectangle("fill", x, y, w, h, 14, 14)
  love.graphics.setColor(1, 1, 1, 0.05)
  for i = 0, math.floor((w + h) / 18) do
    local o = i * 18
    love.graphics.setLineWidth(6)
    love.graphics.line(x + math.max(0, o - h), y + math.min(h, o), x + math.min(w, o), y + math.max(0, o - w))
  end
  love.graphics.setColor(0.24, 0.24, 0.32)
  love.graphics.rectangle("fill", x + w / 2 - 34, y + h / 2 - 44, 68, 88, 10, 10)
  love.graphics.setFont(app.fonts.big)
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.printf("?", x, y + h / 2 - app.fonts.big:getHeight() / 2, w, "center")
  if selected then
    love.graphics.setColor(ownerColor)
    love.graphics.setLineWidth(5)
  else
    love.graphics.setColor(1, 1, 1, 0.18)
    love.graphics.setLineWidth(2)
  end
  love.graphics.rectangle("line", x, y, w, h, 14, 14)
end

-- rarityId: optional override (the card pool editor shows the configured rarity).
function hud.drawCard(card, x, y, w, h, selected, ownerColor, rarityId)
  rarityId = rarityId or card.rarity
  local rarity = Cards.rarity[rarityId]
  local rc = rarity.color
  local t = love.timer.getTime()

  if rarityId == "legendary" then
    local pulse = 0.5 + 0.5 * math.sin(t * 3)
    love.graphics.setColor(rc[1], rc[2], rc[3], 0.15 + 0.2 * pulse)
    love.graphics.rectangle("fill", x - 8, y - 8, w + 16, h + 16, 18, 18)
  end

  love.graphics.setColor(0.12, 0.12, 0.16)
  love.graphics.rectangle("fill", x, y, w, h, 14, 14)
  love.graphics.setColor(rc)
  love.graphics.rectangle("fill", x, y, w, 80, 14, 14)
  love.graphics.rectangle("fill", x, y + 50, w, 30)

  if selected then
    love.graphics.setColor(ownerColor)
    love.graphics.setLineWidth(5)
  else
    love.graphics.setColor(rc[1], rc[2], rc[3], 0.5)
    love.graphics.setLineWidth(2)
  end
  love.graphics.rectangle("line", x, y, w, h, 14, 14)

  -- Narrow cards (5-6 on screen) use a smaller title font so long names fit.
  local titleFont = app.fonts.title
  if titleFont:getWidth(card.name) > w - 20 then titleFont = app.fonts.med end
  love.graphics.setFont(titleFont)
  love.graphics.setColor(0.08, 0.08, 0.1)
  love.graphics.printf(card.name, x + 10, y + 40 - titleFont:getHeight() / 2, w - 20, "center")

  local font = app.fonts.med
  love.graphics.setFont(font)
  local ly = y + 100
  for _, line in ipairs(card.lines) do
    local first = line:sub(1, 1)
    if first == "+" then
      love.graphics.setColor(0.5, 1, 0.5)
    elseif first == "-" then
      love.graphics.setColor(1, 0.45, 0.45)
    else
      love.graphics.setColor(1, 1, 1)
    end
    love.graphics.printf(line, x + 14, ly, w - 28, "center")
    local _, wrapped = font:getWrap(line, w - 28)
    ly = ly + #wrapped * font:getHeight() + 10
  end

  -- What extra copies do (for cards where it isn't just "the stats add up").
  if card.stack then
    local sf = app.fonts.small
    love.graphics.setFont(sf)
    local _, wrapped = sf:getWrap("Stacking: " .. card.stack, w - 28)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.printf("Stacking: " .. card.stack, x + 14, y + h - 40 - #wrapped * sf:getHeight(), w - 28, "center")
  end

  local label = rarity.name:upper()
  if card.block then label = label .. "  -  BLOCK" end
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(rc)
  love.graphics.printf(label, x, y + h - 30, w, "center")
end

function hud.drawWells(wells)
  local t = love.timer.getTime()
  for _, w in ipairs(wells) do
    local k = math.max(0, math.min(1, w.t / 0.3, (w.max - w.t) / 0.15 + 0.2))
    local c = w.owner.color
    love.graphics.setColor(c[1], c[2], c[3], 0.08 * k)
    love.graphics.circle("fill", w.x, w.y, w.radius or 280)
    love.graphics.setLineWidth(2)
    for i = 0, 2 do
      local rr = (22 + ((t * 60 + i * 20) % 60)) * k
      love.graphics.setColor(c[1], c[2], c[3], 0.5 * (1 - rr / (82 * math.max(k, 0.01))))
      love.graphics.circle("line", w.x, w.y, rr)
    end
    love.graphics.setColor(0.02, 0.02, 0.04, 0.95)
    love.graphics.circle("fill", w.x, w.y, 18 * k)
  end
end

function hud.drawCrosshair(x, y, color)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.circle("line", x, y, 11)
  love.graphics.setColor(color)
  love.graphics.circle("line", x, y, 9)
  love.graphics.line(x - 15, y, x - 5, y)
  love.graphics.line(x + 5, y, x + 15, y)
  love.graphics.line(x, y - 15, x, y - 5)
  love.graphics.line(x, y + 5, x, y + 15)
end

return hud
