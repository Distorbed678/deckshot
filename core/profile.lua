-- Local play statistics (codex): how often each card was offered to you, picked by you, and how
-- many rounds you won while holding it. Saved to profile.txt in the save folder.
local Profile = { cards = {}, dirty = false }

local FILE = "profile.txt"

function Profile.load()
  Profile.cards = {}
  if not love.filesystem.getInfo(FILE) then return end
  for line in love.filesystem.lines(FILE) do
    local id, o, p, w = line:match("^card%.([%w_]+)=(%d+),(%d+),(%d+)$")
    if id then Profile.cards[id] = { offered = tonumber(o), picked = tonumber(p), wins = tonumber(w) } end
  end
end

function Profile.save()
  if not Profile.dirty then return end
  local lines = {}
  for id, c in pairs(Profile.cards) do
    lines[#lines + 1] = string.format("card.%s=%d,%d,%d", id, c.offered, c.picked, c.wins)
  end
  table.sort(lines)
  love.filesystem.write(FILE, table.concat(lines, "\n") .. "\n")
  Profile.dirty = false
end

function Profile.card(id)
  local c = Profile.cards[id]
  if not c then
    c = { offered = 0, picked = 0, wins = 0 }
    Profile.cards[id] = c
  end
  return c
end

function Profile.add(id, field)
  if not id then return end
  local c = Profile.card(id)
  c[field] = c[field] + 1
  Profile.dirty = true
end

Profile.load()

return Profile
