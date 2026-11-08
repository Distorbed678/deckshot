-- Achievements: lifetime counts from core/profile.lua. Each one unlocks a cosmetic.
-- Everything counts: local play, bots and online.
local Profile = require "core.profile"

local Ach = { pending = {} }

function Ach.wording(text, n)
  if n ~= 1 then return text end
  return (text:gsub(" matches$", " match"):gsub(" rounds$", " round"):gsub(" kills$", " kill"):gsub(" cards$", " card")
    :gsub(" synergies in", " synergy in"))
end

local function tier(stat, name, text, counts)
  for i, n in ipairs(counts) do
    Ach[#Ach + 1] = { id = stat .. "_" .. n, stat = stat, n = n, name = name .. (#counts > 1 and (" " .. i) or ""),
      desc = Ach.wording(string.format(text, n), n) }
  end
end

tier("wins", "Champion", "Win %d matches", { 1, 3, 5, 10, 25, 50 })
tier("rounds", "Round Winner", "Win %d rounds", { 5, 25, 50, 100, 250 })
tier("kills", "Marksman", "Get %d kills", { 10, 50, 100, 250, 500 })
tier("picks", "Collector", "Pick %d cards", { 10, 50, 100, 200, 500 })
tier("hillWins", "King of the Hill", "Win %d King of the Hill rounds", { 1, 3, 10, 25 })
tier("matches", "Regular", "Play %d matches", { 1, 10, 50 })
tier("blocks", "Wall", "Block %d attacks", { 25, 100, 500 })
tier("meleeKills", "Brawler", "Get %d melee kills", { 5, 25, 100 })
tier("maps", "Tourist", "Play on %d different maps", { 10, 25, 55 })
tier("synergies", "Combo Artist", "Finish matches with %d synergies in total", { 1, 10 })
tier("peakCards", "Stacked", "Hold %d cards in one match", { 10, 15 })
tier("flawless", "Untouched", "Win %d rounds without taking damage", { 1, 5 })
tier("sudden", "Clutch", "Win %d round during sudden death", { 1 })

function Ach.count()
  return #Ach
end

function Ach.earned(id)
  return Profile.earned[id] == true
end

function Ach.progress(a)
  return math.min(Profile.stats[a.stat] or 0, a.n)
end

-- Marks what's been reached. quiet: no popup (progress from before achievements existed).
function Ach.check(quiet)
  for i = 1, #Ach do
    local a = Ach[i]
    if not Profile.earned[a.id] and (Profile.stats[a.stat] or 0) >= a.n then
      Profile.earned[a.id] = true
      Profile.dirty = true
      if not quiet then Ach.pending[#Ach.pending + 1] = { a = a, t = 6 } end
    end
  end
end

-- Popups for new achievements (top middle of the match-over screen and the main menu).
function Ach.draw(startY)
  if #Ach.pending == 0 then return end
  local app = require "core.app"
  local ui = require "core.ui"
  local dt = love.timer.getDelta()
  local y = startY or 12
  for i = #Ach.pending, 1, -1 do
    local e = Ach.pending[i]
    e.t = e.t - dt
    if e.t <= 0 then table.remove(Ach.pending, i) end
  end
  for i = 1, math.min(3, #Ach.pending) do
    local e = Ach.pending[i]
    local a = math.min(1, e.t * 2)
    local w, h, x = 340, 58, app.W - 354
    love.graphics.setColor(0.13, 0.13, 0.17, 0.96 * a)
    love.graphics.rectangle("fill", x, y, w, h, 10, 10)
    love.graphics.setColor(ui.GOLD[1], ui.GOLD[2], ui.GOLD[3], a)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h, 10, 10)
    ui.printFit("Achievement: " .. e.a.name, app.fonts.med, x + 14, y + 7, w - 28, "left")
    love.graphics.setColor(1, 1, 1, 0.75 * a)
    ui.printFit(e.a.reward and ("Unlocked " .. e.a.reward) or e.a.desc, app.fonts.small, x + 14, y + 33, w - 28, "left")
    y = y + h + 8
  end
end

return Ach
