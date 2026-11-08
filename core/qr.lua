-- A small QR code encoder (byte mode, error correction level L, versions 1-5: up to 106 bytes).
-- Used to show the LAN address in the lobby so phones can scan it. Plain Lua 5.1 (web-safe).
local QR = {}

-- Per version (level L, single block): total codewords, data codewords, alignment centre (0 = none).
local VERSIONS = {
  { size = 21, data = 19, ec = 7, align = 0 },
  { size = 25, data = 34, ec = 10, align = 18 },
  { size = 29, data = 55, ec = 15, align = 22 },
  { size = 33, data = 80, ec = 20, align = 26 },
  { size = 37, data = 108, ec = 26, align = 30 },
}

-- GF(256) tables for Reed-Solomon (polynomial 0x11d).
local EXP, LOG = {}, {}
-- Lua 5.1 has no bit operators, so xor is done by hand.
local function bxor(a, b)
  local r, bitv = 0, 1
  while a > 0 or b > 0 do
    local ab, bb = a % 2, b % 2
    if ab ~= bb then r = r + bitv end
    a, b, bitv = (a - ab) / 2, (b - bb) / 2, bitv * 2
  end
  return r
end
do
  local x = 1
  for i = 0, 254 do
    EXP[i] = x
    LOG[x] = i
    x = x * 2
    if x >= 256 then x = bxor(x, 0x11d) end
  end
  for i = 255, 511 do EXP[i] = EXP[i - 255] end
end

local function gmul(a, b)
  if a == 0 or b == 0 then return 0 end
  return EXP[LOG[a] + LOG[b]]
end

local function rsGenerator(n)
  local g = { 1 }
  for i = 0, n - 1 do
    local ng = {}
    for k = 1, #g + 1 do ng[k] = 0 end
    for k = 1, #g do
      ng[k] = bxor(ng[k], g[k])
      ng[k + 1] = bxor(ng[k + 1], gmul(g[k], EXP[i]))
    end
    g = ng
  end
  return g
end

