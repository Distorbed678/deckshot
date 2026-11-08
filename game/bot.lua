-- AI players. A bot fills in its input table (core/input.lua, kind "bot") every frame like a
-- person pressing keys, so Player code treats it like anyone else and bots work online too.
-- Difficulty 1 easy, 2 normal, 3 hard.
local Map = require "game.map"
local Objects = require "game.objects"
local Cards = require "game.cards"

local Bot = {}

Bot.NAMES = { "Easy", "Normal", "Hard" }
local LEVEL = {
  { reaction = 0.45, aimError = 0.22, blockChance = 0.15, dodge = 0, melee = 0.3, heavy = false, fireHold = 0.6 },
  { reaction = 0.26, aimError = 0.1, blockChance = 0.45, dodge = 0.3, melee = 0.6, heavy = true, fireHold = 0.85 },
  { reaction = 0.14, aimError = 0.035, blockChance = 0.8, dodge = 0.7, melee = 0.9, heavy = true, fireHold = 1 },
}

local function solidAt(w, x, y, ww, hh)
  return Map.hit(w.solids, x, y, ww, hh) ~= nil
end

-- Any ground (solid or one-way) within `depth` px below (x, y)? Upward fans count: they carry you.
local function groundBelow(w, x, y, depth)
  for _, r in ipairs(w.solids) do
    if x >= r.x - 4 and x <= r.x + r.w + 4 and r.y >= y and r.y <= y + depth then return r end
  end
  for _, o in ipairs(w.objects or {}) do
    if o.alive and o.type == "fan" and (o.dir or "up") == "up" and x >= o.x and x <= o.x + o.w and o.y + o.h >= y then
      return o
    end
  end
  return nil
end

local function press(inp, field)
  inp[field] = (inp[field] or 0) + 1
end

local function hazardNear(w, x, y, radius)
  for _, o in ipairs(w.objects or {}) do
    if o.alive and Objects.HAZARD[o.type] and o.type ~= "turret" then
      local bx, by, bw, bh
      if o.w then bx, by, bw, bh = o.x, o.y, o.w, o.h else bx, by, bw, bh = o.x - (o.r or 20), o.y - (o.r or 20), (o.r or 20) * 2, (o.r or 20) * 2 end
      local cx = math.max(bx, math.min(x, bx + bw))
      local cy = math.max(by, math.min(y, by + bh))
      if (cx - x) ^ 2 + (cy - y) ^ 2 < radius * radius then return o end
    end
  end
end

-- Find a firing angle whose arc reaches (tx, ty) without hitting a wall (to shoot over cover).
local function lobAngle(w, p, tx, ty)
  local s = p.stats
  local speed, g = math.max(200, s.bulletSpeed), 1800 * s.bulletGravity
  local best, bestD
  for deg = -85, 85, 5 do
    for _, side in ipairs({ 1, -1 }) do
      local a = side > 0 and math.rad(deg) or math.pi - math.rad(deg)
      local x, y = p.x, p.y
      local vx, vy = math.cos(a) * speed, math.sin(a) * speed
      for _ = 1, 60 do
        x, y, vy = x + vx * 0.02, y + vy * 0.02, vy + g * 0.02
        if x < 0 or x > Map.W or y > Map.H or solidAt(w, x - 2, y - 2, 4, 4) then break end
        local d = (x - tx) ^ 2 + (y - ty) ^ 2
        if d < 30 * 30 and (not bestD or d < bestD) then best, bestD = a, d end
      end
    end
  end
  return best
end

---------------------------------------------------------------- platform graph
-- Surfaces are the tops of the map's rects; edges are jumps (single or double) and drops.
local JUMP_UP, DOUBLE_UP, JUMP_GAP, DROP_GAP = 160, 300, 250, 400

