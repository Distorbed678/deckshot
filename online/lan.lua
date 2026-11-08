-- LAN session: the same interface as online/session.lua (Steam), over the local network.
--
-- The host runs one TCP server (port 27960, or the next free one) and tells connections apart
-- by their first bytes:
--   "RCL1"                      a desktop player; then [u32 length][message] frames both ways.
--   GET /lan (WebSocket)        a browser player; one binary WebSocket message per game message.
--   any other HTTP GET          a browser loading the game: the host serves the browser build
--                               (dist/web from source, web/ next to the executable when packaged),
--                               so http://<host>:27960/ runs the game in a page that can connect
--                               back with ws:// (a page from https:// can't open ws:// to a LAN IP).
-- Joiners find games by broadcasting "RCLQ" to UDP port 27961; hosts answer with their details.
-- Desktop uses luasocket; the browser connects through online/webbridge.lua. Clients only talk to
-- the host, like the Steam version.
local platform = require "core.platform"
local session = require "online.session" -- PROTOCOL, GAME_TAG, MAX_PLAYERS
local bit = require "core.bit"

local pack, unpack = love.data.pack, love.data.unpack

local socket
if not platform.web then
  local ok, s = pcall(require, "socket")
  if ok then socket = s end
end

local lan = {
  kind = "lan",
  active = false,     -- in a lobby (hosting, or joined and welcomed)
  isHost = false,
  hostId = "host",
  me = nil,           -- our peer id ("host" or "lan<n>")
  code = nil,         -- "ip" or "ip:port" shown in the lobby
  rounds = 5,
  pickFrom = 3,
  picks = 1,
  members = {},       -- { { id = string, name = string }, ... }, host first
  busy = false,
  status = nil,
  error = nil,
  events = {},
  inbox = {},
  onEntered = nil,    -- set by main.lua: switch to the lobby screen
  available = socket ~= nil or platform.web,
}

lan.MAX_PLAYERS = session.MAX_PLAYERS
lan.PORT = 27960
lan.DISCOVERY_PORT = 27961

local MAX_MESSAGE = 1024 * 1024
local UNRELIABLE_BACKLOG = 128 * 1024 -- skip unreliable messages to a connection this far behind
local TIMEOUT = 10
local PING_INTERVAL = 1
local CONNECT_TIMEOUT = 6
local WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

-- LAN control messages. Game messages (online/net.lua) are below 200 and pass straight through.
local CTL = { HELLO = 200, WELCOME = 201, REJECT = 202, MEMBERS = 203, PING = 204, COLOR = 205 }
lan.CTL = CTL

