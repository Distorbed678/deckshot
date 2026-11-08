-- Lobby and in-match chat. Clients send text to the host, which checks it, attaches the sender's
-- name and sends it to everyone. Works over Steam and LAN (anything with session.transport).
local net = require "online.net"
local utf8 = require "utf8"

local Chat = { lines = {}, MAX_LEN = 120 }

local HISTORY = 60
local WINDOW, LIMIT = 5, 3 -- at most LIMIT messages per WINDOW seconds from each player
local recent = {}

function Chat.reset()
  Chat.lines = {}
  recent = {}
end

-- Text a player sent: valid UTF-8, no control characters, trimmed, limited length.
function Chat.clean(text)
  text = tostring(text or "")
  if not utf8.len(text) then return "" end
  text = text:gsub("[%z\1-\31\127]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if utf8.len(text) > Chat.MAX_LEN then text = text:sub(1, utf8.offset(text, Chat.MAX_LEN + 1) - 1) end
  return text
end

local function add(name, color, text)
  table.insert(Chat.lines, { name = name, color = color, text = text, at = love.timer.getTime() })
  if #Chat.lines > HISTORY then table.remove(Chat.lines, 1) end
  local sfx = package.loaded["gfx.sfx"]
  if sfx and name ~= "" then sfx.ui("uiHover") end
end

local function allowed(peer)
  local now = love.timer.getTime()
  local list = recent[peer] or {}
  for i = #list, 1, -1 do
    if now - list[i] > WINDOW then table.remove(list, i) end
  end
  recent[peer] = list
  if #list >= LIMIT then return false end
  list[#list + 1] = now
  return true
end

local function broadcast(session, name, color, text)
  add(name, color, text)
  local data = net.encodeChat(name, color, text)
  for _, m in ipairs(session.members) do
    if m.id ~= session.myId() then session.transport:send(m.id, data, true) end
  end
end

local function memberOf(session, peer)
  for _, m in ipairs(session.members) do
    if m.id == peer then return m end
  end
end

-- A line from the game itself ("X joined"). Host only; it goes to everyone.
function Chat.system(session, text)
  if session.isHost then broadcast(session, "", 0, text) end
end

-- The local player sends text.
function Chat.send(session, text)
  text = Chat.clean(text)
  if text == "" then return end
  if session.isHost then
    if allowed(session.myId()) then
      local me = memberOf(session, session.myId())
      broadcast(session, me and me.name or "Host", me and me.color or 0, text)
    else
      add("", 0, "Slow down a little")
    end
  else
    session.transport:send(session.hostId, net.encodeChat("", 0, text), true)
  end
end

-- A CHAT message arrived (call for any peer's message of kind CHAT).
function Chat.handle(session, msg)
  local ok, name, color, text = pcall(net.decodeChat, msg.data)
  if not ok then return end
  if session.isHost then
    local m = memberOf(session, msg.from)
    text = Chat.clean(text)
    if m and text ~= "" and allowed(msg.from) then broadcast(session, m.name or "Player", m.color or 0, text) end
  elseif msg.from == session.hostId then
    add(name, color, text)
  end
end

function Chat.draw(x, y, w, maxLines, fadeAfter)
  local app = require "core.app"
  local World = require "game.world"
  local font = app.fonts.small
  love.graphics.setFont(font)
  local now = love.timer.getTime()
  local lh = font:getHeight()
  local drawn, cy = 0, y
  for i = #Chat.lines, 1, -1 do
    local l = Chat.lines[i]
    local a = 1
    if fadeAfter then
      a = math.max(0, math.min(1, fadeAfter + 1 - (now - l.at)))
    end
    if a <= 0 or drawn >= maxLines then break end
    local prefix = l.name ~= "" and (l.name .. ": ") or ""
    local _, wrapped = font:getWrap(prefix .. l.text, w)
    cy = cy - #wrapped * lh
    if cy < y - maxLines * lh then break end
    local nameColor = World.PALETTE[l.color] or { 0.8, 0.8, 0.85 }
    if l.name == "" then
      love.graphics.setColor(1, 0.85, 0.4, a * 0.85)
      love.graphics.printf(l.text, x, cy, w, "left")
    else
      love.graphics.printf({ { nameColor[1], nameColor[2], nameColor[3], a }, prefix, { 1, 1, 1, a * 0.95 }, l.text }, x, cy, w, "left")
    end
    drawn = drawn + #wrapped
  end
end

return Chat
