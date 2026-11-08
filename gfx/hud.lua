-- Shared drawing helpers for the match: score panels, cards, black holes, crosshair.
local app = require "core.app"
local ui = require "core.ui"
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
-- Round timer, top middle. left: seconds until sudden death.
function hud.drawTimer(left)
  if not left then return end
  local cx, w, h = app.W / 2, 124, 40
  local urgent = left > 0 and left <= 10
  if left <= 0 then
    local a = 0.65 + 0.35 * math.sin(love.timer.getTime() * 7)
    love.graphics.setColor(0.45, 0.05, 0.05, 0.85)
    love.graphics.rectangle("fill", cx - 100, 8, 200, h, 8, 8)
    love.graphics.setColor(1, 0.35, 0.3, a)
    love.graphics.setFont(app.fonts.med)
    love.graphics.printf("SUDDEN DEATH", cx - 100, 8 + (h - app.fonts.med:getHeight()) / 2, 200, "center")
    return
  end
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", cx - w / 2, 8, w, h, 8, 8)
  local s = math.ceil(left)
  local text = string.format("%d:%02d", math.floor(s / 60), s % 60)
  love.graphics.setFont(app.fonts.title)
  if urgent then
    local pulse = 0.5 + 0.5 * math.abs(math.sin(left * math.pi))
    love.graphics.setColor(1, 0.3 + 0.2 * pulse, 0.25, 1)
  else
    love.graphics.setColor(1, 1, 1, 0.9)
  end
  love.graphics.printf(text, cx - w / 2, 8 + (h - app.fonts.title:getHeight()) / 2, w, "center")
end

-- King of the Hill: the zone, in world coordinates. hill = { x, y, t, owner }.
function hud.drawHill(hill, players, H)
  local c = { 1, 1, 1 }
  if hill.owner == 255 then c = { 1, 0.45, 0.2 }
  elseif hill.owner > 0 and players[hill.owner] then c = players[hill.owner].color end
  local x, y = hill.x - H.w / 2, hill.y - H.h / 2
  local a = 0.13 + 0.05 * math.sin(love.timer.getTime() * 5)
  love.graphics.setColor(c[1], c[2], c[3], a)
  love.graphics.rectangle("fill", x, y, H.w, H.h, 14, 14)
  love.graphics.setColor(c[1], c[2], c[3], 0.85)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", x, y, H.w, H.h, 14, 14)
  if hill.t > 0 then
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.rectangle("fill", x + 10, y - 9, (H.w - 20) * math.min(1, hill.t / H.move), 4, 2, 2)
  end
end

-- King of the Hill: each side's progress, under the timer.
function hud.drawHillScores(players, target, scoreOf)
  local w, cx = 240, app.W / 2
  local y, seen = 54, {}
  for i, p in ipairs(players) do
    local key = p.team or -i
    if not seen[key] and not p.disconnected then
      seen[key] = true
      local frac = math.max(0, math.min(1, scoreOf(i) / target))
      love.graphics.setColor(0, 0, 0, 0.55)
      love.graphics.rectangle("fill", cx - w / 2, y, w, 9, 4, 4)
      if w * frac > 2 then
        love.graphics.setColor(p.color)
        love.graphics.rectangle("fill", cx - w / 2, y, w * frac, 9, 4, 4)
      end
      y = y + 13
    end
  end
end

-- A circle cut into n segments with `filled` of them coloured. lastK (0-1) animates the newest one in.
function hud.drawPie(x, y, r, n, filled, color, alpha, lastK)
  alpha = alpha or 1
  n = math.max(1, n)
  love.graphics.setColor(0, 0, 0, 0.45 * alpha)
  love.graphics.circle("fill", x, y, r)
  for i = 1, math.min(filled, n) do
    local a0 = -math.pi / 2 + (i - 1) * 2 * math.pi / n
    local a1 = a0 + 2 * math.pi / n
    local rr = r
    if lastK and i == filled then rr = r * lastK end
    love.graphics.setColor(color[1], color[2], color[3], alpha)
    if n == 1 then love.graphics.circle("fill", x, y, rr) else love.graphics.arc("fill", x, y, rr, a0, a1) end
  end
  love.graphics.setColor(color[1], color[2], color[3], alpha)
  love.graphics.setLineWidth(math.max(1.5, r * 0.08))
  love.graphics.circle("line", x, y, r)
  if n > 1 then
    for i = 1, n do
      local a = -math.pi / 2 + (i - 1) * 2 * math.pi / n
      love.graphics.line(x, y, x + math.cos(a) * r, y + math.sin(a) * r)
    end
  end
