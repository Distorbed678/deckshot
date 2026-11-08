-- Card trigger rules: "when <event>, do <effect>". Each copy of a card adds its rules again,
-- so they stack. Effects caused by a trigger can't fire more triggers (Player.inTrigger, and
-- bullets they spawn are marked fromTrigger), so chains can't loop.
local fx = require "gfx.fx"
local sfx = require "gfx.sfx"
local Stats = require "game.stats"

local Triggers = {}

-- Events, in the order the editor lists them.
Triggers.WHEN = {
  { "shoot", "When you shoot" }, { "hit", "When your bullet hits" }, { "kill", "When you kill" },
  { "hurt", "When you get hurt" }, { "block", "When you block" }, { "parry", "When your block stops an attack" },
  { "meleeHit", "When your melee hits" }, { "heavyHit", "When your heavy melee hits" },
  { "meleeBlocked", "When you block a melee" }, { "reload", "When you finish reloading" },
  { "jump", "When you jump" }, { "wallJump", "When you wall jump" }, { "land", "When you land hard" },
  { "dash", "When you dash" }, { "lowHp", "When you drop below 30% HP" }, { "roundStart", "At round start" },
  { "interval", "Every few seconds" },
}
Triggers.WHEN_LABEL = {}
for _, w in ipairs(Triggers.WHEN) do Triggers.WHEN_LABEL[w[1]] = w[2] end
Triggers.SHORT = {
  shoot = "On shoot", hit = "On hit", kill = "On kill", hurt = "When hurt", block = "On block", parry = "On parry",
  meleeHit = "On melee hit", heavyHit = "On heavy hit", meleeBlocked = "Blocking a melee", reload = "On reload",
  jump = "On jump", wallJump = "On wall jump", land = "On hard landing", dash = "On dash", lowHp = "Below 30% HP",
  roundStart = "Round start", interval = "Every %ss",
}

-- Effects: params with defaults { key, default, step, min, max, label }, text for the card line.
Triggers.EFFECTS = {
  { id = "explode", name = "Explode", params = { { "radius", 110, 10, 30, 400, "Radius" }, { "damage", 30, 5, 0, 300, "Damage" } },
    text = function(p) return "explode (" .. p.damage .. " dmg)" end },
  { id = "heal", name = "Heal", params = { { "amount", 15, 5, 1, 200, "HP" } },
    text = function(p) return "heal " .. p.amount .. " HP" end },
  { id = "shield", name = "Shield", params = { { "amount", 20, 5, 1, 300, "Shield" } },
    text = function(p) return "gain a " .. p.amount .. " HP shield" end },
  { id = "nova", name = "Bullet nova", params = { { "count", 6, 1, 1, 24, "Bullets" } },
    text = function(p) return "fire " .. p.count .. " bullets around you" end },
  { id = "shockwave", name = "Shockwave", params = { { "radius", 150, 10, 40, 400, "Radius" },
    { "damage", 15, 5, 0, 200, "Damage" } },
    text = function(p) return "release a shockwave (" .. p.damage .. " dmg)" end },
  { id = "speed", name = "Speed boost", params = { { "pct", 30, 5, 5, 300, "Speed %" }, { "time", 2, 0.5, 0.5, 10, "Seconds" } },
    text = function(p) return "+" .. p.pct .. "% move speed for " .. p.time .. "s" end },
  { id = "damage", name = "Damage boost", params = { { "pct", 50, 5, 5, 500, "Damage %" }, { "shots", 1, 1, 0, 10, "Shots (0 = all)" },
    { "time", 0, 0.5, 0, 10, "Within (s)" } },
    text = function(p)
      local within = p.time > 0 and (" within " .. p.time .. "s") or ""
      if p.shots == 0 then
        return "shots deal +" .. p.pct .. "% damage" .. (p.time > 0 and (" for " .. p.time .. "s") or "")
      end
      local who = p.shots > 1 and ("next " .. p.shots .. " shots") or "next shot"
      return who .. within .. " deal" .. (p.shots > 1 and "" or "s") .. " +" .. p.pct .. "% damage"
    end },
  { id = "ammo", name = "Refill ammo", params = { { "amount", 1, 1, 1, 20, "Ammo (20 = all)" } },
    text = function(p) return p.amount >= 20 and "refill all your ammo" or ("refill " .. p.amount .. " ammo") end },
  { id = "invuln", name = "Invulnerable", params = { { "time", 0.5, 0.1, 0.1, 5, "Seconds" } },
    text = function(p) return "become invulnerable for " .. p.time .. "s" end },
  { id = "mine", name = "Drop a mine", params = {}, text = function() return "drop a mine" end },
  { id = "blink", name = "Blink", params = { { "dist", 200, 20, 40, 600, "Distance" } },
    text = function() return "teleport where you aim" end },
  { id = "slow", name = "Slow enemies", params = { { "radius", 220, 10, 40, 600, "Radius" }, { "time", 1.5, 0.5, 0.5, 6, "Seconds" } },
    text = function(p) return "slow nearby enemies for " .. p.time .. "s" end },
  { id = "poison", name = "Poison cloud", params = { { "radius", 150, 10, 40, 500, "Radius" }, { "damage", 20, 5, 1, 200, "Damage" } },
    text = function(p) return "poison nearby enemies (" .. p.damage .. " over 3s)" end },
  { id = "blackhole", name = "Black hole", params = {}, text = function() return "open a black hole" end },
  { id = "dash", name = "Refill dash", params = {}, text = function() return "refill your dash" end },
  { id = "lightning", name = "Lightning", params = { { "damage", 30, 5, 1, 200, "Damage" }, { "delay", 0.75, 0.05, 0.2, 3, "Charge (s)" } },
    text = function(p) return "lightning charges on every enemy, striking for " .. p.damage .. " after " .. p.delay .. "s" end },
  { id = "melee", name = "Reset melee", params = {}, text = function() return "reset your melee cooldown" end },
}
Triggers.EFFECT = {}
for _, e in ipairs(Triggers.EFFECTS) do Triggers.EFFECT[e.id] = e end