local function rsEncode(data, n)
  local gen = rsGenerator(n)
  local rem = {}
  for i = 1, n do rem[i] = 0 end
  for _, d in ipairs(data) do
    local factor = bxor(d, rem[1])
    table.remove(rem, 1)
    rem[#rem + 1] = 0
    for i = 1, n do rem[i] = bxor(rem[i], gmul(gen[i + 1], factor)) end
  end
  return rem
end

-- Returns a matrix m[row][col] = true for dark modules, and its size; nil if the text is too long.
function QR.encode(text)
  local ver, vi
  for i, v in ipairs(VERSIONS) do
    local capacity = v.data - 2 -- 4 bits mode + 8 bits length + terminator
    if #text <= capacity then ver, vi = v, i break end
  end
  if not ver then return nil end

  -- Bit stream: mode 0100 (byte), 8-bit length, data, terminator, padding.
  local bits = {}
  local function put(value, n)
    for i = n - 1, 0, -1 do bits[#bits + 1] = math.floor(value / 2 ^ i) % 2 end
  end
  put(4, 4)
  put(#text, 8)
  for i = 1, #text do put(text:byte(i), 8) end
  for _ = 1, math.min(4, ver.data * 8 - #bits) do bits[#bits + 1] = 0 end
  while #bits % 8 ~= 0 do bits[#bits + 1] = 0 end
  local data = {}
  for i = 1, #bits, 8 do
    local v = 0
    for k = 0, 7 do v = v * 2 + bits[i + k] end
    data[#data + 1] = v
  end
  local pad = { 236, 17 }
  local k = 1
  while #data < ver.data do
    data[#data + 1] = pad[k]
    k = 3 - k
  end
  local codewords = {}
  for _, d in ipairs(data) do codewords[#codewords + 1] = d end
  for _, e in ipairs(rsEncode(data, ver.ec)) do codewords[#codewords + 1] = e end

  local n = ver.size
  local m, fixed = {}, {}
  for r = 0, n - 1 do
    m[r], fixed[r] = {}, {}
    for c = 0, n - 1 do m[r][c], fixed[r][c] = false, false end
  end
  local function set(r, c, dark)
    if r >= 0 and r < n and c >= 0 and c < n then
      m[r][c] = dark
      fixed[r][c] = true
    end
  end
  -- Finder patterns with separators.
  local function finder(r0, c0)
    for dr = -1, 7 do
      for dc = -1, 7 do
        local r, c = r0 + dr, c0 + dc
        local inside = dr >= 0 and dr <= 6 and dc >= 0 and dc <= 6
        local dark = inside and (dr == 0 or dr == 6 or dc == 0 or dc == 6 or (dr >= 2 and dr <= 4 and dc >= 2 and dc <= 4))
        set(r, c, dark)
      end
    end
  end
  finder(0, 0)
  finder(0, n - 7)
  finder(n - 7, 0)
  -- Timing patterns.
  for i = 8, n - 9 do
    set(6, i, i % 2 == 0)
    set(i, 6, i % 2 == 0)
  end
  -- Alignment pattern (versions 2-5 have one).
  if ver.align > 0 then
    local a = ver.align
    for dr = -2, 2 do
      for dc = -2, 2 do
        set(a + dr, a + dc, math.max(math.abs(dr), math.abs(dc)) ~= 1)
      end
    end
  end
  -- Dark module and reserved format areas.
  set(n - 8, 8, true)
  for i = 0, 8 do
    if not fixed[8][i] then set(8, i, false) end
    if not fixed[i][8] then set(i, 8, false) end
  end
  for i = 0, 7 do
    set(8, n - 1 - i, false)
    if i < 7 then set(n - 1 - i, 8, false) end
  end
  set(n - 8, 8, true)

  -- Data placement in the zigzag, with mask 0 ((r + c) % 2 == 0).
  local bitList = {}
  for _, cw in ipairs(codewords) do
    for i = 7, 0, -1 do bitList[#bitList + 1] = math.floor(cw / 2 ^ i) % 2 end
  end
  local idx = 1
  local col = n - 1
  local upward = true
  while col > 0 do
    if col == 6 then col = col - 1 end
    for step = 0, n - 1 do
      local r = upward and (n - 1 - step) or step
      for dc = 0, 1 do
        local c = col - dc
        if not fixed[r][c] then
          local b = bitList[idx] or 0
          idx = idx + 1
          local dark = b == 1
          if (r + c) % 2 == 0 then dark = not dark end
          m[r][c] = dark
        end
      end
    end
    upward = not upward
    col = col - 2
  end

  -- Format information: level L, mask 0 -> 111011111000100 (0x77c4). Bit i = 2^i.
  local format = 0x77c4
  local function bit(i) return math.floor(format / 2 ^ i) % 2 == 1 end
  for i = 0, 5 do m[i][8] = bit(i) end
  m[7][8] = bit(6)
  m[8][8] = bit(7)
  m[8][7] = bit(8)
  for i = 9, 14 do m[8][14 - i] = bit(i) end
  for i = 0, 7 do m[8][n - 1 - i] = bit(i) end
  for i = 8, 14 do m[n - 15 + i][8] = bit(i) end
  m[n - 8][8] = true
  return m, n
end

-- Draw a QR code as a white square with dark modules, `size` px wide (including a quiet zone).
function QR.draw(m, n, x, y, size)
  local cell = size / (n + 8)
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("fill", x, y, size, size, 6, 6)
  love.graphics.setColor(0, 0, 0)
  for r = 0, n - 1 do
    for c = 0, n - 1 do
      if m[r][c] then love.graphics.rectangle("fill", x + (c + 4) * cell, y + (r + 4) * cell, cell + 0.5, cell + 0.5) end
    end
  end
end

return QR
