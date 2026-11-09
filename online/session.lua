-- Online session: the Steam lobby we're in, its members, joining by code or
-- invite, and the Steam P2P transport used by the match. online/lan.lua has the same interface
-- for LAN play; online/active.lua says which one the lobby and match screens use.
local steam = require "online.steam"

local session = {
  kind = "steam",
  lobby = nil,        -- lobby id (uint64 userdata)
  lobbyKey = nil,     -- tostring(lobby)
  isHost = false,
  hostId = nil,
  code = nil,
  rounds = 5,
  pickFrom = 3,       -- host's gameplay rules, shown in the lobby
  picks = 1,
  members = {},       -- { { id = string, raw = uint64, name = string }, ... }
  busy = false,
  status = nil,
  error = nil,
  events = {},        -- { type = "joined"|"left"|"hostLeft", id = ... }
  inbox = {},         -- received network messages { from =, data = }
  onEntered = nil,    -- set by main.lua: switch to the lobby screen
}

session.GAME_TAG = "deckshot"
session.PROTOCOL = "7"
session.MAX_PLAYERS = 4

local CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

local function S() return steam.Steam end
local function push(ev) table.insert(session.events, ev) end

local function makeCode()
  local t = {}
  for i = 1, 6 do
    local k = love.math.random(#CODE_CHARS)
    t[i] = CODE_CHARS:sub(k, k)
  end
  return table.concat(t)
end

local function joinErrorText(data)
  local Steam = S()
  local r = data and data.m_EChatRoomEnterResponse
  if r == Steam.k_EChatRoomEnterResponseFull then return "That lobby is full" end
  if r == Steam.k_EChatRoomEnterResponseDoesntExist then return "That lobby no longer exists" end
  if r == Steam.k_EChatRoomEnterResponseNotAllowed then return "You're not allowed to join that lobby" end
  return "Could not join the lobby" .. (r and (" (code " .. tostring(r) .. ")") or "")
end

---------------------------------------------------------------- callbacks
function session.init()
  if not steam.available then return end
  local Steam = S()

  Steam.Matchmaking.OnLobbyChatUpdate = function(d)
    if not session.lobby or tostring(d.m_ulSteamIDLobby) ~= session.lobbyKey then return end
    local who = tostring(d.m_ulSteamIDUserChanged)
    local entered = d.m_rgfChatMemberStateChange == Steam.k_EChatMemberStateChangeEntered
    session.refreshMembers()
    if entered then
      push({ type = "joined", id = who })
    else
      push({ type = "left", id = who })
      if who == session.hostId then push({ type = "hostLeft" }) end
    end
  end

  Steam.Matchmaking.OnLobbyDataUpdate = function(d)
    if session.lobby and tostring(d.m_ulSteamIDLobby) == session.lobbyKey then
      session.refreshData()
      session.refreshMembers()
    end
  end

  -- Accepted a Steam invite (or "Join game") while the game is running.
  Steam.Friends.OnGameLobbyJoinRequested = function(d)
    session.joinLobby(d.m_steamIDLobby)
  end

  -- Only talk to people who are in our lobby.
  Steam.NetworkingMessages.OnSteamNetworkingMessagesSessionRequest = function(d)
    local who = tostring(d.m_identityRemote:GetSteamID())
    session.refreshMembers()
    if session.isMember(who) then
      Steam.NetworkingMessages.AcceptSessionWithUser(d.m_identityRemote)
    end
  end
end

---------------------------------------------------------------- lobby state
function session.myId()
  return steam.myId()
end

function session.inLobby()
  return session.lobby ~= nil
end

function session.isMember(id)
  for _, m in ipairs(session.members) do
    if m.id == id then return true end
  end
  return false
end

function session.memberName(id)
  for _, m in ipairs(session.members) do
    if m.id == id then return m.name end
  end
  return "Player"
end

-- Members with the host first, then in Steam's join order.
function session.refreshMembers()
  if not session.lobby then return end
  local Steam = S()
  local MM = Steam.Matchmaking
  local list, host = {}, nil
  for i = 0, MM.GetNumLobbyMembers(session.lobby) - 1 do
    local raw = MM.GetLobbyMemberByIndex(session.lobby, i)
    local m = { id = tostring(raw), raw = raw, name = Steam.Friends.GetFriendPersonaName(raw) }
    local ok, c = pcall(MM.GetLobbyMemberData, session.lobby, raw, "color")
    m.color = ok and tonumber(c) or nil
    if m.id == session.hostId then host = m else list[#list + 1] = m end
  end
  if host then table.insert(list, 1, host) end
  session.members = list
end

function session.refreshData()
  local MM = S().Matchmaking
  local L = session.lobby
  session.code = MM.GetLobbyData(L, "code")
  session.hostId = MM.GetLobbyData(L, "host")
  if session.hostId == "" then session.hostId = tostring(MM.GetLobbyOwner(L)) end
  session.rounds = tonumber(MM.GetLobbyData(L, "rounds")) or session.rounds
  session.pickFrom = tonumber(MM.GetLobbyData(L, "pickfrom")) or session.pickFrom
  session.picks = tonumber(MM.GetLobbyData(L, "picks")) or session.picks
end

local function enter(lobby, isHost)
  session.lobby = lobby
  session.lobbyKey = tostring(lobby)
  session.isHost = isHost
  session.events = {}
  session.inbox = {}
  session.refreshData()
  session.refreshMembers()
  session.status = nil
  session.error = nil
  if session.onEntered then session.onEntered() end
end

---------------------------------------------------------------- actions
-- rules: { pickFrom, picksPerRound } shown to people in the lobby.
function session.host(rounds, rules)
  if not steam.available or session.busy then return end
  session.leave()
  session.busy = true
  session.error = nil
  session.status = "Creating lobby..."
  local Steam = S()
  local vis = require("core.settings").values.lobbyVisibility
  local lobbyType = vis == "friends" and Steam.k_ELobbyTypeFriendsOnly or Steam.k_ELobbyTypePublic
  Steam.Matchmaking.CreateLobby(lobbyType, session.MAX_PLAYERS, function(data, ioFail)
    session.busy = false
    if ioFail or not data or data.m_eResult ~= Steam.k_EResultOK then
      session.status = nil
      session.error = "Could not create a lobby (Steam error " .. tostring(data and data.m_eResult) .. ")"
      return
    end
    local MM = Steam.Matchmaking
    local L = data.m_ulSteamIDLobby
    MM.SetLobbyData(L, "game", session.GAME_TAG)
    MM.SetLobbyData(L, "ver", session.PROTOCOL)
    MM.SetLobbyData(L, "code", makeCode())
    MM.SetLobbyData(L, "host", steam.myId())
    MM.SetLobbyData(L, "rounds", tostring(rounds or 5))
    MM.SetLobbyData(L, "name", Steam.Friends.GetPersonaName())
    local vis = require("core.settings").values.lobbyVisibility
    MM.SetLobbyData(L, "listed", vis == "public" and "1" or "0")
    enter(L, true)
    if rules then session.publishRules(rules) end
  end)
end

-- lobby: uint64 userdata or a decimal string
function session.joinLobby(lobby)
  if not steam.available then return end
  local Steam = S()
  if type(lobby) == "string" then lobby = Steam.Extra.ParseUint64(lobby) end
  if session.lobby and tostring(lobby) == session.lobbyKey then return end
  session.leave()
  session.busy = true
  session.error = nil
  session.status = "Joining lobby..."
  Steam.Matchmaking.JoinLobby(lobby, function(data, ioFail)
    session.busy = false
    session.status = nil
    if ioFail or not data or data.m_EChatRoomEnterResponse ~= Steam.k_EChatRoomEnterResponseSuccess then
      session.error = joinErrorText(data)
      return
    end
    local MM = Steam.Matchmaking
    local L = data.m_ulSteamIDLobby
    if MM.GetLobbyData(L, "game") ~= session.GAME_TAG then
      MM.LeaveLobby(L)
      session.error = "That lobby isn't for this game"
      return
    end
    if MM.GetLobbyData(L, "ver") ~= session.PROTOCOL then
      MM.LeaveLobby(L)
      session.error = "Version mismatch: you and the host have different game versions"
      return
    end
    enter(L, false)
  end)
end

function session.joinByCode(code)
  if not steam.available or session.busy then return end
  code = (code or ""):upper():gsub("[^A-Z0-9]", "")
  if #code ~= 6 then
    session.error = "Lobby codes are 6 characters"
    return
  end
  local Steam = S()
  local MM = Steam.Matchmaking
  session.busy = true
  session.error = nil
  session.status = "Searching for lobby " .. code .. "..."
  MM.AddRequestLobbyListStringFilter("game", session.GAME_TAG, Steam.k_ELobbyComparisonEqual)
  MM.AddRequestLobbyListStringFilter("code", code, Steam.k_ELobbyComparisonEqual)
  MM.AddRequestLobbyListDistanceFilter(Steam.k_ELobbyDistanceFilterWorldwide)
  MM.RequestLobbyList(function(data, ioFail)
    session.busy = false
    session.status = nil
    if ioFail or not data or data.m_nLobbiesMatching == 0 then
      session.error = "No open lobby found with code " .. code
      return
    end
    session.joinLobby(MM.GetLobbyByIndex(0))
  end)
end

-- Your colour in the lobby (palette index), shared through Steam lobby member data.
function session.setColor(idx)
  session.myColor = idx
  if session.lobby then
    pcall(S().Matchmaking.SetLobbyMemberData, session.lobby, "color", tostring(idx))
    session.refreshMembers()
  end
end

function session.leave()
  session.streaks, session.bots = nil, nil -- win streaks and bots belong to this lobby only
  if not session.lobby then return end
  local Steam = S()
  for _, m in ipairs(session.members) do
    if m.id ~= steam.myId() then
      pcall(Steam.NetworkingMessages.CloseSessionWithUser, session.identity(m.id))
    end
  end
  Steam.Matchmaking.LeaveLobby(session.lobby)
  session.lobby, session.lobbyKey = nil, nil
  session.isHost = false
  session.hostId = nil
  session.code = nil
  session.members = {}
  session.events = {}
  session.inbox = {}
end

function session.setRounds(n)
  session.rounds = n
  if session.isHost and session.lobby then
    S().Matchmaking.SetLobbyData(session.lobby, "rounds", tostring(n))
  end
end

-- The host's card rules summary (the full rules are sent when the match starts).
function session.publishRules(rules)
  session.pickFrom, session.picks = rules.pickFrom, rules.picksPerRound
  if session.isHost and session.lobby then
    local MM = S().Matchmaking
    MM.SetLobbyData(session.lobby, "pickfrom", tostring(rules.pickFrom))
    MM.SetLobbyData(session.lobby, "picks", tostring(rules.picksPerRound))
  end
end

-- A key that stays the same for a player across reconnects (their Steam ID).
function session.playerKey(peer)
  return peer
end

-- Public lobbies for the lobby browser. callback(list) with
-- { { lobby = id, name, players, max, code } }.
function session.listLobbies(callback)
  if not steam.available or session.listing then return end
  local Steam = S()
  local MM = Steam.Matchmaking
  session.listing = true
  MM.AddRequestLobbyListStringFilter("game", session.GAME_TAG, Steam.k_ELobbyComparisonEqual)
  MM.AddRequestLobbyListStringFilter("ver", session.PROTOCOL, Steam.k_ELobbyComparisonEqual)
  MM.AddRequestLobbyListStringFilter("listed", "1", Steam.k_ELobbyComparisonEqual)
  MM.AddRequestLobbyListDistanceFilter(Steam.k_ELobbyDistanceFilterWorldwide)
  MM.RequestLobbyList(function(data, ioFail)
    session.listing = false
    local list = {}
    if not ioFail and data then
      for i = 0, (data.m_nLobbiesMatching or 0) - 1 do
        local L = MM.GetLobbyByIndex(i)
        list[#list + 1] = {
          lobby = L, name = MM.GetLobbyData(L, "name"), code = MM.GetLobbyData(L, "code"),
          players = MM.GetNumLobbyMembers(L), max = MM.GetLobbyMemberLimit(L),
        }
      end
    end
    callback(list)
  end)
end

-- Steam friends list status ("In a lobby (2/4)", "Round 3, 2-1") and "Join game".
function session.setPresence(text)
  if not steam.available then return end
  local F = S().Friends
  pcall(F.SetRichPresence, "status", text or "")
  pcall(F.SetRichPresence, "steam_display", "#Status")
  if session.lobby then
    pcall(F.SetRichPresence, "connect", "+connect_lobby " .. tostring(session.lobby))
  else
    pcall(F.SetRichPresence, "connect", "")
  end
end

-- Lobbies stay open during matches: people who join then watch until the next match.
function session.setJoinable(on)
  if session.isHost and session.lobby then
    S().Matchmaking.SetLobbyJoinable(session.lobby, on)
  end
end

function session.openInviteDialog()
  if session.lobby then S().Friends.ActivateGameOverlayInviteDialog(session.lobby) end
end

function session.friendsOnline()
  if not steam.available then return {} end
  local Steam = S()
  local F = Steam.Friends
  local flag = Steam.k_EFriendFlagImmediate
  local list = {}
  for i = 0, F.GetFriendCount(flag) - 1 do
    local id = F.GetFriendByIndex(i, flag)
    if F.GetFriendPersonaState(id) ~= Steam.k_EPersonaStateOffline then
      list[#list + 1] = { id = tostring(id), raw = id, name = F.GetFriendPersonaName(id) }
    end
  end
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  return list
end

function session.invite(friend)
  if session.lobby then S().Matchmaking.InviteUserToLobby(session.lobby, friend.raw) end
end

function session.popEvents()
  local e = session.events
  session.events = {}
  return e
end

function session.popMessages()
  local m = session.inbox
  session.inbox = {}
  return m
end

---------------------------------------------------------------- Steam transport
local identities = {}

function session.identity(peer)
  local idt = identities[peer]
  if not idt then
    local Steam = S()
    idt = Steam.newSteamNetworkingIdentity()
    idt:SetSteamID(Steam.Extra.ParseUint64(peer))
    identities[peer] = idt
  end
  return idt
end

session.transport = {}

function session.transport:send(peer, data, reliable)
  if not steam.available then return end
  local Steam = S()
  local flags = reliable and Steam.k_nSteamNetworkingSend_ReliableNoNagle
    or Steam.k_nSteamNetworkingSend_UnreliableNoNagle
  Steam.NetworkingMessages.SendMessageToUser(session.identity(peer), data, #data, flags, 0)
end

-- Messages are drained once per frame in session.update and consumed by the active screen.
function session.transport:receive()
  return session.popMessages()
end

function session.update()
  if not steam.available or not session.lobby then return end
  local NM = S().NetworkingMessages
  for _ = 1, 8 do
    local count, msgs = NM.ReceiveMessagesOnChannel(0, 64)
    if count <= 0 then break end
    for i = 1, count do
      local m = msgs[i]
      local from = tostring(m.m_identityPeer:GetSteamID())
      if session.isMember(from) then
        session.inbox[#session.inbox + 1] = { from = from, data = m.m_pData }
      end
      m:Release()
    end
  end
end

return session