local function now() return love.timer.getTime() end
local function push(ev) lan.events[#lan.events + 1] = ev end

function lan.cleanName(name)
  name = tostring(name or ""):gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then name = "Player" end
  return name:sub(1, 24)
end

local function myName()
  return lan.cleanName(require("core.settings").values.playerName)
end

---------------------------------------------------------------- connections (desktop sockets)
local Conn = {}
Conn.__index = Conn

local function newConn(sock, mode)
  sock:settimeout(0)
  pcall(sock.setoption, sock, "tcp-nodelay", true)
  local t = now()
  return setmetatable({ sock = sock, mode = mode, inbuf = "", out = "", outPos = 1, queued = {}, queuedBytes = 0,
    heard = t, sent = t }, Conn)
end

function Conn:backlog()
  return #self.out - self.outPos + 1 + self.queuedBytes
end

function Conn:write(bytes)
  self.queued[#self.queued + 1] = bytes
  self.queuedBytes = self.queuedBytes + #bytes
end

function Conn:flush()
  if self.closed or self.connecting then return end
  if #self.queued > 0 then
    self.out = self.out:sub(self.outPos) .. table.concat(self.queued)
    self.outPos, self.queued, self.queuedBytes = 1, {}, 0
  end
  while self.outPos <= #self.out do
    local last, err, partial = self.sock:send(self.out, self.outPos)
    local n = last or partial
    if n and n >= self.outPos then self.outPos = n + 1 end
    if not last then
      if err == "closed" then self.closed = true end
      break -- "timeout": the socket buffer is full; the rest goes next frame
    end
  end
  if self.outPos > #self.out then self.out, self.outPos = "", 1 end
end

function Conn:read()
  if self.closed or self.connecting then return end
  local chunks = {}
  for _ = 1, 64 do
    local data, err, partial = self.sock:receive(65536)
    local got = data or partial
    if got and #got > 0 then chunks[#chunks + 1] = got end
    if not data then
      if err == "closed" then self.closed = true end
      break
    end
  end
  if #chunks > 0 then
    self.inbuf = self.inbuf .. table.concat(chunks)
    self.heard = now()
  end
end

local function wsFrame(data, op)
  local n = #data
  local b1 = 128 + (op or 2)
  local head
  if n < 126 then
    head = string.char(b1, n)
  elseif n < 65536 then
    head = string.char(b1, 126, math.floor(n / 256), n % 256)
  else
    head = string.char(b1, 127, 0, 0, 0, 0, math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
      math.floor(n / 256) % 256, n % 256)
  end
  return head .. data
end

function Conn:sendMsg(data, reliable)
  if self.closed then return end
  if not reliable and self:backlog() > UNRELIABLE_BACKLOG then return end
  if self.mode == "ws" then
    self:write(wsFrame(data, 2))
  else
    self:write(pack("string", "<I4", #data) .. data)
  end
  self.sent = now()
  self:flush()
end

local function unmask(s, m)
  local t = {}
  for i = 1, #s do t[i] = string.char(bit.bxor(s:byte(i), m[(i - 1) % 4 + 1])) end
  return table.concat(t)
end

-- Browser clients' WebSocket frames (always masked; may be fragmented).
function Conn:wsMessages(list)
  local buf, pos = self.inbuf, 1
  while true do
    local avail = #buf - pos + 1
    if avail < 2 then break end
    local b1, b2 = buf:byte(pos, pos + 1)
    local fin, op = b1 >= 128, b1 % 16
    local len, hl = b2 % 128, 2
    if len == 126 then
      if avail < 4 then break end
      len, hl = buf:byte(pos + 2) * 256 + buf:byte(pos + 3), 4
    elseif len == 127 then
      if avail < 10 then break end
      len, hl = 0, 10
      for i = pos + 2, pos + 9 do len = len * 256 + buf:byte(i) end
    end
    local ml = b2 >= 128 and 4 or 0
    if len > MAX_MESSAGE then self.closed = true break end
    if avail < hl + ml + len then break end
    local payload = buf:sub(pos + hl + ml, pos + hl + ml + len - 1)
    if ml > 0 then payload = unmask(payload, { buf:byte(pos + hl, pos + hl + 3) }) end
    pos = pos + hl + ml + len
    if op == 8 then
      self:write(wsFrame("", 8))
      self.closeWhenSent = true
      break
    elseif op == 9 then
      self:write(wsFrame(payload, 10))
    elseif op <= 2 then
      self.fragment = (self.fragment or "") .. payload
      if fin then
        list[#list + 1] = self.fragment
        self.fragment = nil
      end
    end
  end
  if pos > 1 then self.inbuf = buf:sub(pos) end
end

-- Complete messages received so far.
function Conn:messages()
  local list = {}
  if self.mode == "ws" then
    self:wsMessages(list)
  elseif self.mode == "raw" then
    local buf, pos = self.inbuf, 1
    while #buf - pos + 1 >= 4 do
      local len = unpack("<I4", buf, pos)
      if len > MAX_MESSAGE then self.closed = true break end
      if #buf - pos + 1 < 4 + len then break end
      list[#list + 1] = buf:sub(pos + 4, pos + 3 + len)
      pos = pos + 4 + len
    end
    if pos > 1 then self.inbuf = buf:sub(pos) end
  end
  return list
end

-- Client side: true once connected, false while connecting, nil + reason on failure.
function Conn:checkConnected()
  if not self.connecting then return true end
  local _, writable = socket.select(nil, { self.sock }, 0)
  if writable and #writable > 0 then
    if self.sock:getpeername() then
      self.connecting = false
      self:write("RCL1")
      return true
    end
    return nil, "Connection refused"
  end
  return false
end

function Conn:close()
  self.closed = true
  pcall(self.sock.close, self.sock)
end

---------------------------------------------------------------- serving the browser build
local CONTENT_TYPES = {
  html = "text/html; charset=utf-8", js = "application/javascript", wasm = "application/wasm",
  css = "text/css", png = "image/png", ico = "image/x-icon",
}
local fileCache = {}

-- Folder with the browser build, or nil.
function lan.webDir()
  if lan.webDirCache ~= nil then return lan.webDirCache or nil end
  local src = love.filesystem.getSource()
  local dir
  if love.filesystem.isFused() or src:match("%.love$") then
    dir = love.filesystem.getSourceBaseDirectory() .. "/web"
  else
    dir = src .. "/dist/web"
  end
  local f = io.open(dir .. "/index.html", "rb")
  if f then f:close() end
  lan.webDirCache = f and dir or false
  return f and dir or nil
end

local function readFile(path)
  if fileCache[path] == nil then
    local f = io.open(path, "rb")
    fileCache[path] = f and f:read("*a") or false
    if f then f:close() end
  end
  return fileCache[path] or nil
end

local function serveFile(c, method, path)
  c.mode = "http"
  c.closeWhenSent = true
  local name = path:match("^/([^?#]*)") or ""
  if name == "" then name = "index.html" end
  if name == "favicon.ico" then
    c:write("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n")
    return
  end
  local dir = lan.webDir()
  local body, status = nil, "200 OK"
  if (method == "GET" or method == "HEAD") and dir and name:match("^[%w_%-][%w_%.%-]*$") then
    body = readFile(dir .. "/" .. name)
  end
  local ctype = CONTENT_TYPES[name:match("%.(%w+)$") or ""] or "application/octet-stream"
  if not body then
    status, ctype = "404 Not Found", "text/plain; charset=utf-8"
    body = dir and "Not found" or
      "This Deckshot host doesn't have the browser version (the web folder next to the game). " ..
      "Desktop players can still join from Online Play > LAN."
  end
  c:write("HTTP/1.1 " .. status .. "\r\nContent-Type: " .. ctype .. "\r\nContent-Length: " .. #body ..
    "\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n")
  if method ~= "HEAD" then c:write(body) end
end

-- A new connection on the host: work out what it is from its first bytes.
local function handshake(c)
  if #c.inbuf < 4 then return end
  if c.inbuf:sub(1, 4) == "RCL1" then
    c.mode = "raw"
    c.inbuf = c.inbuf:sub(5)
    return
  end
  local stop = c.inbuf:find("\r\n\r\n", 1, true)
  if not stop then
    if #c.inbuf > 16384 then c.closed = true end
    return
  end
  local request = c.inbuf:sub(1, stop + 1)
  c.inbuf = c.inbuf:sub(stop + 4)
  local method, path = request:match("^(%u+) (%S+) HTTP/1%.%d")
  if not method then
    c.closed = true
    return
  end
  local headers = {}
  for k, v in request:gmatch("\r\n([^:\r\n]+):[ \t]*([^\r\n]*)") do headers[k:lower()] = v end
  local key = headers["sec-websocket-key"]
  if path == "/lan" and key and (headers.upgrade or ""):lower() == "websocket" then
    local accept = love.data.encode("string", "base64", love.data.hash("sha1", key .. WS_GUID))
    c:write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" ..
      "Sec-WebSocket-Accept: " .. accept .. "\r\n\r\n")
    c.mode = "ws"
  else
    serveFile(c, method, path)
  end
end

---------------------------------------------------------------- addresses
-- This machine's LAN address (the one with the default route), plus any others.
function lan.addresses()
  if not socket then return {} end
  local list, seen = {}, {}
  local function add(ip)
    if ip and not seen[ip] and ip ~= "0.0.0.0" and not ip:match("^127%.") and ip:match("^%d+%.%d+%.%d+%.%d+$") then
      seen[ip] = true
      list[#list + 1] = ip
    end
  end
  pcall(function()
    local u = socket.udp()
    u:setpeername("8.8.8.8", 53) -- no packet is sent; this just picks the outgoing interface
    add((u:getsockname()))
    u:close()
  end)
  pcall(function()
    local _, info = socket.dns.toip(socket.dns.gethostname())
    for _, ip in ipairs(info and info.ip or {}) do add(ip) end
  end)
  return list
end

---------------------------------------------------------------- messages
local function membersMsg()
  local parts = { pack("string", "<BBBBB", CTL.MEMBERS, lan.rounds, lan.pickFrom, lan.picks, #lan.members) }
  for _, m in ipairs(lan.members) do parts[#parts + 1] = pack("string", "<s1s1B", m.id, m.name, m.color or 0) end
  return table.concat(parts)
end

local function broadcastMembers()
  if not lan.isHost then return end
  local data = membersMsg()
  for _, c in pairs(lan.byPeer) do c:sendMsg(data, true) end
end

local function dropPeer(peer)
  lan.byPeer[peer] = nil
  for i, m in ipairs(lan.members) do
    if m.id == peer then table.remove(lan.members, i) break end
  end
  push({ type = "left", id = peer })
  broadcastMembers()
end

local function hostMessage(c, data)
  local kind = data:byte(1)
  if kind == CTL.HELLO then
    if c.peer then return end
    local ok, _, ver, name = pcall(unpack, "<Bs1s1", data)
    if not ok then
      c.closed = true
      return
    end
    local reason
    if ver ~= session.PROTOCOL then
      reason = "Version mismatch: you and the host have different game versions"
    elseif not lan.joinable then
      reason = "A match is running. Try again when the host is back in the lobby"
    elseif #lan.members >= session.MAX_PLAYERS then
      reason = "That game is full"
    end
    if reason then
      c:sendMsg(pack("string", "<Bs2", CTL.REJECT, reason), true)
      c.closeWhenSent = true
      return
    end
    lan.nextPeer = lan.nextPeer + 1
    c.peer = "lan" .. lan.nextPeer
    lan.byPeer[c.peer] = c
    lan.members[#lan.members + 1] = { id = c.peer, name = lan.cleanName(name) }
    c:sendMsg(pack("string", "<Bs1", CTL.WELCOME, c.peer), true)
    push({ type = "joined", id = c.peer })
    broadcastMembers()
  elseif kind == CTL.COLOR and c.peer then
    local color = data:byte(2) or 0
    for _, m in ipairs(lan.members) do
      if m.id == c.peer then m.color = color > 0 and color or nil end
    end
    broadcastMembers()
  elseif kind and kind < 200 and c.peer then
    lan.inbox[#lan.inbox + 1] = { from = c.peer, data = data }
  end
end

local function respondDiscovery()
  local u = lan.udp
  if not u then return end
  for _ = 1, 16 do
    local data, ip, port = u:receivefrom()
    if not data then break end
    if data == "RCLQ" then
      local reply = table.concat({ "RCLR", session.GAME_TAG, session.PROTOCOL, lan.token, myName(),
        #lan.members, session.MAX_PLAYERS, lan.port, lan.joinable and 1 or 0 }, "\t")
      pcall(u.sendto, u, reply, ip, port)
    end
  end
end

local function hostUpdate()
  for _ = 1, 16 do
    local s = lan.server:accept()
    if not s then break end
    lan.conns[#lan.conns + 1] = newConn(s)
  end
  local t = now()
  for i = #lan.conns, 1, -1 do
    local c = lan.conns[i]
    c:read()
    if not c.mode then handshake(c) end
    if c.mode == "raw" or c.mode == "ws" then
      for _, data in ipairs(c:messages()) do hostMessage(c, data) end
      if c.peer and t - c.sent > PING_INTERVAL then c:sendMsg(string.char(CTL.PING), true) end
    end
    if t - c.heard > (c.mode == "http" and 60 or TIMEOUT) then c.closed = true end
    c:flush()
    if c.closeWhenSent and c:backlog() == 0 then c.closed = true end
    if c.closed then
      c:close()
      table.remove(lan.conns, i)
      if c.peer and lan.byPeer[c.peer] == c then dropPeer(c.peer) end
    end
  end
  respondDiscovery()
end

---------------------------------------------------------------- client
local function fail(reason)
  if lan.conn then lan.conn:close() end
  lan.conn = nil
  lan.busy, lan.status = false, nil
  lan.error = reason
end

local function clientMessage(data)
  local kind = data:byte(1)
  if kind == CTL.WELCOME then
    local _, id = unpack("<Bs1", data)
    lan.me = id
    lan.active, lan.isHost = true, false
    lan.busy, lan.status, lan.error = false, nil, nil
    lan.events, lan.inbox = {}, {}
    if lan.onEntered then lan.onEntered() end
  elseif kind == CTL.REJECT then
    local _, reason = unpack("<Bs2", data)
    fail(reason)
  elseif kind == CTL.MEMBERS then
    local _, rounds, pickFrom, picks, n, pos = unpack("<BBBBB", data)
    lan.rounds, lan.pickFrom, lan.picks = rounds, pickFrom, picks
    local list = {}
    for i = 1, n do
      local id, name
      local color
      id, name, color, pos = unpack("<s1s1B", data, pos)
      list[i] = { id = id, name = name, color = color > 0 and color or nil }
    end
    lan.members = list
  elseif kind and kind < 200 and lan.active then
    lan.inbox[#lan.inbox + 1] = { from = lan.hostId, data = data }
  end
end

local function clientUpdate()
  local c = lan.conn
  local t = now()
  if not lan.helloSent then
    local ok, err = c:checkConnected()
    if ok then
      lan.helloSent = true
      c:sendMsg(pack("string", "<Bs1s1", CTL.HELLO, session.PROTOCOL, myName()), true)
      c.heard = t
      lan.deadline = t + CONNECT_TIMEOUT
    elseif ok == nil then
      return fail("Couldn't connect to " .. lan.target .. " (" .. tostring(err) .. ")")
    elseif t > lan.deadline then
      return fail("Couldn't reach " .. lan.target .. ". Check the address, and that the host's firewall allows the game")
    end
    if not lan.helloSent then return end
  end

  c:read()
  for _, data in ipairs(c:messages()) do
    clientMessage(data)
    if not lan.conn then return end -- rejected
  end
  if not lan.active and t > lan.deadline then
    return fail("The host at " .. lan.target .. " didn't answer")
  end
  if lan.active and not c.web and t - c.sent > PING_INTERVAL then c:sendMsg(string.char(CTL.PING), true) end
  if c.closed or t - c.heard > TIMEOUT then
    if lan.active then
      c:close()
      lan.conn = nil
      lan.error = "Lost the connection to the host"
      push({ type = "hostLeft" })
    else
      fail(c.web and c.detail or ("The host at " .. lan.target .. " closed the connection"))
    end
    return
  end
  c:flush()
end

---------------------------------------------------------------- session interface
function lan.inLobby()
  return lan.active
end

function lan.myId()
  return lan.me
end

function lan.isMember(id)
  for _, m in ipairs(lan.members) do
    if m.id == id then return true end
  end
  return false
end

function lan.memberName(id)
  for _, m in ipairs(lan.members) do
    if m.id == id then return m.name end
  end
  return "Player"
end

-- rules: { pickFrom, picksPerRound }, shown to people in the lobby.
function lan.host(rounds, rules)
  if not socket or lan.busy then return end
  lan.leave()
  lan.error = nil
  local server, port
  for p = lan.PORT, lan.PORT + 9 do
    server = socket.bind("0.0.0.0", p)
    if server then
      port = p
      break
    end
  end
  if not server then
    lan.error = "Couldn't open a network port (" .. lan.PORT .. "-" .. (lan.PORT + 9) .. ")"
    return
  end
  server:settimeout(0)
  lan.server, lan.port = server, port

  local udp = socket.udp()
  if udp and udp:setsockname("0.0.0.0", lan.DISCOVERY_PORT) then
    udp:settimeout(0)
    lan.udp = udp
  elseif udp then
    udp:close() -- another host on this machine has the discovery port; joiners can still type the address
  end

  lan.webDirCache = nil
  lan.conns, lan.byPeer, lan.nextPeer = {}, {}, 0
  lan.token = tostring(love.math.random(1, 2 ^ 30))
  lan.active, lan.isHost, lan.me, lan.joinable = true, true, lan.hostId, true
  lan.members = { { id = lan.hostId, name = myName(), color = lan.myColor } }
  lan.events, lan.inbox = {}, {}
  lan.rounds = rounds or 5
  lan.ipList = lan.addresses()
  local ip = lan.ipList[1] or "127.0.0.1"
  lan.code = port == lan.PORT and ip or (ip .. ":" .. port)
  lan.url = "http://" .. ip .. ":" .. port
  if rules then lan.publishRules(rules) end
  if lan.onEntered then lan.onEntered() end
end

-- address: "192.168.1.20" or "192.168.1.20:27961". Ignored in the browser, which joins the
-- host that served the page.
function lan.join(address)
  if lan.busy or not lan.available then return end
  lan.leave()
  lan.error = nil
  if platform.web then
    lan.target = "the host"
    lan.conn = require("online.webbridge").open()
  else
    address = (address or ""):gsub("%s", "")
    local host, port = address:match("^(.-):(%d+)$")
    host = host or address
    port = tonumber(port) or lan.PORT
    if host == "" then
      lan.error = "Enter the host's address"
      return
    end
    lan.target = port == lan.PORT and host or (host .. ":" .. port)
    local s = socket.tcp()
    s:settimeout(0)
    local ok, err = s:connect(host, port)
    if not ok and err ~= "timeout" then
      s:close()
      lan.error = "Couldn't connect to " .. lan.target .. " (" .. tostring(err) .. ")"
      return
    end
    lan.conn = newConn(s, "raw")
    lan.conn.connecting = not ok
    if ok then lan.conn:write("RCL1") end
  end
  lan.code = lan.target
  lan.helloSent = false
  lan.busy = true
  lan.status = "Connecting to " .. lan.target .. "..."
  lan.deadline = now() + CONNECT_TIMEOUT
end

function lan.leave()
  if lan.conn then lan.conn:close() end
  lan.conn = nil
  if lan.server then
    for _, c in ipairs(lan.conns) do
      c:flush()
      c:close()
    end
    lan.server:close()
    if lan.udp then lan.udp:close() end
  end
  lan.server, lan.udp, lan.conns, lan.byPeer = nil, nil, {}, {}
  lan.active, lan.isHost, lan.me, lan.code = false, false, nil, nil
  lan.busy, lan.status = false, nil
  lan.members, lan.events, lan.inbox = {}, {}, {}
end

function lan.setRounds(n)
  lan.rounds = n
  broadcastMembers()
end

function lan.publishRules(rules)
  lan.pickFrom, lan.picks = rules.pickFrom, rules.picksPerRound
  broadcastMembers()
end

-- New players can't join while a match is running.
-- Your colour in the lobby (palette index).
function lan.setColor(idx)
  lan.myColor = idx
  if not lan.active then return end
  if lan.isHost then
    if lan.members[1] then lan.members[1].color = idx end
    broadcastMembers()
  elseif lan.conn then
    lan.conn:sendMsg(string.char(CTL.COLOR, idx), true)
  end
end

function lan.setJoinable(on)
  lan.joinable = on
end

function lan.popEvents()
  local e = lan.events
  lan.events = {}
  return e
end

function lan.popMessages()
  local m = lan.inbox
  lan.inbox = {}
  return m
end

lan.transport = {}

function lan.transport:send(peer, data, reliable)
  if lan.isHost then
    local c = lan.byPeer and lan.byPeer[peer]
    if c then c:sendMsg(data, reliable) end
  elseif lan.conn and lan.active then
    lan.conn:sendMsg(data, reliable)
  end
end

function lan.transport:receive()
  return lan.popMessages()
end

-- Start of the frame: accept, receive, handshake.
function lan.update()
  if lan.server then
    hostUpdate()
  elseif lan.conn then
    clientUpdate()
  end
end

-- End of the frame: the browser sends what this frame queued (desktop sockets send at once).
function lan.flush()
  if lan.conn and lan.conn.web and lan.helloSent then lan.conn:flush() end
end

---------------------------------------------------------------- finding games (desktop)
-- Call every frame while the list is shown. Returns
-- { { ip, port, name, players, max, joinable, compatible, address }, ... }.
function lan.browse()
  if not socket then return {} end
  local f = lan.finder
  if not f then
    local u = socket.udp()
    if not u then return {} end
    u:settimeout(0)
    u:setsockname("0.0.0.0", 0)
    u:setoption("broadcast", true)
    f = { udp = u, games = {}, nextQuery = 0, targets = { "255.255.255.255", "127.0.0.1" } }
    for _, ip in ipairs(lan.addresses()) do
      f.targets[#f.targets + 1] = ip:gsub("%d+$", "255") -- subnet broadcast, assuming a /24 network
    end
    lan.finder = f
  end
  local t = now()
  if t >= f.nextQuery then
    f.nextQuery = t + 1
    for _, ip in ipairs(f.targets) do pcall(f.udp.sendto, f.udp, "RCLQ", ip, lan.DISCOVERY_PORT) end
  end
  for _ = 1, 32 do
    local data, ip = f.udp:receivefrom()
    if not data then break end
    local tag, ver, token, name, count, max, port, joinable =
      data:match("^RCLR\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(%d+)\t(%d+)\t(%d+)\t(%d)$")
    if tag == session.GAME_TAG then
      local old = f.games[token]
      -- A host on this machine answers on loopback too; keep its LAN address.
      if not (old and ip:match("^127%.") and not old.ip:match("^127%.")) then
        port = tonumber(port)
        f.games[token] = {
          ip = ip, port = port, name = name, players = tonumber(count), max = tonumber(max),
          joinable = joinable == "1", compatible = ver == session.PROTOCOL,
          address = port == lan.PORT and ip or (ip .. ":" .. port),
        }
      end
      f.games[token].seen = t
    end
  end
  local list = {}
  for token, g in pairs(f.games) do
    if t - g.seen > 3.5 then f.games[token] = nil else list[#list + 1] = g end
  end
  table.sort(list, function(a, b) return a.address < b.address end)
  return list
end

function lan.stopBrowsing()
  if lan.finder then lan.finder.udp:close() end
  lan.finder = nil
end

return lan
