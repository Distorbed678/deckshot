-- Steam invites from inside the game, for when Steam's overlay isn't available (the game wasn't
-- started through Steam, so the overlay's invite dialog can't open). Pushed over the lobby.
local app = require "core.app"
local ui = require "core.ui"

local Invite = {}
Invite.__index = Invite

-- invited: the lobby's table of friend ids already invited (shared, so the lobby shows "Sent" too).
function Invite.open(session, invited)
  app.push(setmetatable({ session = session, invited = invited or {}, scroll = {},
    friends = session.friendsOnline(), refresh = 3 }, Invite))
end

function Invite:keypressed(key)
  if key == "escape" then app.pop() end
end

function Invite:wheelmoved(_, dy)
  ui.wheel(self.scroll, dy)
end

function Invite:update(dt)
  self.refresh = self.refresh - dt
  if self.refresh <= 0 then
    self.refresh = 3
    self.friends = self.session.friendsOnline()
  end
end

function Invite:draw()
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local w, h = 620, 560
  local x, y = (app.W - w) / 2, (app.H - h) / 2
  ui.panel(x, y, w, h, 1)
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("Invite friends", x, y + 20, w, "center")
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf("Steam's overlay isn't available because the game wasn't started from Steam, so invites are sent from here. They show up in your friends' Steam chat.",
    x + 40, y + 70, w - 80, "center")

  local listY, listH, rowH = y + 130, h - 220, 44
  local friends = self.friends
  if #friends == 0 then
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.4)
    love.graphics.printf("No friends online right now", x, listY + 40, w, "center")
  else
    local top = ui.beginScroll(self.scroll, x + 30, listY, w - 80, listH, #friends * rowH)
    for i, f in ipairs(friends) do
      local fy = top + (i - 1) * rowH
      love.graphics.setColor(1, 1, 1, 0.06)
      love.graphics.rectangle("fill", x + 30, fy, w - 80, rowH - 6, 6, 6)
      love.graphics.setColor(1, 1, 1, 0.9)
      ui.printFit(f.name, app.fonts.med, x + 44, fy + 8, w - 260, "left")
      local sent = self.invited[f.id]
      if ui.button(sent and "Sent" or "Invite", x + w - 170, fy + 4, 110, rowH - 14,
          { font = app.fonts.small, disabled = sent }) then
        self.session.invite(f)
        self.invited[f.id] = true
      end
    end
    ui.endScroll(self.scroll)
  end

  if ui.button("Done", x + w / 2 - 120, y + h - 76, 240, 52, { back = true }) then app.pop() end
end

return Invite