-- Params with defaults filled in.
function Triggers.params(rule)
  local e = Triggers.EFFECT[rule.effect]
  local p = {}
  for _, def in ipairs(e and e.params or {}) do p[def[1]] = def[2] end
  for k, v in pairs(rule.params or {}) do p[k] = v end
  return p
end

function Triggers.describe(rule)
  local e = Triggers.EFFECT[rule.effect]
  local p = Triggers.params(rule)
  local when = Triggers.SHORT[rule.when] or rule.when
  if rule.when == "interval" then when = when:format(Stats.num(p.every or 5)) end
  local text = "+" .. when .. ": " .. (e and e.text(p) or rule.effect)
  if rule.chance and rule.chance < 1 then text = text .. " (" .. math.floor(rule.chance * 100 + 0.5) .. "% chance)" end
  if rule.cd and rule.cd > 0 then text = text .. " (every " .. rule.cd .. "s at most)" end
  return text
end

---------------------------------------------------------------- running effects
local function enemiesNear(p, x, y, radius)
  local out = {}
  for _, e in ipairs(p.game:enemiesOf(p)) do
    local dx, dy = e.x - x, e.y - y
    if dx * dx + dy * dy < (radius + e.r) ^ 2 then out[#out + 1] = e end
  end
  return out
end

local RUN = {}
function RUN.explode(p, q, x, y)
  q.radius = q.radius * (p.stats.explosionSize or 1)
  fx.explosion(x, y, q.radius, p.color)
  fx.addShake(5)
  sfx.play(q.radius > 120 and "explosion" or "explosionSmall", x)
  for _, e in ipairs(enemiesNear(p, x, y, q.radius)) do
    e:hit(q.damage, e.x - x, e.y - y, 500, p, "explosion")
  end
  local Objects = require "game.objects"
  if p.game.objects then Objects.explosion(p.game, x, y, q.radius, q.damage, p) end
end
function RUN.heal(p, q)
  p:heal(q.amount)
  fx.burst(p.x, p.y, { 0.4, 1, 0.5 }, 8, 160, 3)
end
function RUN.shield(p, q)
  p.shield = math.min((p.shield or 0) + q.amount, 300)
  fx.ring(p.x, p.y, p.r + 10, { 0.5, 0.8, 1 })
end
function RUN.nova(p, q)
  for i = 1, q.count do p:spawnBullet(i / q.count * math.pi * 2, 0.8, false) end
end
function RUN.shockwave(p, q)
  fx.ring(p.x, p.y, q.radius, p.color)
  fx.addShake(5)
  for _, e in ipairs(enemiesNear(p, p.x, p.y, q.radius)) do e:hit(q.damage, e.x - p.x, e.y - p.y, 650, p) end
  for _, b in ipairs(p.game.bullets) do
    if b.owner ~= p and not b.laser and (b.x - p.x) ^ 2 + (b.y - p.y) ^ 2 < q.radius ^ 2 then b.dead = true end
  end
end
function RUN.speed(p, q)
  p.boostSpeed, p.boostSpeedTimer = math.max(p.boostSpeed or 0, q.pct / 100), q.time
end
function RUN.damage(p, q)
  p.boostDamage = math.max(p.boostDamage or 0, q.pct / 100)
  p.boostShots = q.shots == 0 and math.huge or math.max(p.boostShots or 0, q.shots)
  p.boostTimer = q.time > 0 and q.time or math.huge
end
-- Marks every enemy's spot; after the delay, strikes there (dodgeable). Runs through world.strikes.
function RUN.lightning(p, q)
  for _, e in ipairs(p.game:enemiesOf(p)) do
    table.insert(p.game.effects, { type = "strike", x = e.x, y = e.y, life = q.delay, max = q.delay, owner = p,
      damage = q.damage, radius = 55 })
  end
  sfx.play("laserCharge", p.x, 0.8)
end
function RUN.ammo(p, q)
  p.ammo = math.min(p.stats.ammo, p.ammo + q.amount)
  p.reloadTimer = 0
end
function RUN.invuln(p, q)
  p.invuln = math.max(p.invuln, q.time)
end
function RUN.mine(p)
  local Bullet = require "game.bullet"
  local m = Bullet.new(p, p.x, p.y + p.r - 6, 0, 0)
  m.laser = false
  m.fromTrigger = true
  m:becomeMine()
  m.armTime = 0.8
  p.game:addBullet(m)
end
function RUN.blink(p, q)
  p:blink(q.dist)
end
function RUN.slow(p, q)
  fx.ring(p.x, p.y, q.radius, { 0.6, 0.85, 1 })
  for _, e in ipairs(enemiesNear(p, p.x, p.y, q.radius)) do e.slowTimer = math.max(e.slowTimer, q.time) end
end
function RUN.poison(p, q)
  fx.ring(p.x, p.y, q.radius, { 0.4, 0.9, 0.2 })
  for _, e in ipairs(enemiesNear(p, p.x, p.y, q.radius)) do e:poisonFor(q.damage, 3) end
end
function RUN.blackhole(p, q, x, y)
  table.insert(p.game.wells, { x = x, y = y, t = 1.4, max = 1.4, owner = p, radius = 260, strength = 3000 })
  sfx.play("blackhole", x)
end
function RUN.dash(p)
  p.dashesLeft = p.stats.dashes
  p.dashCd = 0
end
function RUN.melee(p)
  p.meleeCd = 0
end

-- Run one rule for player p. ctx: { target = player, x = .., y = .. } (where it happened).
function Triggers.run(p, rule, ctx)
  local f = RUN[rule.effect]
  if not f or not p.game then return end
  local q = Triggers.params(rule)
  local x, y = p.x, p.y
  if ctx and ctx.target then x, y = ctx.target.x, ctx.target.y end
  if ctx and ctx.x then x, y = ctx.x, ctx.y end
  f(p, q, x, y)
end

return Triggers
