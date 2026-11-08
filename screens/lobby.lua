-- The lobby (Steam or LAN, whichever online/active.lua holds): members, how others can join
-- (Steam: lobby code and invites; LAN: the host's address), chat, and the host's Start button.
local app = require "core.app"
local ui = require "core.ui"
local active = require "online.active"
local Settings = require "core.settings"
local World = require "game.world"
local net = require "online.net"
local Chat = require "online.chat"
local Cosmetics = require "core.cosmetics"
local Map = require "game.map"
local Cards = require "game.cards"

local Lobby = {}
Lobby.__index = Lobby

function Lobby.new(message)
  return setmetatable({ message = message, friends = {}, friendTimer = 0, copied = 0, chatText = "" }, Lobby)
end

function Lobby:enter()
  love.mouse.setVisible(true)
  require("gfx.music").play("menu")
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
  local hat, face = Cosmetics.mine()
  session.cosmetics = session.cosmetics or {}
  session.cosmetics[session.myId()] = { hat = hat, face = face }
  if session.isHost then
    self:sendInfo()
  else
    -- Tells the host our look and asks for its settings (for the read-only view).
    session.transport:send(session.hostId, net.encodeLobbyHello(hat, face), true)
  end
end

-- Host: everything a client needs to view the host's settings and custom content.
function Lobby:sendInfo(peer)
  local session = active.get()
  if not session.isHost then return end
  local rules = Settings.cardRules(true)
  local Synergies = require "game.synergies"
  local msgs = { net.encodeMaps(Map.sessionEntries()), net.encodeCards(Cards.sessionEntries()),
    net.encodeSynergies(Synergies.sessionEntries()), net.encodeRules(rules, Cards.list, Cards.RARITIES) }
  for _, m in ipairs(session.members) do
    if m.id ~= session.myId() and (not peer or m.id == peer) then
      for _, data in ipairs(msgs) do session.transport:send(m.id, data, true) end
    end
  end
end

local function toMenu(message)
  active.get().leave()
  app.switch(require("screens.menu").new(message))
end

function Lobby:askLeave()
  local session = active.get()
  if session.isHost and #session.members > 1 then
    require("screens.confirm").ask("Close this lobby?", "You're the host, so everyone will be disconnected.",
      function() toMenu() end, { yes = "Close Lobby", danger = true })
  else
    require("screens.confirm").ask("Leave this lobby?", "", function() toMenu() end, { yes = "Leave", danger = true })
  end
end

function Lobby:keypressed(key)
  if key == "escape" then self:askLeave() end
end

-- The game mode and teams setting in force: the host's.
local function rulesInForce(session)
  if session.isHost then
    local v = Settings.values
    return { teams = v.teams, mode = v.matchMode, roundsToWin = v.roundsToWin, pickFrom = v.pickFrom, picksPerRound = v.picksPerRound }
  end
  return session.hostRules
end

-- Everyone in the lobby plus the host's bots, with final colours and teams.
function Lobby.slots(session)
  local slots = {}
  local cos = session.cosmetics or {}
  for i, m in ipairs(session.members) do
    if i > session.MAX_PLAYERS then break end
    local look = cos[m.id] or {}
    slots[i] = { peer = m.id, name = m.name, color = m.color, hat = look.hat, face = look.face }
  end
  for _, b in ipairs(session.bots or {}) do
    if #slots >= session.MAX_PLAYERS then break end
    slots[#slots + 1] = { peer = "bot" .. #slots, name = "Bot (" .. require("game.bot").NAMES[b.level] .. ")",
      bot = b.level, color = b.color }
  end
  local r = rulesInForce(session)
  if r and r.teams then
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
  session.setRounds(Settings.values.roundsToWin)
  local slots = Lobby.slots(session)
  local data = net.encodeStart(session.rounds, slots)
  for i = 2, #slots do
    if not slots[i].bot then session.transport:send(slots[i].peer, data, true) end
  end
  -- (The lobby stays joinable: people who join mid-match watch until the next one.)
  app.instant()
  app.switch(require("screens.match").newHost(slots, session.rounds, session.transport))
end

function Lobby:update(dt)
  local session = active.get()
  require("online.presence").set("In a lobby (" .. #session.members .. "/" .. session.MAX_PLAYERS .. ")")
  if session.isHost and session.autoStart then
    session.autoStart = false
    self:start()
    return
  end
  if not session.inLobby() then
    app.switch(require("screens.menu").new(session.error or "You left the lobby"))
    return
  end

  for _, ev in ipairs(session.popEvents()) do
    if ev.type == "hostLeft" and not session.isHost then
      toMenu("The host closed the lobby")
      return
    elseif ev.type == "joined" and session.isHost then
      Chat.system(session, (session.memberName and session.memberName(ev.id) or "Someone") .. " joined")
    elseif ev.type == "left" and session.isHost then
      Chat.system(session, (session.memberName and session.memberName(ev.id) or "Someone") .. " left")
    end
  end

  local msgs = session.popMessages()
  for i, msg in ipairs(msgs) do
    local kind = net.kind(msg.data)
    if kind == net.MSG.CHAT then
      Chat.handle(session, msg)
    elseif session.isHost then
      if kind == net.MSG.LOBBYHELLO then
        local ok, hat, face = pcall(net.decodeLobbyHello, msg.data)
        if ok then session.cosmetics[msg.from] = { hat = hat, face = face } end
        self:sendInfo(msg.from)
      end
    elseif msg.from == session.hostId then
      if kind == net.MSG.START then
        local winScore, slots = net.decodeStart(msg.data)
        local me = session.myId()
        local mySlot
        for k, s in ipairs(slots) do
          if s.peer == me then mySlot = k end
        end
        -- Not in the slots: the match is already running, so we watch it until the next one.
        local rest = {}
        for k = i + 1, #msgs do rest[#rest + 1] = msgs[k] end
        app.instant()
        app.switch(require("screens.match").newClient(slots, mySlot or 0, winScore, session.transport, msg.from, rest))
        return
      elseif kind == net.MSG.MAPS then
        local ok, entries = pcall(net.decodeMaps, msg.data)
        if ok then Map.setSession(entries) end
      elseif kind == net.MSG.CARDS then
        local ok, entries = pcall(net.decodeCards, msg.data)
        if ok then Cards.setSession(entries) end
      elseif kind == net.MSG.SYNERGIES then
        local ok, entries = pcall(net.decodeMaps, msg.data)
        if ok then require("game.synergies").setSession(entries) end
      elseif kind == net.MSG.RULES then
        local ok, rules = pcall(net.decodeRules, msg.data, Cards.RARITIES)
        if ok then
          Cards.applyRules(rules)
          session.hostRules = rules
        end
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

-- "King of the Hill  -  first to 5  -  pick 1 of 3 cards" (the host's rules).
function Lobby.rulesText()
  local session = active.get()
  local r = rulesInForce(session)
  if not r then return "" end
  local picks = (r.picksPerRound or 1) > 1 and (r.picksPerRound .. " picks of ") or "pick 1 of "
  return (Settings.MODE_NAMES[r.mode] or "Elimination") .. (r.teams and ", Teams" or "") .. "  -  first to " ..
    (r.roundsToWin or session.rounds) .. "  -  " .. picks .. (r.pickFrom or 3) .. " cards"
end

function Lobby:drawPlayers(session, lx, ly, lw)
  local lh = 322
  ui.panel(lx, ly, lw, lh)
  local slots = Lobby.slots(session)
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Players  " .. #slots .. " / " .. session.MAX_PLAYERS, lx + 20, ly + 10)
  local me = session.myId()
  local r = rulesInForce(session)
  local teams = r and r.teams
  local botIndex = 0
  for i = 1, session.MAX_PLAYERS do
    local sl = slots[i]
    local ry = ly + 50 + (i - 1) * 56
    love.graphics.setColor(ui.WIDGET)
    love.graphics.rectangle("fill", lx + 16, ry, lw - 32, 50, 10, 10)
    if sl then
      local c = World.PALETTE[sl.color] or World.COLORS[i]
      Cosmetics.drawPreview(lx + 46, ry + 26, 15, c, sl.hat, sl.face, { 0.5, 0 })
      love.graphics.setColor(1, 1, 1)
      ui.printFit(sl.name, app.fonts.med, lx + 78, ry + 4, lw - 280, "left")
      local st = (session.peerStreaks or {})[sl.peer] or (session.peerStreaks or {})[sl.name]
      love.graphics.setFont(app.fonts.tiny)
      love.graphics.setColor(1, 0.8, 0.35, st and 0.9 or 0.35)
      local text = st and (st.wins .. (st.wins == 1 and " win" or " wins") .. (st.streak > 1 and ("   " .. st.streak .. " in a row!") or ""))
        or "no wins yet"
      love.graphics.print(text, lx + 78, ry + 28)
      local tags = {}
      if sl.peer == session.hostId then tags[#tags + 1] = "HOST" end
      if sl.peer == me then tags[#tags + 1] = "YOU" end
      if sl.team then tags[#tags + 1] = World.TEAM_NAMES[sl.team]:upper() end
      love.graphics.setColor(c)
      ui.printFit(table.concat(tags, "  "), app.fonts.small, lx + lw - 210, ry + 16, sl.bot and 140 or 176, "right")
      if sl.bot then
        botIndex = botIndex + 1
        local bi = botIndex
        if session.isHost and ui.button("x", lx + lw - 58, ry + 10, 34, 30, { font = app.fonts.small, back = true }) then
          table.remove(session.bots, bi)
        end
      end
    else
      love.graphics.setFont(app.fonts.med)
      love.graphics.setColor(1, 1, 1, 0.3)
      love.graphics.print("Waiting for player...", lx + 78, ry + 14)
    end
  end
  return ly + lh, teams, me
end

function Lobby:drawColors(session, lx, y, teams, me)
  if not session.setColor or teams then return end
  -- The colours everyone actually ends up with.
  local taken, myColor = {}, nil
  for _, s in ipairs(Lobby.slots(session)) do
    if s.peer == me then myColor = s.color elseif s.color then taken[s.color] = true end
  end
  local mx, my = app.mouse()
  for k, col in ipairs(World.PALETTE) do
    local x = lx + 4 + (k - 1) * 46
    local over = mx >= x and mx <= x + 38 and my >= y and my <= y + 32
    love.graphics.setColor(col[1], col[2], col[3], taken[k] and 0.2 or 1)
    love.graphics.rectangle("fill", x, y, 38, 32, 6, 6)
    if k == myColor or (over and not taken[k]) then
      love.graphics.setColor(1, 1, 1)
      love.graphics.setLineWidth(3)
      love.graphics.rectangle("line", x - 2, y - 2, 42, 36, 7, 7)
    end
    if ui.click and over and not taken[k] then
      session.setColor(k)
      Settings.values.playerColor = k
      Settings.save()
      ui.click = nil
    end
  end
end

function Lobby:drawChat(session, x, y, w, h)
  ui.panel(x, y, w, h)
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.7)
  love.graphics.print("Chat", x + 16, y + 8)
  local lineH = app.fonts.small:getHeight()
  local rows = math.floor((h - 90) / lineH)
  Chat.draw(x + 16, y + h - 50, w - 32, rows)
  local text, submitted = ui.textField(self.chatText, x + 12, y + h - 44, w - 110, 34,
    { font = app.fonts.small, maxLength = 240, align = "left", placeholder = "Say something" })
  self.chatText = text
  if ui.button("Send", x + w - 90, y + h - 44, 78, 34, { font = app.fonts.small }) or submitted then
    Chat.send(session, self.chatText)
    self.chatText = ""
  end
end

function Lobby:draw()
  local session = active.get()
  app.centered(session.kind == "lan" and "LAN LOBBY" or "LOBBY", app.fonts.big, 18)

  local lx, ly, lw = 50, 72, 570
  local bottom, teams, me = self:drawPlayers(session, lx, ly, lw)
  self:drawColors(session, lx, bottom + 12, teams, me)

  local rx, ry, rw, rh = 660, 72, 570, 268
  ui.panel(rx, ry, rw, rh)
  if session.kind == "lan" then
    self:drawLanInfo(session, rx, ry, rw, rh)
  else
    self:drawSteamInfo(session, rx, ry, rw, rh)
  end
  self:drawChat(session, rx, ry + rh + 10, rw, 252)
  self:drawControls(session)
end

-- How to join a LAN game: the host's address (desktop) and browser link.
function Lobby:drawLanInfo(session, rx, ry, rw, rh)
  local function copyButton(label, key, text, x, y, w)
    if ui.button(self.copied > 0 and self.copiedKey == key and "Copied!" or label, x, y, w, 34, { font = app.fonts.small }) then
      love.system.setClipboardText(text)
      self.copied, self.copiedKey = 1.5, key
    end
  end
  local tw = session.isHost and rw - 196 or rw - 40
  local tx = rx + 20
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf(session.isHost and "Your address on this network" or "Connected to the host at", tx, ry + 12, tw, "center")
  love.graphics.setColor(ui.GOLD)
  ui.printFit(session.code or "?", app.fonts.big, tx, ry + 32, tw, "center")
  if not session.isHost then return end

  copyButton("Copy Address", "addr", session.code or "", tx + 40, ry + 86, tw - 80)
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf("Phones, tablets and browsers: scan the code or open", tx, ry + 132, tw, "center")
  if session.webDir() then
    love.graphics.setColor(0.55, 0.85, 1)
    ui.printFit(session.url or "", app.fonts.title, tx, ry + 154, tw, "center")
    copyButton("Copy Browser Link", "url", session.url or "", tx + 40, ry + 196, tw - 80)
    if self.qrUrl ~= session.url then
      self.qrUrl = session.url
      self.qrM, self.qrN = require("core.qr").encode(session.url or "")
    end
    if self.qrM then require("core.qr").draw(self.qrM, self.qrN, rx + rw - 172, ry + 44, 156) end
  else
    love.graphics.setColor(ui.BAD)
    love.graphics.printf("The browser version's files weren't found.", tx, ry + 160, rw - 40, "center")
  end
  local others = {}
  for i, ip in ipairs(session.ipList or {}) do
    if i > 1 then others[#others + 1] = ip end
  end
  if #others > 0 then
    love.graphics.setColor(1, 1, 1, 0.35)
    ui.printFit("Other addresses of this computer: " .. table.concat(others, ", "), app.fonts.tiny, tx, ry + rh - 24, rw - 40, "center")
  end
end

-- Steam: lobby code, invite dialog and friends.
function Lobby:drawSteamInfo(session, rx, ry, rw, rh)
  local cw = 250
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf("Lobby code", rx + 16, ry + 12, cw, "center")
  love.graphics.setColor(ui.GOLD)
  ui.printFit(session.code or "------", app.fonts.big, rx + 16, ry + 34, cw, "center")
  if ui.button(self.copied > 0 and "Copied!" or "Copy Code", rx + 16, ry + 92, cw, 42) then
    love.system.setClipboardText(session.code or "")
    self.copied = 1.5
  end
  if ui.button("Steam Invite...", rx + 16, ry + 144, cw, 42) then session.openInviteDialog() end

  local fx0 = rx + cw + 40
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.print("Friends online", fx0, ry + 12)
  if #self.friends == 0 then
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.print("No friends online right now", fx0, ry + 44)
  end
  local fw = rw - cw - 56
  for i = 1, math.min(#self.friends, 6) do
    local f = self.friends[i]
    local fy = ry + 40 + (i - 1) * 36
    love.graphics.setColor(1, 1, 1, 0.85)
    ui.printFit(f.name, app.fonts.med, fx0, fy + 4, fw - 106, "left")
    local sent = self.invited[f.id]
    if ui.button(sent and "Sent" or "Invite", fx0 + fw - 96, fy, 96, 30, { font = app.fonts.small, disabled = sent }) then
      session.invite(f)
      self.invited[f.id] = true
    end
  end
end

function Lobby:drawControls(session)
  local by = 440
  if session.isHost then
    -- Bots fill empty seats (only the host's game runs them).
    session.bots = session.bots or {}
    local full = #session.members + #session.bots >= session.MAX_PLAYERS
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.print("Add a bot", 54, by + 12)
    for k, name in ipairs(require("game.bot").NAMES) do
      if ui.button("+ " .. name, 136 + (k - 1) * 162, by, 156, 42, { font = app.fonts.small, disabled = full }) then
        local used = {}
        for _, m in ipairs(session.members) do if m.color then used[m.color] = true end end
        for _, bb in ipairs(session.bots) do used[bb.color] = true end
        local col = 1
        for c = 1, #World.PALETTE do if not used[c] then col = c break end end
        table.insert(session.bots, { level = k, color = col })
      end
    end
  end

  love.graphics.setColor(1, 1, 1, 0.75)
  ui.printFit(Lobby.rulesText(), app.fonts.med, 50, by + 54, 570, "center")
  if not session.isHost then
    love.graphics.setColor(1, 1, 1, 0.5)
    ui.printFit("Waiting for the host to start...", app.fonts.small, 50, by + 80, 570, "center")
  end

  local y = 620
  if session.isHost then
    local enough = #session.members + #session.bots >= 2
    if ui.button(enough and "Start Match" or "Need 2+ players", 50, y, 370, 54, { disabled = not enough, color = ui.GOOD }) then
      self:start()
    end
  end
  if ui.button("Settings", 440, y, 390, 54) then app.push(require("screens.settings").new(4)) end
  if ui.button("Leave Lobby", 850, y, 380, 54, { back = true }) then self:askLeave() end
  if self.message then app.centered(self.message, app.fonts.med, 684, ui.BAD) end
end

return Lobby
