-- The lobby (Steam or LAN, whichever online/active.lua holds): members, how others can join
-- (Steam: lobby code and invites; LAN: the host's address), and the host's Start button.
local app = require "core.app"
local ui = require "core.ui"
local active = require "online.active"
local Settings = require "core.settings"
local World = require "game.world"
local net = require "online.net"

local Lobby = {}
Lobby.__index = Lobby

function Lobby.new(message)
  return setmetatable({ message = message, friends = {}, friendTimer = 0, copied = 0 }, Lobby)
end

function Lobby:enter()
  love.mouse.setVisible(true)
  -- Take your saved colour, or the first free one.
  local session = active.get()
  if session.setColor then
    local want = Settings.values.playerColor or 1
    local taken = {}
    for _, m in ipairs(session.members) do if m.id ~= session.myId() and m.color then taken[m.color] = true end end
    for k = 0, #World.PALETTE - 1 do
      local c = (want - 1 + k) % #World.PALETTE + 1
      if not taken[c] then want = c break end
    end
    session.setColor(want)
  end
  self.friends = active.get().kind == "steam" and active.get().friendsOnline() or {}
  self.invited = {}
end

local function toMenu(message)
  active.get().leave()
  app.switch(require("screens.menu").new(message))
end

function Lobby:keypressed(key)
  if key == "escape" then toMenu() end
end

-- Everyone in the lobby plus the host's bots, with final colours and teams.
function Lobby.slots(session)
  local slots = {}
  for i, m in ipairs(session.members) do
    if i > session.MAX_PLAYERS then break end
    slots[i] = { peer = m.id, name = m.name, color = m.color }
  end
  for _, b in ipairs(session.bots or {}) do
    if #slots >= session.MAX_PLAYERS then break end
    slots[#slots + 1] = { peer = "bot" .. #slots, name = "Bot (" .. require("game.bot").NAMES[b.level] .. ")",
      bot = b.level, color = b.color }
  end
  local v = Settings.values
  if v.teams then
    local teams = {}
    for i, s in ipairs(slots) do
      s.team = (i - 1) % 2 + 1
      teams[i] = s.team
    end
    for i, idx in ipairs(World.teamColorIndices(teams)) do slots[i].color = idx end
  else
    -- Fill in missing / clashing colours with free ones.
    local used = {}
    for _, s in ipairs(slots) do
      if s.color and not used[s.color] then used[s.color] = true else s.color = nil end
    end
    for _, s in ipairs(slots) do
      if not s.color then
        for k = 1, #World.PALETTE do
          if not used[k] then s.color, used[k] = k, true break end
        end
      end
    end
  end
  return slots
end

function Lobby:start()
  local session = active.get()
  local slots = Lobby.slots(session)
  local data = net.encodeStart(session.rounds, slots)
  for i = 2, #slots do
    if not slots[i].bot then session.transport:send(slots[i].peer, data, true) end
  end
  session.setJoinable(false)
  app.switch(require("screens.match").newHost(slots, session.rounds, session.transport))
end

function Lobby:update(dt)
  local session = active.get()
  if not session.inLobby() then
    app.switch(require("screens.menu").new(session.error or "You left the lobby"))
    return
  end

  for _, ev in ipairs(session.popEvents()) do
    if ev.type == "hostLeft" and not session.isHost then
      toMenu("The host closed the lobby")
      return
    end
  end

  local msgs = session.popMessages()
  for i, msg in ipairs(msgs) do
    if not session.isHost and msg.from == session.hostId and net.kind(msg.data) == net.MSG.START then
      local winScore, slots = net.decodeStart(msg.data)
      local me = session.myId()
      local mySlot
      for k, s in ipairs(slots) do
        if s.peer == me then mySlot = k end
      end
      if mySlot then
        -- Hand any messages that arrived right after START to the match.
        local rest = {}
        for k = i + 1, #msgs do rest[#rest + 1] = msgs[k] end
        app.switch(require("screens.match").newClient(slots, mySlot, winScore, session.transport, msg.from, rest))
        return
      end
    end
  end

  self.friendTimer = self.friendTimer + dt
  if session.kind == "steam" and self.friendTimer > 5 then
    self.friendTimer = 0
    self.friends = session.friendsOnline()
  end
  self.copied = math.max(0, self.copied - dt)
end

-- "First to 5  -  pick 1 of 3 cards" (the host's rules, from the lobby data).
function Lobby.rulesText()
  local session = active.get()
  local picks = session.picks > 1 and (session.picks .. " picks of ") or "pick 1 of "
  return "First to " .. session.rounds .. "  -  " .. picks .. session.pickFrom .. " cards"
end

function Lobby:draw()
  local session = active.get()
  app.centered(session.kind == "lan" and "LAN LOBBY" or "LOBBY", app.fonts.big, 28)

  -- Players (members, then the host's bots)
  local lx, ly, lw, lh = 60, 90, 560, 380
  ui.panel(lx, ly, lw, lh)
  local slots = Lobby.slots(session)
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Players  " .. #slots .. " / " .. session.MAX_PLAYERS, lx + 24, ly + 14)
  if Settings.values.teams and session.isHost then
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.printf("TEAMS", lx, ly + 22, lw - 24, "right")
  end
  local me = session.myId()
  local botIndex = 0
  for i = 1, session.MAX_PLAYERS do
    local sl = slots[i]
    local ry = ly + 56 + (i - 1) * 62
    love.graphics.setColor(0.17, 0.17, 0.22)
    love.graphics.rectangle("fill", lx + 20, ry, lw - 40, 54, 10, 10)
    if sl then
      local c = World.PALETTE[sl.color] or World.COLORS[i]
      love.graphics.setColor(c)
      love.graphics.circle("fill", lx + 52, ry + 27, 16)
      love.graphics.setColor(0.1, 0.1, 0.12)
      love.graphics.circle("fill", lx + 48, ry + 23, 2.5)
      love.graphics.circle("fill", lx + 58, ry + 23, 2.5)
      love.graphics.setFont(app.fonts.title)
      love.graphics.setColor(1, 1, 1)
      love.graphics.print(sl.name, lx + 84, ry + 12)
      local tags = {}
      if sl.peer == session.hostId then tags[#tags + 1] = "HOST" end
      if sl.peer == me then tags[#tags + 1] = "YOU" end
      if sl.team then tags[#tags + 1] = World.TEAM_NAMES[sl.team]:upper() end
      love.graphics.setFont(app.fonts.small)
      love.graphics.setColor(c)
      love.graphics.printf(table.concat(tags, "  "), lx + 20, ry + 19, lw - (sl.bot and 110 or 60), "right")
      if sl.bot then
        botIndex = botIndex + 1
        local bi = botIndex
        if session.isHost and ui.button("x", lx + lw - 76, ry + 12, 36, 30, { font = app.fonts.small, back = true }) then
          table.remove(session.bots, bi)
        end
      end
    else
      love.graphics.setFont(app.fonts.med)
      love.graphics.setColor(1, 1, 1, 0.3)
      love.graphics.print("Waiting for player...", lx + 84, ry + 17)
    end
  end
  -- Your colour
  if session.setColor and not Settings.values.teams then
    local taken = {}
    for _, m in ipairs(session.members) do if m.id ~= me and m.color then taken[m.color] = true end end
    for _, bb in ipairs(session.bots or {}) do if bb.color then taken[bb.color] = true end end
    local myColor
    for _, m in ipairs(session.members) do if m.id == me then myColor = m.color end end
    local sx = lx + 24
    for k, col in ipairs(World.PALETTE) do
      local x = sx + (k - 1) * 43
      local y = ly + lh - 44
      local mx, my = app.mouse()
      local over = mx >= x and mx <= x + 36 and my >= y and my <= y + 34
      love.graphics.setColor(col[1], col[2], col[3], taken[k] and 0.2 or 1)
      love.graphics.rectangle("fill", x, y, 36, 34, 6, 6)
      if k == myColor or (over and not taken[k]) then
        love.graphics.setColor(1, 1, 1)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", x - 2, y - 2, 40, 38, 7, 7)
      end
      if ui.click and over and not taken[k] then
        session.setColor(k)
        Settings.values.playerColor = k
        Settings.save()
        ui.click = nil
      end
    end
  end

  local rx, ry, rw, rh = 660, 90, 560, 380
  ui.panel(rx, ry, rw, rh)
  if session.kind == "lan" then
    self:drawLanInfo(session, rx, ry, rw)
  else
    self:drawSteamInfo(session, rx, ry, rw)
  end
  self:drawControls(session)
end

-- How to join a LAN game: the host's address (desktop) and browser link.
function Lobby:drawLanInfo(session, rx, ry, rw)
  local function copyButton(label, key, text, x, y, w)
    if ui.button(self.copied > 0 and self.copiedKey == key and "Copied!" or label, x, y, w, 40, { font = app.fonts.small }) then
      love.system.setClipboardText(text)
      self.copied, self.copiedKey = 1.5, key
    end
  end
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf(session.isHost and "Your address on this network" or "Connected to the host at", rx, ry + 16, rw, "center")
  love.graphics.setFont(app.fonts.big)
  love.graphics.setColor(1, 0.85, 0.4)
  love.graphics.printf(session.code or "?", rx, ry + 44, rw, "center")
  if not session.isHost then
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.printf("The host's settings (rounds, cards, maps) are used for the match.", rx + 30, ry + 110, rw - 60, "center")
    return
  end

  copyButton("Copy Address", "addr", session.code or "", rx + 150, ry + 96, rw - 300)
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.55)
  love.graphics.printf("Desktop players: Online Play > LAN, then pick this game from the list or type the address.",
    rx + 30, ry + 146, rw - 60, "center")

  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  local tw = rw - 210
  love.graphics.printf("Phones, tablets and browsers: scan the code or open", rx + 20, ry + 196, tw, "center")
  love.graphics.setFont(app.fonts.title)
  if session.webDir() then
    love.graphics.setColor(0.55, 0.85, 1)
    love.graphics.printf(session.url or "", rx + 20, ry + 246, tw, "center")
    copyButton("Copy Browser Link", "url", session.url or "", rx + 60, ry + 286, tw - 80)
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.printf("then choose Online Play > LAN > Join Game.", rx + 20, ry + 332, tw, "center")
    -- QR code of the browser link (phones on the same Wi-Fi scan it).
    if self.qrUrl ~= session.url then
      self.qrUrl = session.url
      self.qrM, self.qrN = require("core.qr").encode(session.url or "")
    end
    if self.qrM then require("core.qr").draw(self.qrM, self.qrN, rx + rw - 180, ry + 190, 160) end
  else
    love.graphics.setColor(1, 0.6, 0.45, 0.8)
    love.graphics.printf("unavailable", rx, ry + 226, rw, "center")
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.printf("The browser version's files weren't found (the web folder next to the game, or dist/web " ..
      "from ./build.sh web when running from source).", rx + 30, ry + 270, rw - 60, "center")
  end
  local others = {}
  for i, ip in ipairs(session.ipList or {}) do
    if i > 1 then others[#others + 1] = ip end
  end
  if #others > 0 then
    love.graphics.setFont(app.fonts.tiny)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.printf("Other addresses of this computer: " .. table.concat(others, ", "), rx + 20, ry + 352, rw - 40, "center")
  end
end

-- Steam: lobby code, invite dialog and friends.
function Lobby:drawSteamInfo(session, rx, ry, rw)
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf("Lobby code", rx, ry + 16, rw, "center")
  love.graphics.setFont(app.fonts.huge)
  love.graphics.setColor(1, 0.85, 0.4)
  love.graphics.printf(session.code or "------", rx, ry + 34, rw, "center")

  local bw = (rw - 60) / 2
  if ui.button(self.copied > 0 and "Copied!" or "Copy Code", rx + 20, ry + 150, bw, 46) then
    love.system.setClipboardText(session.code or "")
    self.copied = 1.5
  end
  if ui.button("Steam Invite...", rx + 40 + bw, ry + 150, bw, 46) then
    session.openInviteDialog()
  end

  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.print("Friends online", rx + 24, ry + 210)
  if #self.friends == 0 then
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.print("No friends online right now", rx + 24, ry + 240)
  end
  for i = 1, math.min(#self.friends, 4) do
    local f = self.friends[i]
    local fy = ry + 238 + (i - 1) * 34
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.print(f.name, rx + 24, fy + 4)
    local sent = self.invited[f.id]
    if ui.button(sent and "Sent" or "Invite", rx + rw - 130, fy, 106, 30, { font = app.fonts.small, disabled = sent }) then
      session.invite(f)
      self.invited[f.id] = true
    end
  end
end

function Lobby:drawControls(session)

  -- Bottom controls
  local by = 495
  if session.isHost then
    local d = ui.cycler("Rounds", tostring(session.rounds), 60, by, 270, 50)
    if d ~= 0 then
      local opts = Settings.ROUND_OPTIONS
      local idx = 1
      for k, v in ipairs(opts) do if v == session.rounds then idx = k end end
      session.setRounds(opts[(idx - 1 + d) % #opts + 1])
    end
    -- Bots fill empty seats (only the host's game runs them).
    session.bots = session.bots or {}
    local full = #session.members + #session.bots >= session.MAX_PLAYERS
    love.graphics.setFont(app.fonts.small)
    for k, name in ipairs(require("game.bot").NAMES) do
      if ui.button("+ " .. name, 340 + (k - 1) * 94, by, 90, 50, { font = app.fonts.small, disabled = full }) then
        local used = {}
        for _, m in ipairs(session.members) do if m.color then used[m.color] = true end end
        for _, bb in ipairs(session.bots) do used[bb.color] = true end
        local col = 1
        for c = 1, #World.PALETTE do if not used[c] then col = c break end end
        table.insert(session.bots, { level = k, color = col })
      end
    end
    local enough = #session.members + #session.bots >= 2
    if ui.button(enough and "Start Match" or "Need 2+ players", 660, by, 560, 50,
      { disabled = not enough, color = { 0.4, 1, 0.5 } }) then
      self:start()
    end
  else
    love.graphics.setFont(app.fonts.title)
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.printf(Lobby.rulesText() .. "  -  waiting for the host to start...", 0, by + 10, app.W, "center")
  end

  if ui.button("Leave Lobby", app.W / 2 - 310, 570, 300, 46) then toMenu() end
  if ui.button("Settings", app.W / 2 + 10, 570, 300, 46) then app.push(require("screens.settings").new()) end

  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.4)
  if session.kind == "lan" then
    love.graphics.printf("Everyone plays with the Online controls (mouse aim). Players need the same game version " ..
      "as the host. Windows may ask to let the game through its firewall: allow it on private networks.",
      100, 630, app.W - 200, "center")
  else
    love.graphics.printf("Friends can join with the code, or by accepting a Steam invite while they have the game open " ..
      "(the game runs as Spacewar, so Steam can't launch it for them).", 100, 630, app.W - 200, "center")
  end
  if self.message then
    app.centered(self.message, app.fonts.med, 672, { 1, 0.6, 0.45 })
  end
end

return Lobby