end

-- Top left: a row of points for each player or team; the next point shows sub-round progress.
-- Top right: every player's cards as boxes with 2-letter initials. Returns hover items.
function hud.drawScores(players, winScore)
  local hover = {}
  local need = math.max(1, Cards.rules.subRounds or 1)
  local gap = math.min(24, 460 / math.max(1, winScore))
  local dotR = math.min(8, gap * 0.42)
  local y, seen = 18, {}
  for i, p in ipairs(players) do
    local key = p.team or -i
    if not seen[key] then
      seen[key] = true
      local a = p.disconnected and 0.35 or 1
      local c = p.color
      for k = 1, winScore do
        local x = 18 + (k - 1) * gap
        if k <= p.score then
          love.graphics.setColor(c[1], c[2], c[3], a)
          love.graphics.circle("fill", x, y, dotR)
        elseif k == p.score + 1 then
          hud.drawPie(x, y, dotR, need, p.subWins or 0, c, a)
        else
          love.graphics.setColor(c[1], c[2], c[3], 0.55 * a)
          love.graphics.circle("fill", x, y, dotR * 0.42)
        end
      end
      y = y + dotR * 2 + 8
    end
  end

  local size, sp, perRow = 30, 4, 12
  local rowY = 10
  for i, p in ipairs(players) do
    local a = p.disconnected and 0.35 or 1
    local c = p.color
    local n = #p.cards
    for k = 1, n do
      local card = p.cards[k]
      local col = (k - 1) % perRow
      local row = math.floor((k - 1) / perRow)
      local x, by = app.W - 14 - size - col * (size + sp), rowY + row * (size + sp)
      love.graphics.setColor(0.06, 0.06, 0.09, 0.72 * a)
      love.graphics.rectangle("fill", x, by, size, size, 5, 5)
      love.graphics.setColor(c[1], c[2], c[3], 0.85 * a)
      love.graphics.setLineWidth(1.5)
      love.graphics.rectangle("line", x, by, size, size, 5, 5)
      local rc = Cards.rarity[card.rarity] and Cards.rarity[card.rarity].color or { 1, 1, 1 }
      love.graphics.setColor(rc[1], rc[2], rc[3], a)
      ui.printFit(card.name:sub(1, 2), app.fonts.small, x + 3, by + (size - app.fonts.small:getHeight()) / 2, size - 6, "center")
      hover[#hover + 1] = { x = x, y = by, w = size, h = size, card = card, count = 1, bottom = by + size }
    end
    rowY = rowY + math.max(1, math.ceil(n / perRow)) * (size + sp) + 4
  end
  hud.cardsBottom = rowY
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
-- Cards fanned in an arc above the character. Each rect is { x, y, w, h, cx =, cy =, a = } (a: tilt);
-- lift: card index -> 0..1, how far that card has slid out toward you.
function hud.cardRects(n, selected, lift)
  local step = n <= 3 and 0.42 or n == 4 and 0.36 or n == 5 and 0.31 or 0.26
  local cw, ch = n >= 6 and 190 or 215, n >= 6 and 265 or 300
  local R, cy0 = 640, 930
  local rects = {}
  for i = 1, n do
    local a = (i - (n + 1) / 2) * step
    local k = lift and (lift[i] or 0) or (i == selected and 1 or 0)
    local cx = app.W / 2 + math.sin(a) * (R + 26 * k)
    local cy = cy0 - math.cos(a) * (R + 26 * k)
    rects[i] = { cx - cw / 2, cy - ch / 2, cw, ch, cx = cx, cy = cy, a = a }
  end
  return rects
end

-- A small wrench: marks custom and edited cards (and maps).
function hud.drawWrench(x, y, size, color)
  love.graphics.setColor(color or { 1, 1, 1 })
  love.graphics.push()
  love.graphics.translate(x + size / 2, y + size / 2)
  love.graphics.rotate(-math.pi / 4)
  love.graphics.rectangle("fill", -size * 0.1, -size * 0.1, size * 0.2, size * 0.55)
  love.graphics.circle("fill", 0, -size * 0.22, size * 0.24)
  love.graphics.setColor(1, 1, 1, 0)
  love.graphics.pop()
  love.graphics.setColor(color or { 1, 1, 1 })
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

  -- Shrink the text until every line (and the stacking note) fits on the card.
  local stackH = 0
  if card.stack then
    local _, sw = app.fonts.small:getWrap("Stacking: " .. card.stack, w - 28)
    stackH = #sw * app.fonts.small:getHeight() + 6
  end
  local synergyLine = #require("game.synergies").forCard(card, Cards.rules) > 0
  local bottomGap = synergyLine and 56 or 40
  local room = h - 100 - bottomGap - stackH
  local font, gap
  for _, f in ipairs({ { app.fonts.med, 10 }, { app.fonts.small, 6 }, { app.fonts.tiny, 3 } }) do
    font, gap = f[1], f[2]
    local total = 0
    for _, line in ipairs(card.lines) do
      local _, wr = font:getWrap(line, w - 28)
      total = total + #wr * font:getHeight() + gap
    end
    if total <= room then break end
  end
  love.graphics.setFont(font)
  local ly = y + 100
  for i, line in ipairs(card.lines) do
    local good
    if card.lineGood then
      good = card.lineGood[i]
    else
      local first = line:sub(1, 1)
      good = (first == "+" and true) or (first == "-" and false) or nil
    end
    if good == true then
      love.graphics.setColor(0.5, 1, 0.5)
    elseif good == false then
      love.graphics.setColor(1, 0.45, 0.45)
    else
      love.graphics.setColor(1, 1, 1)
    end
    love.graphics.printf(line, x + 14, ly, w - 28, "center")
    local _, wrapped = font:getWrap(line, w - 28)
    ly = ly + #wrapped * font:getHeight() + gap
  end

  -- What extra copies do (for cards where it isn't just "the stats add up").
  if card.stack then
    local sf = app.fonts.small
    love.graphics.setFont(sf)
    local _, wrapped = sf:getWrap("Stacking: " .. card.stack, w - 28)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.printf("Stacking: " .. card.stack, x + 14, y + h - bottomGap - #wrapped * sf:getHeight(), w - 28, "center")
  end

  -- Synergies this card is part of.
  local syns = require("game.synergies").forCard(card, Cards.rules)
  if #syns > 0 then
    local names = {}
    for k = 1, math.min(2, #syns) do names[#names + 1] = require("game.synergies").partners(syns[k], card) end
    local text = "Synergy: " .. table.concat(names, ", ") .. (#syns > 2 and (" +" .. (#syns - 2)) or "")
    love.graphics.setFont(app.fonts.tiny)
    love.graphics.setColor(1, 0.82, 0.35, 0.85)
    love.graphics.printf(text, x + 10, y + h - 50, w - 20, "center")
  end

  local label = rarity.name:upper()
  if card.block then label = label .. "  -  BLOCK" end
  if card.custom or card.edited then hud.drawWrench(x + w - 26, y + 8, 18, { 0.08, 0.08, 0.1 }) end
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(rc)
  love.graphics.printf(label, x, y + h - 30, w, "center")
end

-- The sudden-death barrier: darkness outside a pulsing red rect.
function hud.drawBarrier(b, glowOnly)
  local x0, y0, x1, y1 = b[1], b[2], b[3], b[4]
  local a = 0.6 + 0.25 * math.sin(love.timer.getTime() * 6)
  if not glowOnly then
    love.graphics.setColor(0.35, 0, 0, 0.35)
    love.graphics.rectangle("fill", 0, 0, app.W, y0)
    love.graphics.rectangle("fill", 0, y1, app.W, app.H - y1)
    love.graphics.rectangle("fill", 0, y0, x0, y1 - y0)
    love.graphics.rectangle("fill", x1, y0, app.W - x1, y1 - y0)
  end
  love.graphics.setColor(1, 0.15, 0.12, a)
  love.graphics.setLineWidth(glowOnly and 8 or 4)
  love.graphics.rectangle("line", x0, y0, x1 - x0, y1 - y0)
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
