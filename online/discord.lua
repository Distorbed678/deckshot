-- Discord Rich Presence over Discord's local socket, with no library to ship. Desktop only: it
-- needs ffi, so the browser build leaves it switched off. APP_ID is the Discord application
-- (discord.com/developers); its Art Assets must include one named "logo" for the large image.
-- Every failure is silent: no Discord, no problem.
local Platform = require "core.platform"

local Discord = { APP_ID = "1569473562580881549", connected = false, retry = 0, startedAt = os.time() }

local ffi, libc, handle, isWindows

local function init()
  if ffi then return true end
  if Platform.web or not Discord.APP_ID then return false end
  local ok, mod = pcall(require, "ffi")
  if not ok then return false end
  ffi = mod
  isWindows = ffi.os == "Windows"
  if isWindows then
    ffi.cdef [[
      void* CreateFileA(const char*, unsigned long, unsigned long, void*, unsigned long, unsigned long, void*);
      int ReadFile(void*, void*, unsigned long, unsigned long*, void*);
      int WriteFile(void*, const void*, unsigned long, unsigned long*, void*);
      int CloseHandle(void*);
      int PeekNamedPipe(void*, void*, unsigned long, unsigned long*, unsigned long*, unsigned long*);
    ]]
    libc = ffi.C
  else
    ffi.cdef [[
      struct sockaddr_un_ds { unsigned short sun_family; char sun_path[108]; };
      int socket(int, int, int);
      int connect(int, const void*, unsigned int);
      long send(int, const void*, unsigned long, int);
      long recv(int, void*, unsigned long, int);
      int close(int);
    ]]
    libc = ffi.C
  end
  return true
end

local function jsonValue(v)
  local t = type(v)
  if t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
  elseif t == "number" or t == "boolean" then
    return tostring(v)
  end
  local parts = {}
  for k, val in pairs(v) do parts[#parts + 1] = '"' .. k .. '":' .. jsonValue(val) end
  return "{" .. table.concat(parts, ",") .. "}"
end
Discord.jsonValue = jsonValue

local function writeAll(data)
  if isWindows then
    local n = ffi.new("unsigned long[1]")
    return libc.WriteFile(handle, data, #data, n, nil) ~= 0
  end
  return libc.send(handle, data, #data, 0x4000) == #data -- MSG_NOSIGNAL
end

local function sendFrame(op, payload)
  local body = jsonValue(payload)
  return writeAll(love.data.pack("string", "<I4I4", op, #body) .. body)
end

local function close()
  if handle then
    if isWindows then libc.CloseHandle(handle) else libc.close(handle) end
  end
  handle, Discord.connected = nil, false
end

-- Throw away what Discord sends; only the fact it's alive matters.
local function drain()
  if isWindows then
    local avail, got = ffi.new("unsigned long[1]"), ffi.new("unsigned long[1]")
    if libc.PeekNamedPipe(handle, nil, 0, nil, avail, nil) == 0 then close() return end
    if avail[0] > 0 then
      local buf = ffi.new("char[?]", avail[0])
      libc.ReadFile(handle, buf, avail[0], got, nil)
    end
  else
    local buf = ffi.new("char[1024]")
    local n = libc.recv(handle, buf, 1024, 0x40) -- MSG_DONTWAIT
    if n == 0 then close() end
  end
end

local function connect()
  if isWindows then
    for i = 0, 9 do
      local h = libc.CreateFileA("\\\\.\\pipe\\discord-ipc-" .. i, 0xC0000000, 0, nil, 3, 0, nil)
      if tonumber(ffi.cast("intptr_t", h)) ~= -1 then
        handle = h
        return true
      end
    end
    return false
  end
  local dirs = {}
  local xdg = Discord.socketDir or os.getenv("XDG_RUNTIME_DIR")
  if xdg then
    dirs[#dirs + 1] = xdg
    dirs[#dirs + 1] = xdg .. "/app/com.discordapp.Discord"
    dirs[#dirs + 1] = xdg .. "/snap.discord"
  end
  dirs[#dirs + 1] = "/tmp"
  for _, dir in ipairs(dirs) do
    for i = 0, 9 do
      local path = dir .. "/discord-ipc-" .. i
      local fd = #path < 107 and libc.socket(1, 1, 0) or -1
      if fd >= 0 then
        local addr = ffi.new("struct sockaddr_un_ds")
        addr.sun_family = 1
        ffi.copy(addr.sun_path, path)
        if libc.connect(fd, addr, ffi.sizeof(addr)) == 0 then
          handle = fd
          return true
        end
        libc.close(fd)
      end
    end
  end
  return false
end

-- Call once a frame.
function Discord.update(dt)
  if not init() then return end
  if not handle then
    Discord.retry = Discord.retry - dt
    if Discord.retry > 0 then return end
    Discord.retry = 15
    if connect() and sendFrame(0, { v = 1, client_id = Discord.APP_ID }) then
      Discord.connected, Discord.sentText = true, nil
    else
      close()
    end
    return
  end
  drain()
end

-- What friends see: details is the first line, state the second.
function Discord.set(details, state)
  local text = details .. "|" .. (state or "")
  if not Discord.connected or text == Discord.sentText then return end
  Discord.sentText = text
  local pid = 1
  if isWindows then
    if pcall(ffi.cdef, "unsigned long GetCurrentProcessId(void);") then pid = tonumber(ffi.C.GetCurrentProcessId()) end
  elseif pcall(ffi.cdef, "int getpid(void);") then
    pid = tonumber(ffi.C.getpid())
  end
  if not sendFrame(1, { cmd = "SET_ACTIVITY", nonce = tostring(love.timer.getTime()), args = { pid = pid,
    activity = { details = details, state = state, timestamps = { start = Discord.startedAt },
      assets = { large_image = "logo", large_text = "Deckshot" } } } }) then
    close()
  end
end

return Discord
