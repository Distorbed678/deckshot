-- The match recap: every player's numbers and build, plus awards, on one page that can be saved as
-- an image. It belongs to the match screen (the host keeps simulating underneath), and everything
-- on it comes from data that clients already have, so it works the same online.
local app = require "core.app"
local ui = require "core.ui"
local platform = require "core.platform"
local Settings = require "core.settings"
local Cards = require "game.cards"
local CardArt = require "gfx.cardart"
local Logo = require "gfx.logo"
local sfx = require "gfx.sfx"

local Recap = {}

local function st(p, key) return p.st and p.st[key] or 0 end
local function accuracy(p)
  local shots = st(p, "shots")
  return shots > 0 and st(p, "hits") / shots or 0
end

-- The highest deficit the winning side came back from, using the round winners in order.
-- history: winner slot per point (0 = draw).
function Recap.comeback(players, history, winner)
  if not winner then return 0 end
  local function side(slot)
    local p = players[slot]
    return p and (p.team or -slot) or nil
  end
  local winnerSide
  for slot, p in ipairs(players) do
    if p == winner then winnerSide = side(slot) end
  end
  local points, worst = {}, 0
  for _, slot in ipairs(history or {}) do
    local s = side(slot)
    if s then points[s] = (points[s] or 0) + 1 end
    local best = 0
    for k, v in pairs(points) do if k ~= winnerSide and v > best then best = v end end
    worst = math.max(worst, best - (points[winnerSide] or 0))
  end
  return worst
end

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