local function buildGraph(w)
  local surf = {}
  for _, r in ipairs(w.map.rects) do
    if r.w >= 30 then surf[#surf + 1] = { x0 = r.x, x1 = r.x + r.w, y = r.y, rect = r, edges = {} } end
  end
  for _, o in ipairs(w.objects or {}) do
    if o.solid and o.w and o.w >= 30 and (o.type == "wall" or o.type == "plank" or o.type == "conveyor" or o.type == "crumble") then
      surf[#surf + 1] = { x0 = o.x, x1 = o.x + o.w, y = o.y, rect = o, edges = {} }
    end
  end
  for _, a in ipairs(surf) do
    for _, b in ipairs(surf) do
      if a ~= b then
        local gap = math.max(0, b.x0 - a.x1, a.x0 - b.x1)
        local up = a.y - b.y
        local ok = (up > 0 and up <= DOUBLE_UP and gap <= (up <= JUMP_UP and JUMP_GAP or JUMP_GAP * 0.8))
          or (up <= 0 and gap <= DROP_GAP)
        if ok then
          -- The way between them must be open (a tall wall between two floors blocks it).
          local ax = math.max(a.x0 + 10, math.min(a.x1 - 10, (b.x0 + b.x1) / 2))
          local bx = math.max(b.x0 + 10, math.min(b.x1 - 10, ax))
          local ay, by = a.y - 26, b.y - 26
          local steps = math.max(1, math.floor(math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2) / 10))
          for k = 1, steps - 1 do
            local x, y = ax + (bx - ax) * k / steps, ay + (by - ay) * k / steps
            for _, r in ipairs(w.map.rects) do
              if not r.oneway and r ~= a.rect and r ~= b.rect and x > r.x and x < r.x + r.w and y > r.y and y < r.y + r.h then
                ok = false
              end
            end
            if not ok then break end
          end
        end
        if ok then a.edges[#a.edges + 1] = b end
      end
    end
  end
  return surf
end

local function surfaceUnder(graph, x, y)
  local best, bestY
  for _, s in ipairs(graph) do
    if x >= s.x0 - 8 and x <= s.x1 + 8 and s.y >= y - 4 and (not bestY or s.y < bestY) then best, bestY = s, s.y end
  end
  return best
end

-- First surface to head for on the shortest hop path from a to b.
local function nextSurface(a, b)
  if a == b then return nil end
  local prev, queue, head = { [a] = a }, { a }, 1
  while queue[head] do
    local s = queue[head]
    head = head + 1
    if s == b then break end
    for _, n in ipairs(s.edges) do
      if not prev[n] then
        prev[n] = s
        queue[#queue + 1] = n
      end
    end
  end
  if not prev[b] then return nil end
  local s = b
  while prev[s] ~= a do s = prev[s] end
  return s
end

-- How far from the target this bot likes to fight, from its build.
local function preferredRange(s)
  if s.meleeDamage > s.gunDamage * 1.6 then return 60 end
  if s.bullets >= 3 then return 200 end
  if s.bulletSpeed > 1500 or s.distDamage > 0 or s.laser > 0 then return 480 end
  return 320
end

function Bot.update(p, w, dt)
  local inp = p.input
  local L = LEVEL[inp.difficulty or 2] or LEVEL[2]
  local b = inp.brain
  if not b then
    b = { react = 0, noise = 0, noiseT = 0, jumpHold = 0, blockCd = 0, seen = nil, wander = Map.W / 2, holdMelee = 0 }
    inp.brain = b
  end
  inp.left, inp.right, inp.up, inp.down, inp.fire = false, false, false, false, false
  if p.dead or w.state ~= "playing" then
    inp.jumpHeld, inp.meleeHeld = false, false
    return
  end
  b.react = b.react - dt
  b.blockCd = b.blockCd - dt
  b.noiseT = b.noiseT - dt
  if b.noiseT <= 0 then
    b.noiseT = 0.3 + love.math.random() * 0.4
    b.noise = (love.math.random() * 2 - 1) * L.aimError
  end
  local s = p.stats

  -- Perception lags behind reality by the reaction time.
  local target = w:nearestEnemy(p, p.x, p.y, true)
  if target and (not b.seen or b.react <= 0 or b.seen.p ~= target) then
    b.react = L.reaction
    b.seen = { p = target, x = target.x, y = target.y, vx = target.vx or 0, vy = target.vy or 0 }
  end
  if not target then b.seen = nil end
  local t = b.seen

  -- Line of sight: without it for a while, close in (and jump for an angle); later, shoot anyway.
  local clear = t and Objects.lineClear(w, p.x, p.y, t.x, t.y)
  if t and not clear then
    b.blind = (b.blind or 0) + dt
  else
    b.blind, b.lob = 0, nil
  end

  -- Where to stand
  local goalX = b.wander
  if t then
    local range = preferredRange(s)
    if b.blind > 1 then range = math.max(40, range * math.max(0, 1 - (b.blind - 1) * 0.5)) end
    local side = (p.x < t.x) and -1 or 1
    goalX = t.x + side * range
    if goalX < 90 or goalX > Map.W - 90 then goalX = t.x - side * range end
  else
    if math.abs(p.x - b.wander) < 40 then b.wander = 200 + love.math.random() * (Map.W - 400) end
  end
  -- Stalemate: nobody's been hurt for a while, so go to them even if we can see them.
  local hpSum = p.hp + (t and t.p.hp or 0)
  if b.lastHpSum ~= hpSum then b.lastHpSum, b.calm = hpSum, 0 else b.calm = (b.calm or 0) + dt end
  local stale = b.calm > 6

  -- Can't see them (or stalemate): follow the platform graph toward their platform.
  local route
  -- King of the Hill: head for the hill first, fight on it.
  local hill = w.hill and w.state == "playing" and w.hill
  local hillFar = hill and (math.abs(p.x - hill.x) > 110 or math.abs(p.y - hill.y) > 100)
  local dest = hillFar and { x = hill.x, y = hill.y + 50 } or t
  if dest and (hillFar or b.blind > 0.8 or stale) then
    if not w.botGraph or w.botGraphMap ~= w.map then
      w.botGraph, w.botGraphMap = buildGraph(w), w.map
    end
    local g = w.botGraph
    local here = p.onGround and surfaceUnder(g, p.x, p.y + p.r + p.leg - 2) or b.lastSurface
    if p.onGround then b.lastSurface = here end
    local there = surfaceUnder(g, dest.x, dest.y + 10)
    route = here and there and nextSurface(here, there)
    if route then
      if route.y < (here and here.y or p.y) - 10 then
        -- Higher: take off from the nearest point on our surface (outside the target's span if it's solid).
        local tx = math.max(route.x0 + 20, math.min(route.x1 - 20, p.x))
        if not route.rect.oneway and p.x > route.x0 - 10 and p.x < route.x1 + 10 then
          tx = (p.x < (route.x0 + route.x1) / 2) and route.x0 - 30 or route.x1 + 30
        end
        goalX = tx
        b.climb = route
      else
        goalX = math.max(route.x0 + 20, math.min(route.x1 - 20, p.x + (route.x0 + route.x1 - 2 * p.x) * 0.5))
        b.climb = nil
      end
    end
  else
    b.climb = nil
  end
  if hillFar and not route then goalX = hill.x end
  if hill and not hillFar then goalX = math.max(hill.x - 100, math.min(hill.x + 100, goalX)) end
  goalX = math.max(70, math.min(Map.W - 70, goalX))
  local dir = 0
  if goalX > p.x + 30 then dir = 1 elseif goalX < p.x - 30 then dir = -1 end
  -- Climbing: jump when lined up, steer onto the platform, double jump near the apex.
  if b.climb then
    local c = b.climb
    if p.onGround and math.abs(p.x - goalX) < 40 then
      press(inp, "jumpCount")
      b.jumpHold = 0.4
    end
    if not p.onGround then
      local cx = (c.x0 + c.x1) / 2
      dir = (cx > p.x + 10) and 1 or (cx < p.x - 10) and -1 or 0
      if p.y + p.r + p.leg > c.y and p.vy > -120 and p.jumpsLeft > 0 then
        press(inp, "jumpCount")
        b.jumpHold = 0.3
      elseif p.y + p.r + p.leg > c.y and p.vy > 0 and p.dashesLeft > 0 and p.dashCd <= 0 then
        inp.aim = math.atan2(c.y - 30 - p.y, cx - p.x) -- dash onto it
        press(inp, "dashCount")
      end
    end
  elseif stale and route == nil and t then
    goalX = t.x -- no route found: just walk at them
  end
  -- Pressed against a wall in the air: double jump, then dash, to get over it.
  if not p.onGround and dir ~= 0 and p.wallDir == dir and p.vy > -150 then
    if p.jumpsLeft > 0 then
      press(inp, "jumpCount")
      b.jumpHold = 0.3
    elseif p.dashesLeft > 0 and p.dashCd <= 0 then
      inp.aim = -math.pi / 2 + dir * 0.4
      press(inp, "dashCount")
    end
  end

  -- Look ahead: walls, gaps, hazards
  local ahead = p.x + dir * (p.r + 24)
  local wantJump = false
  if dir ~= 0 and p.onGround then
    if solidAt(w, ahead - 4, p.y - p.r + 4, 8, p.r * 2 - 10) then wantJump = true end
    if not groundBelow(w, ahead, p.y + p.r + p.leg - 2, 160) then
      -- A gap: jump if there's somewhere to land, otherwise wait at the edge.
      local landing = false
      for dx = 100, 300, 50 do
        if groundBelow(w, p.x + dir * dx, p.y - 120, 300) then landing = true break end
      end
      if landing then wantJump = true else dir = 0 end
    end
  end
  if hazardNear(w, p.x + dir * 50, p.y, 70) then
    if p.onGround then wantJump = true else dir = -dir end
  end
  -- Edges of the arena hurt: don't walk into them.
  if (p.x < 80 and dir < 0) or (p.x > Map.W - 80 and dir > 0) then dir = 0 end

  -- Chasing someone above: jump toward platforms. Someone below on a one-way: drop through.
  if t and t.y < p.y - 110 and p.onGround and love.math.random() < dt * 3 then wantJump = true end
  if b.blind > 1.5 and p.onGround and love.math.random() < dt * 2 then wantJump = true end
  if t and t.y > p.y + 90 and p.onGround and p.groundOneway and love.math.random() < dt * 2 then
    inp.down = true
    press(inp, "jumpCount")
  end

  -- Falling with nothing below: double jump / dash back up toward the middle.
  if not p.onGround and p.vy > 150 and not groundBelow(w, p.x, p.y, 420) then
    if p.jumpsLeft > 0 and love.math.random() < dt * 8 then
      press(inp, "jumpCount")
      b.jumpHold = 0.25
    elseif p.dashesLeft > 0 and p.dashCd <= 0 and love.math.random() < dt * 6 then
      dir = p.x < Map.W / 2 and 1 or -1
      inp.up = true
      press(inp, "dashCount")
    end
    dir = p.x < Map.W / 2 and 1 or -1
  end
  if p.y > Map.H - 80 and not p.onGround then dir = p.x < Map.W / 2 and 1 or -1 end
  -- Sudden death: stay inside the barrier.
  if w.barrier then
    local margin = 110
    if p.x - w.barrier[1] < margin then dir = 1 elseif w.barrier[3] - p.x < margin then dir = -1 end
    if w.barrier[4] - p.y < margin and p.onGround then wantJump = true end
  end

  if wantJump and p.onGround then
    press(inp, "jumpCount")
    b.jumpHold = 0.3
  end
  b.jumpHold = b.jumpHold - dt
  inp.jumpHeld = b.jumpHold > 0
  inp.left, inp.right = dir < 0, dir > 0

  -- Aim with lead and drop compensation
  if t then
    local dx, dy = t.x - p.x, t.y - p.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local tt = dist / math.max(200, s.bulletSpeed)
    local ax = t.x + t.vx * tt * 0.8
    local ay = t.y + t.vy * tt * 0.5 - 0.5 * 1800 * s.bulletGravity * tt * tt
    inp.aim = math.atan2(ay - p.y, ax - p.x) + b.noise
    if not clear and b.blind > 1.5 then
      b.lobT = (b.lobT or 0) - dt
      if b.lobT <= 0 then
        b.lobT = 0.5
        b.lob = lobAngle(w, p, t.x, t.y)
      end
      if b.lob then inp.aim = b.lob + b.noise * 0.5 end
    end
    if (clear or b.lob or b.blind > 4) and p.ammo > 0 and love.math.random() < L.fireHold then inp.fire = true end

    -- Melee up close
    if dist < p.r + t.p.r + s.meleeRange * 0.9 and p.meleeCd <= 0 then
      if L.heavy and (t.p.stunTimer or 0) > 0.3 then
        inp.meleeHeld = true
        if not p.charging then press(inp, "meleeCount") end
        b.holdMelee = 0.5
      elseif love.math.random() < L.melee * dt * 6 then
        press(inp, "meleeCount")
        inp.meleeHeld = true
        b.holdMelee = 0.05
      end
    end
  end
  b.holdMelee = b.holdMelee - dt
  if b.holdMelee <= 0 then inp.meleeHeld = false end

  -- Defence: block or dash away from bullets about to hit, and from charged heavy melee.
  if b.blockCd <= 0 then
    for _, bl in ipairs(w.bullets) do
      if bl.owner ~= p and not bl.mine and not (bl.owner.team and bl.owner.team == p.team and w.rules.teams) then
        local rx, ry = p.x - bl.x, p.y - bl.y
        local vx, vy = bl.vx, bl.vy
        local v2 = vx * vx + vy * vy
        if v2 > 1 then
          local tc = (rx * vx + ry * vy) / v2
          if tc > 0 and tc < 0.2 then
            local cx, cy = bl.x + vx * tc - p.x, bl.y + vy * tc - p.y
            if cx * cx + cy * cy < (p.r + bl.r + 12) ^ 2 then
              b.blockCd = 0.4
              if p.blockCd <= 0 and love.math.random() < L.blockChance then
                press(inp, "blockCount")
              elseif p.dashesLeft > 0 and p.dashCd <= 0 and love.math.random() < L.dodge then
                inp.aim = math.atan2(-vx, vy) -- dash sideways to the bullet
                press(inp, "dashCount")
              end
              break
            end
          end
        end
      end
    end
    for _, e in ipairs(w:enemiesOf(p)) do
      if e.charging and (e.meleeCharge or 0) > 0.35 and (e.x - p.x) ^ 2 + (e.y - p.y) ^ 2 < 150 * 150
          and p.blockCd <= 0 and love.math.random() < L.blockChance * dt * 10 then
        press(inp, "blockCount")
        b.blockCd = 0.5
      end
    end
  end
end

---------------------------------------------------------------- card picks
-- Score a card for a bot: rarity, plus a bonus when it completes a synergy (hard bots care most).
function Bot.scoreCard(p, card, difficulty)
  local rarityValue = { common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }
  local score = (rarityValue[card.rarity] or 1) * 10 + love.math.random() * (difficulty == 1 and 30 or 10)
  if card.special then score = score - 15 end
  local Synergies = require "game.synergies"
  local copies = {}
  for _, c in ipairs(p.cards) do copies[c.id] = (copies[c.id] or 0) + 1 end
  copies[card.id] = (copies[card.id] or 0) + 1
  for _, syn in ipairs(Synergies.forCard(card, Cards.rules)) do
    if Synergies.sets(syn, copies) > 0 then score = score + 8 * (difficulty or 2) end
  end
  return score
end

-- The world asks a bot to pick: hover over a few cards (so watchers see flips), then take the best.
-- Which card a bot bans before a match: a strong one, with some variety.
function Bot.banChoice()
  local Cards = require "game.cards"
  local best, bestScore
  for _, c in ipairs(Cards.list) do
    if not c.special and not c.disabled and not c.banned then
      local r = 1
      for i, x in ipairs(Cards.RARITIES) do if x.id == c.rarity then r = i end end
      local sc = r + love.math.random() * 2
      if not bestScore or sc > bestScore then best, bestScore = c, sc end
    end
  end
  return best
end

function Bot.pick(w, pk, dt)
  local p = w.players[pk.slot]
  pk.botTimer = (pk.botTimer or -0.7) + dt -- waits while the cards are dealt
  local n = #pk.options
  local step = math.floor(pk.botTimer / 0.35) + 1
  if step <= n then
    w:hover(pk.slot, step)
    return
  end
  if pk.botTimer < n * 0.35 + 0.5 then return end
  local best, bestScore = 1, -math.huge
  for i, c in ipairs(pk.options) do
    local sc = Bot.scoreCard(p, c, p.input.difficulty)
    if sc > bestScore then best, bestScore = i, sc end
  end
  w:hover(pk.slot, best)
  w:choose(pk.slot, best, pk.serial)
end

return Bot
