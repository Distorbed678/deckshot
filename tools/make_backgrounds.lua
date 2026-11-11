-- Draws the sky and caverns map backgrounds (assets/art/bg_sky_*, bg_caverns_*). Run from the repo root, then tools/build_art.sh.
local seed = 12345
local function rnd(a, b) seed = (seed * 1103515245 + 12345) % 2147483648; local r = seed / 2147483648; return a + (b - a) * r end
local function f(n) return string.format("%d", math.floor(n + 0.5)) end
local head = '<svg xmlns="http://www.w3.org/2000/svg" width="800" height="450" viewBox="0 0 1600 900">'
local function write(name, body)
  local h = assert(io.open("assets/art/" .. name .. ".svg", "w")); h:write(head .. body .. "</svg>"); h:close()
end
local function clouds(n, y0, y1, op, color)
  local out = { '<g fill="' .. color .. '" fill-opacity="' .. op .. '">' }
  for _ = 1, n do
    local cx, cy, w = rnd(-50, 1650), rnd(y0, y1), rnd(120, 260)
    for k = 0, 3 do
      out[#out + 1] = '<ellipse cx="' .. f(cx + (k - 1.5) * w * 0.35) .. '" cy="' .. f(cy - (k % 2) * w * 0.12) .. '" rx="' .. f(w * 0.32) .. '" ry="' .. f(w * 0.2) .. '"/>'
    end
  end
  out[#out + 1] = "</g>"
  return table.concat(out)
end
local function islands(n, y0, y1, color, scale)
  local out = { '<g fill="' .. color .. '">' }
  for i = 1, n do
    local cx = (i - 0.5) / n * 1600 + rnd(-60, 60)
    local cy, w = rnd(y0, y1), rnd(110, 220) * scale
    local h = w * rnd(0.5, 0.9)
    out[#out + 1] = string.format('<path d="M%s %s L%s %s L%s %s L%s %s L%s %s Z"/>', f(cx - w), f(cy), f(cx + w), f(cy),
      f(cx + w * 0.45), f(cy + h * 0.55), f(cx + w * 0.1), f(cy + h), f(cx - w * 0.5), f(cy + h * 0.45))
    out[#out + 1] = '<rect x="' .. f(cx - w) .. '" y="' .. f(cy - 10 * scale) .. '" width="' .. f(w * 2) .. '" height="' .. f(12 * scale) .. '" rx="6"/>'
  end
  out[#out + 1] = "</g>"
  return table.concat(out)
end
local function spikes(n, fromTop, minH, maxH, color, op)
  local out = { '<g fill="' .. color .. '" fill-opacity="' .. op .. '">' }
  for i = 1, n do
    local cx = (i - 0.5) / n * 1640 - 20 + rnd(-25, 25)
    local w, h = rnd(30, 70), rnd(minH, maxH)
    if fromTop then
      out[#out + 1] = string.format('<path d="M%s 0 L%s 0 L%s %s Z"/>', f(cx - w), f(cx + w), f(cx + rnd(-8, 8)), f(h))
    else
      out[#out + 1] = string.format('<path d="M%s 900 L%s 900 L%s %s Z"/>', f(cx - w), f(cx + w), f(cx + rnd(-8, 8)), f(900 - h))
    end
  end
  out[#out + 1] = "</g>"
  return table.concat(out)
end
local function crystals(n, color, op)
  local out = { '<g fill="' .. color .. '" fill-opacity="' .. op .. '">' }
  for _ = 1, n do
    local cx, base = rnd(0, 1600), rnd(760, 900)
    for k = -1, 1 do
      local h, w = rnd(60, 150) * (k == 0 and 1.3 or 0.8), rnd(14, 24)
      local x = cx + k * w * 1.4
      out[#out + 1] = string.format('<path d="M%s %s L%s %s L%s %s L%s %s Z"/>', f(x - w), f(base), f(x - w * 0.6), f(base - h),
        f(x), f(base - h - w), f(x + w), f(base))
    end
  end
  out[#out + 1] = "</g>"
  return table.concat(out)
end
for v = 1, 2 do
  seed = 1000 * v + 7
  -- Sky: a bright gradient, soft clouds, floating rock.
  local grad = '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="' .. (v == 1 and "#3f7fc0" or "#4a77b8") ..
    '"/><stop offset="1" stop-color="' .. (v == 1 and "#a9d3ee" or "#c5b8e6") .. '"/></linearGradient></defs><rect width="1600" height="900" fill="url(#g)"/>'
  write("bg_sky_" .. v .. "_far", grad .. clouds(9, 120, 700, "0.35", "#ffffff") .. islands(5, 420, 640, "#5b7896", 0.7))
  write("bg_sky_" .. v .. "_near", clouds(6, 600, 860, "0.45", "#ffffff") .. islands(4, 560, 760, "#41597a", 1))
  -- Caverns: dark stone, stalactites, glowing crystals.
  local cgrad = '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0d0b13"/><stop offset="1" stop-color="' ..
    (v == 1 and "#1d1a2b" or "#16222a") .. '"/></linearGradient></defs><rect width="1600" height="900" fill="url(#g)"/>'
  write("bg_caverns_" .. v .. "_far", cgrad .. spikes(26, true, 90, 260, "#1b1826", "1") .. spikes(20, false, 120, 320, "#1e1b2b", "1")
    .. crystals(6, v == 1 and "#46d8cf" or "#b06cf0", "0.18"))
  write("bg_caverns_" .. v .. "_near", spikes(16, true, 60, 160, "#141220", "1") .. spikes(14, false, 80, 200, "#15131f", "1")
    .. crystals(5, v == 1 and "#46d8cf" or "#b06cf0", "0.35"))
end
print("ok")