local AWARDS = {
  { title = "Top Gun", value = function(p) return st(p, "kills") end, text = function(v) return plural(v, "kill") end, min = 1 },
  { title = "Heavy Hitter", value = function(p) return math.floor(st(p, "dmg")) end, text = function(v) return v .. " damage" end, min = 1 },
  { title = "Sharpshooter", value = function(p) return st(p, "shots") >= 15 and accuracy(p) or 0 end,
    text = function(v) return math.floor(v * 100 + 0.5) .. "% accuracy" end, min = 0.01 },
  { title = "Brick Wall", value = function(p) return st(p, "blocks") end, text = function(v) return plural(v, "block") end, min = 3 },
  { title = "Brawler", value = function(p) return st(p, "melee") end, text = function(v) return plural(v, "melee hit") end, min = 3 },
  { title = "Trigger Happy", value = function(p) return st(p, "shots") end, text = function(v) return plural(v, "shot") end, min = 1 },
  { title = "Collector", value = function(p) return #p.cards end, text = function(v) return plural(v, "card") end, min = 1 },
  { title = "Punching Bag", value = function(p) return st(p, "deaths") end, text = function(v) return plural(v, "death") end, min = 1 },
}

-- Up to 6 awards, as { title, text, player }. A tie for first means nobody gets that award.
-- Everyone gets one before anyone gets a second, where the numbers allow it.
function Recap.awards(players, history, winner)
  local list = {}
  local comeback = Recap.comeback(players, history, winner)
  if winner and comeback >= 2 then
    list[1] = { title = "Comeback Kid", text = "Won from " .. comeback .. " points behind", player = winner }
  end
  for _, a in ipairs(AWARDS) do
    local best, top, tied = a.min - 1e-9, nil, false
    for _, p in ipairs(players) do
      local v = a.value(p)
      if v > best then best, top, tied = v, p, false
      elseif v == best and top then tied = true end
    end
    if top and not tied then list[#list + 1] = { title = a.title, text = a.text(best), player = top } end
  end
  local chosen, has, used = {}, {}, {}
  for i, a in ipairs(list) do
    if not has[a.player] and #chosen < 6 then
      chosen[#chosen + 1], has[a.player], used[i] = a, true, true
    end
  end
  for i, a in ipairs(list) do
    if not used[i] and #chosen < 6 then chosen[#chosen + 1] = a end
  end
  return chosen
end

-- Each different card once with how many copies, rarest first.
local RANK = {}
for i, r in ipairs(Cards.RARITIES) do RANK[r.id] = i end
local function build(p)
  local order, count = {}, {}
  for _, c in ipairs(p.cards) do
    if not count[c] then
      count[c] = 0
      order[#order + 1] = c
    end
    count[c] = count[c] + 1
  end
  table.sort(order, function(a, b)
    local ra, rb = RANK[a.rarity] or 0, RANK[b.rarity] or 0
    if ra ~= rb then return ra > rb end
    return a.name < b.name
  end)
  return order, count
end

local function ranked(players)
  local out = {}
  for i, p in ipairs(players) do out[i] = p end
  local slotOf = {}
  for i, p in ipairs(players) do slotOf[p] = i end
  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return slotOf[a] < slotOf[b]
  end)
  return out
end

local function history(m)
  return m.role == "client" and m.view.history or (m.world and m.world.history) or {}
end

local COLS = { { "Score", 250 }, { "Kills", 320 }, { "Deaths", 390 }, { "Damage", 470 }, { "Accuracy", 560 } }
local CARDS_X = 690

local function drawPlayerRow(m, p, i, x, y, w, h)
  love.graphics.setColor(1, 1, 1, 0.05)
  love.graphics.rectangle("fill", x, y, w, h, 8, 8)
  love.graphics.setColor(p.color)
  love.graphics.rectangle("fill", x, y + 8, 4, h - 16, 2, 2)
  m.recapFigs = m.recapFigs or {}
  local f = m.recapFigs[p]
  if not f then
    f = { r = 19, slot = i, facing = 1, aimX = 1, aimY = 0, noGun = true }
    m.recapFigs[p] = f
  end
  f.x, f.y = x + 46, y + h / 2 - 8
  f.color, f.hat, f.eyes, f.mouth, f.detail = p.color, p.hat, p.eyes, p.mouth, p.detail
  require("game.body").drawFigure(f, love.timer.getDelta())

  love.graphics.setColor(p.color)
  ui.printFit(p.name or ("Player " .. i), app.fonts.med, x + 108, y + (h - app.fonts.med:getHeight()) / 2, 150, "left")
  local acc = st(p, "shots") > 0 and (math.floor(accuracy(p) * 100 + 0.5) .. "%") or "-"
  local vals = { tostring(p.score), tostring(st(p, "kills")), tostring(st(p, "deaths")), tostring(math.floor(st(p, "dmg"))), acc }
  for k, c in ipairs(COLS) do
    love.graphics.setColor(1, 1, 1, k == 1 and 1 or 0.85)
    ui.printFit(vals[k], k == 1 and app.fonts.title or app.fonts.med, x + c[2] + 16, y + (h - (k == 1 and app.fonts.title or app.fonts.med):getHeight()) / 2, 80, "center")
  end

  local order, count = build(p)
  local r, step = 19, 42
  local room = math.floor((w - CARDS_X - 10) / step)
  local cy = y + h / 2
  for k, c in ipairs(order) do
    if k > room or (k == room and #order > room) then
      love.graphics.setColor(1, 1, 1, 0.6)
      ui.printFit("+" .. (#order - k + 1), app.fonts.small, x + CARDS_X + (k - 1) * step, cy - app.fonts.small:getHeight() / 2, step, "center")
      break
    end
    local cx = x + CARDS_X + (k - 1) * step + r
    CardArt.medal(c, cx, cy, r, Cards.rarity[c.rarity] and Cards.rarity[c.rarity].color or { 1, 1, 1 })
    if count[c] > 1 then
      love.graphics.setColor(0, 0, 0, 0.75)
      love.graphics.circle("fill", cx - r * 0.72, cy - r * 0.72, 9, 16)
      love.graphics.setColor(1, 1, 1)
      ui.printFit(tostring(count[c]), app.fonts.tiny, cx - r * 0.72 - 9, cy - r * 0.72 - app.fonts.tiny:getHeight() / 2, 18, "center")
    end
  end
end

local function modeLine()
  local rules = Cards.rules or {}
  local mode = Settings.MODE_NAMES and Settings.MODE_NAMES[rules.mode] or "Elimination"
  return mode .. (rules.teams and ", Teams" or ", Free-for-all")
end

function Recap.draw(m, st_)
  local capturing = m.recapShot ~= nil
  local players = m:players()
  local winner = st_.winner
  love.graphics.setColor(0.07, 0.07, 0.1)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local wc = winner and winner.color or { 1, 1, 1 }
  love.graphics.setColor(wc)
  love.graphics.rectangle("fill", 0, 0, app.W, 6)

  Logo.draw(190, 52, 0.34)
  love.graphics.setColor(1, 1, 1, 0.55)
  ui.printFit(modeLine() .. "  -  first to " .. st_.winScore, app.fonts.small, app.W - 430, 62, 400, "right")
  love.graphics.setColor(1, 1, 1)
  ui.printFit("MATCH RECAP", app.fonts.title, app.W - 430, 26, 400, "right")
  if winner then
    love.graphics.setColor(wc)
    ui.printFit((winner.name or "Player"):upper() .. " WINS!", app.fonts.big, 350, 30, app.W - 800, "center")
  end

  local x, w, y = 30, app.W - 60, 104
  love.graphics.setFont(app.fonts.tiny)
  love.graphics.setColor(1, 1, 1, 0.5)
  for _, c in ipairs(COLS) do love.graphics.printf(c[1], x + c[2] + 16, y, 80, "center") end
  love.graphics.print("Final build", x + CARDS_X, y)
  y = y + 22
  local rowH = 70
  for i, p in ipairs(ranked(players)) do
    drawPlayerRow(m, p, i, x, y, w, rowH - 6)
    y = y + rowH
  end

  local awards = Recap.awards(players, history(m), winner)
  y = y + 8
  local gap, tileW, tileH = 12, (w - 24) / 3, 70
  for i, a in ipairs(awards) do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local tx, ty = x + col * (tileW + gap), y + row * (tileH + gap)
    love.graphics.setColor(1, 0.8, 0.3, 0.09)
    love.graphics.rectangle("fill", tx, ty, tileW, tileH, 8, 8)
    love.graphics.setColor(1, 0.8, 0.3, 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", tx, ty, tileW, tileH, 8, 8)
    love.graphics.setColor(ui.GOLD)
    ui.printFit(a.title, app.fonts.med, tx + 16, ty + 9, tileW / 2 - 20, "left")
    love.graphics.setColor(a.player.color)
    ui.printFit(a.player.name or "Player", app.fonts.med, tx + tileW / 2, ty + 9, tileW / 2 - 16, "right")
    love.graphics.setColor(1, 1, 1, 0.75)
    ui.printFit(a.text, app.fonts.small, tx + 16, ty + 40, tileW - 32, "left")
  end

  if capturing then
    m.recapShot = 2 -- this frame has no buttons: Recap.update saves it
    love.graphics.setColor(1, 1, 1, 0.4)
    ui.printFit("Deckshot  -  distorbed678.github.io/deckshot", app.fonts.small, 0, 694, app.W, "center")
    return
  end

  local showOpen = m.recapSaved and not platform.web
  local bw, bh, by = 270, 44, 648
  local total = bw * (showOpen and 3 or 2) + 16 * (showOpen and 2 or 1)
  local bx = (app.W - total) / 2
  if ui.button("Save Image", bx, by, bw, bh, { color = ui.GOOD }) then m.recapShot = 1 end
  bx = bx + bw + 16
  if showOpen then
    if ui.button("Open Folder", bx, by, bw, bh) then
      love.system.openURL("file://" .. love.filesystem.getSaveDirectory() .. "/recaps")
    end
    bx = bx + bw + 16
  end
  if ui.button("Back", bx, by, bw, bh, { back = true }) then m.recapOpen = false end
  if m.recapMessage then
    love.graphics.setColor(1, 1, 1, 0.7)
    ui.printFit(m.recapMessage, app.fonts.small, 40, 698, app.W - 460, "left")
  end
end

-- Called from the match's update, once the button-free frame has been drawn.
function Recap.update(m)
  if m.recapShot ~= 2 then return end
  m.recapShot = nil
  local ok, png = pcall(function()
    local source = app.canvas
    if source:getFormat() == "rgba16f" then -- browsers can't read these back directly
      local plain = love.graphics.newCanvas(source:getPixelWidth(), source:getPixelHeight(), { dpiscale = 1 })
      love.graphics.push("all")
      love.graphics.origin()
      love.graphics.setCanvas(plain)
      love.graphics.setColor(1, 1, 1)
      love.graphics.setBlendMode("alpha", "premultiplied")
      love.graphics.draw(source, 0, 0, 0, source:getDPIScale(), source:getDPIScale())
      love.graphics.pop()
      source = plain
    end
    local data = source:newImageData()
    -- Browsers can give a 16-bit canvas, and encoding one as PNG hangs: copy it to 8-bit first.
    if data:getFormat() ~= "rgba8" then
      local src = data
      data = love.image.newImageData(src:getWidth(), src:getHeight(), "rgba8")
      data:mapPixel(function(x, y) return src:getPixel(x, y) end)
    end
    return data:encode("png")
  end)
  if not ok then
    m.recapMessage = "Couldn't save the image"
    return
  end
  if platform.web then
    print("\27SAVEPNG " .. love.data.encode("string", "base64", png:getString()))
    m.recapMessage = "Image downloaded"
  else
    local name = os.date("deckshot-%Y%m%d-%H%M%S.png")
    love.filesystem.createDirectory("recaps")
    local wrote = love.filesystem.write("recaps/" .. name, png:getString())
    m.recapSaved = wrote or m.recapSaved
    m.recapMessage = wrote and ("Saved as recaps/" .. name) or "Couldn't save the image"
  end
  sfx.ui("uiClick")
end

return Recap
