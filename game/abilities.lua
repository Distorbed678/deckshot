-- What the v0.7 cards do. Player and Bullet call these hooks at their events; each card is a
-- stat counted in copies (0 = not owned), so everything here scales with the count.
-- Statuses (burn, shock, freeze, bleed) live on the player who has them; card effects that sit
-- in the arena are entries in world.effects (see EFFECT_TYPES in online/snapshot.lua).
local Physics = require "game.physics"
local fx = require("game.events").fx
local sfx = require("game.events").sfx

local A = {}

local function dist2(a, b) return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 end
local function enemies(p) return p.game and p.game.enemiesOf and p.game:enemiesOf(p) or {} end
local function sees(game, a, b) return Physics.canReach(game, a.x, a.y, b.x, b.y) end
local function addEffect(game, e)
  if game and game.effects then table.insert(game.effects, e) end
  return e
end

-- Gadgets (turrets, drones, mines, bees, moons) are stronger and faster with Hive Mind.
function A.gadgetDamage(p) return 1 + ((p.stats.hiveMind or 0) > 0 and (1 + 0.5 * (p.stats.hiveMind - 1)) or 0) end
function A.gadgetRate(p) return 1 + 0.5 * (p.stats.hiveMind or 0) end

---------------------------------------------------------------- per round / respawn
function A.reset(p)
  p.burnT, p.burnDps, p.burnBy = 0, 0, nil
  p.shockT, p.shockAmp = 0, 0
  p.freezeT = 0
  p.bleedT, p.bleedDps, p.bleedBy = 0, 0, nil
  p.sapT = 0
  p.slowedFor = 0
  p.statusCount = {}
  p.kineticBonus = 0
  p.overchargeCount = 0
  p.comboHits, p.comboT = 0, 0
  p.secondSwings = 0
  p.overdriveStacks, p.overdriveT, p.lastDashAt = 0, 0, -10
  p.sinceDash = 10
  p.rageStacks, p.rageT = 0, 0
  p.wagerWon = false
  p.lastLightUsed = false
  p.finalGambitUsed = false
  p.mineT, p.droneCd = 0, {}
  p.shotCount = 0
  p.gravityBombT = 0
  p.flipT = 0
  p.aegisHits = 0
  p.gunOut = nil
  p.chargeShotUsed = false
  p.launchedBy, p.haymakerBy, p.haymakerT = nil, nil, 0
  p.blockStock = nil
end

-- Wager: you start the round lower.
function A.roundStart(p)
  local s = p.stats
  if (s.wager or 0) > 0 then p.hp = math.min(p.hp, s.maxHp * 0.7) end
end

---------------------------------------------------------------- statuses
-- Burn: damage over time that can spread (Wildfire). Stacks the remaining damage like poison.
function A.burn(p, total, duration, by)
  if p.dead or total <= 0 then return end
  local left = (p.burnDps or 0) * (p.burnT or 0)
  p.burnT = math.max(p.burnT or 0, duration)
  p.burnDps = (left + total) / p.burnT
  p.burnBy = by or p.burnBy
  A.countStatus(p, by, "burn")
end

-- Shock: the next damage the target takes is amplified.
function A.shock(p, amp, by)
  if p.dead then return end
  p.shockT = 2
  p.shockAmp = math.max(p.shockAmp or 0, amp)
  A.countStatus(p, by, "shock")
end

-- Freeze: a short stun with a frosty look.
function A.freeze(p, t, by)
  if p.dead then return end
  p.freezeT = math.max(p.freezeT or 0, t)
  p:stun(t)
  fx.burst(p.x, p.y, { 0.7, 0.9, 1 }, 14, 200, 3)
  sfx.play("glassBreak", p.x, 0.5, 1.4)
  A.countStatus(p, by, "freeze")
end

function A.bleedOn(p, total, duration, by)
  if p.dead then return end
  local left = (p.bleedDps or 0) * (p.bleedT or 0)
  p.bleedT = duration
  p.bleedDps = (left + total) / duration
  p.bleedBy = by
end

-- Overload: every Nth status a player puts on the same enemy sets off that status's burst.
function A.countStatus(p, by, kind)
  if not by or not by.stats or (by.stats.overload or 0) <= 0 or by == p then return end
  p.statusCount = p.statusCount or {}
  local n = (p.statusCount[by] or 0) + 1
  local need = math.max(2, 5 - (by.stats.overload - 1))
  if n >= need then
    n = 0
    A.overloadBurst(p, by, kind)
  end
  p.statusCount[by] = n
end

function A.overloadBurst(p, by, kind)
  local game = p.game
  if kind == "burn" then
    fx.explosion(p.x, p.y, 120, { 1, 0.5, 0.15 })
    for _, e in ipairs(enemies(by)) do
      if dist2(e, p) < 140 * 140 then e:hit(40, e.x - p.x, e.y - p.y, 400, by, "explosion"); A.burn(e, 20, 2) end
    end
  elseif kind == "freeze" or kind == "slow" then
    fx.ring(p.x, p.y, 90, { 0.7, 0.9, 1 })
    p.freezeT = math.max(p.freezeT or 0, 1)
    p:stun(1)
  elseif kind == "poison" then
    addEffect(game, { type = "cloud", x = p.x, y = p.y, radius = 110, life = 3, max = 3, owner = by, source = by, slow = true })
  else -- shock
    local n = 0
    for _, e in ipairs(enemies(by)) do
      if e ~= p and n < 2 and dist2(e, p) < 260 * 260 and sees(game, p, e) then
        n = n + 1
        fx.arc(p.x, p.y, e.x, e.y)
        e:hit(30, e.x - p.x, e.y - p.y, 200, by, "shock")
      end
    end
    fx.ring(p.x, p.y, 60, { 0.6, 0.85, 1 })
  end
  sfx.play("explosionSmall", p.x, 0.6, 1.2)
end

-- Ticking statuses on the player who has them (host only).
function A.updateStatus(p, dt)
  if p.dead then return end
  if (p.burnT or 0) > 0 then
    p.burnT = p.burnT - dt
    p.hp = p.hp - p.burnDps * dt
    if p.burnBy and p.burnBy ~= p and p.burnBy.st then p.burnBy.st.dmg = p.burnBy.st.dmg + p.burnDps * dt end
    if p.hp <= 0 then p.lastAttacker = p.burnBy or p.lastAttacker; p:die() return end
    -- Wildfire: the fire spreads to the burner's other enemies close by.
    local by = p.burnBy
    if by and by.stats and (by.stats.wildfire or 0) > 0 then
      p.spreadT = (p.spreadT or 0) - dt
      if p.spreadT <= 0 then
        p.spreadT = 1
        local reach = 120 + 60 * (by.stats.wildfire - 1)
        for _, e in ipairs(enemies(by)) do
          if e ~= p and (e.burnT or 0) <= 0 and dist2(e, p) < reach * reach then
            A.burn(e, 12, 2, by)
            fx.spray(p.x, p.y, math.atan2(e.y - p.y, e.x - p.x), 0.4, { 1, 0.55, 0.2 }, 6, 400, 2.5, 0)
          end
        end
      end
    end
  end
  if (p.bleedT or 0) > 0 then
    p.bleedT = p.bleedT - dt
    p.hp = p.hp - p.bleedDps * dt
    if p.hp <= 0 then p.lastAttacker = p.bleedBy or p.lastAttacker; p:die() return end
  end
  if (p.shockT or 0) > 0 then
    p.shockT = p.shockT - dt
    if p.shockT <= 0 then p.shockAmp = 0 end
  end
  p.freezeT = math.max(0, (p.freezeT or 0) - dt)
  p.sapT = math.max(0, (p.sapT or 0) - dt)
  -- Frostbite: slowed for 2s straight freezes you (by whoever has Frostbite among your enemies).
  if p.slowTimer > 0 then
    p.slowedFor = (p.slowedFor or 0) + dt
    if p.slowedFor >= 2 and p.game and p.game.players then
      for _, q in ipairs(p.game.players) do
        if q ~= p and (q.stats.frostbite or 0) > 0 and p.game:isEnemy(q, p) then
          A.freeze(p, 0.6 + 0.3 * (q.stats.frostbite - 1), q)
          p.slowedFor = -1 -- a little grace before it can happen again
          break
        end
      end
    end
  else
    p.slowedFor = 0
  end
  -- Toxic Puddle: poisoned enemies leave puddles behind them.
  if p.poisonTimer > 0 and p.lastAttacker and p.lastAttacker.stats and (p.lastAttacker.stats.toxicPuddle or 0) > 0 then
    p.puddleT = (p.puddleT or 0) - dt
    if p.puddleT <= 0 then
      p.puddleT = 1
      local by = p.lastAttacker
      addEffect(p.game, { type = "cloud", x = p.x, y = p.y + p.r, radius = 40 * (1 + 0.3 * (by.stats.toxicPuddle - 1)),
        life = 3, max = 3, owner = by, source = by })
    end
  end
end

---------------------------------------------------------------- damage
-- Every hit goes through here (Player:hit), after a block or invulnerability has had its say.
-- Returns the adjusted amount.
function A.incoming(victim, amount, source, kind)
  local vs = victim.stats
  -- The attacker's side.
  local s = source and source ~= victim and source.stats
  if s then
    if (source.sapT or 0) > 0 then amount = amount * 0.8 end
    if (s.brittle or 0) > 0 and (victim.slowTimer > 0 or (victim.chillTimer or 0) > 0) then amount = amount * (1 + 0.15 * s.brittle) end
    if (s.corrode or 0) > 0 and victim.poisonTimer > 0 then amount = amount * (1 + 0.2 * s.corrode) end
    if (s.daredevil or 0) > 0 and dist2(source, victim) < 250 * 250 then amount = amount * (1 + 0.3 * s.daredevil) end
    if (s.lastBreath or 0) > 0 and source.hp < s.maxHp * 0.3 then amount = amount * (1.5 + 0.25 * (s.lastBreath - 1)) end
    if (source.rageStacks or 0) > 0 then amount = amount * (1 + (0.1 + 0.05 * (s.rage - 1)) * source.rageStacks) end
    if source.wagerWon then amount = amount * (1 + 0.4 * s.wager) end
    if (source.overdriveStacks or 0) > 0 then amount = amount * (1 + 0.15 * source.overdriveStacks) end
    if (s.airHunter or 0) > 0 and victim.launchedBy == source and not victim.onGround then amount = amount * (1 + 0.5 * s.airHunter) end
    if (s.shatterpoint or 0) > 0 and (victim.freezeT or 0) > 0 then
      amount = amount * (2 + 0.5 * (s.shatterpoint - 1))
      victim.freezeT, victim.stunTimer = 0, 0
      fx.burst(victim.x, victim.y, { 0.75, 0.92, 1 }, 18, 300, 4)
      sfx.play("glassBreak", victim.x, 0.8)
    end
  end
  -- The victim's side.
  if (victim.shockT or 0) > 0 and (victim.shockAmp or 0) > 0 then
    amount = amount * (1 + victim.shockAmp)
    victim.shockAmp, victim.shockT = 0, 0
    fx.burst(victim.x, victim.y, { 0.6, 0.85, 1 }, 8, 220, 2.5)
  end
  if (vs.ironJaw or 0) > 0 and victim.charging then amount = amount * 0.5 ^ vs.ironJaw end
  if (vs.ironWill or 0) > 0 then
    local cap = vs.maxHp * math.max(0.3, 0.6 - 0.1 * (vs.ironWill - 1))
    amount = math.min(amount, cap)
  end
  return amount
end

-- After a hit landed on the victim.
function A.hurt(victim, amount, source)
  local vs = victim.stats
  if (vs.rage or 0) > 0 then
    victim.rageStacks = math.min(5, (victim.rageStacks or 0) + 1)
    victim.rageT = 4
  end
  -- Last Light: the first time you drop below 25% in a round, you blow everyone back.
  if (vs.lastLight or 0) > 0 and not victim.lastLightUsed and victim.hp > 0 and victim.hp < vs.maxHp * 0.25 then
    victim.lastLightUsed = true
    victim.lastLightT = 4
    local dmg = 80 + 40 * (vs.lastLight - 1)
    fx.explosion(victim.x, victim.y, 400, { 1, 0.95, 0.7 })
    sfx.play("explosion", victim.x, 1, 0.8)
    for _, e in ipairs(enemies(victim)) do
      if dist2(e, victim) < 400 * 400 and sees(victim.game, victim, e) then
        e:hit(dmg, e.x - victim.x, e.y - victim.y, 900, victim, "explosion")
      end
    end
  end
end

-- A bullet (or its blast) hit p: the statuses its owner's cards put on.
function A.bulletEffects(b, p, dmg, blast)
  local o = b.owner
  local s = o and o.stats
  if not s or p == o or p.dead then return end
  if (s.burnOnHit or 0) > 0 then A.burn(p, 12 * s.burnOnHit, 2, o) end
  if blast and (s.cinders or 0) > 0 then A.burn(p, 15, 2 + (s.cinders - 1), o) end
  if (s.sap or 0) > 0 then p.sapT = math.max(p.sapT or 0, 2 + (s.sap - 1)) end
  if b.poison > 0 then A.countStatus(p, o, "poison") end
  if b.frost > 0 then A.countStatus(p, o, "slow") end
  -- Conductor: a shocked enemy arcs to another (checked before this hit's own shock).
  if (s.conductor or 0) > 0 and (p.shockT or 0) > 0 and not blast then
    local arcs = 0
    for _, e in ipairs(enemies(o)) do
      if e ~= p and arcs < s.conductor and dist2(e, p) < 200 * 200 and sees(o.game, p, e) then
        arcs = arcs + 1
        fx.arc(p.x, p.y, e.x, e.y)
        e:hit(15, e.x - p.x, e.y - p.y, 150, o, "shock")
      end
    end
  end
  if (s.shockOnHit or 0) > 0 then A.shock(p, 0.25 * s.shockOnHit, o) end
  -- Thermal Shock: burning and slowed at once sets off a burst.
  if (s.thermal or 0) > 0 and (p.burnT or 0) > 0 and (p.slowTimer > 0 or (p.chillTimer or 0) > 0) then
    p.burnT, p.slowTimer = 0, 0
    fx.explosion(p.x, p.y, 70, { 1, 0.7, 0.5 })
    p:hit(40 + 20 * (s.thermal - 1), 0, -1, 400, o, "explosion")
  end
end

-- Extra damage a bullet carries into a player hit (bounce cards, dash shots, kinetic charge...).
function A.bulletDamage(b, p, dmg)
  local s = b.owner and b.owner.stats
  if not s then return dmg end
  local bounced = (b.bouncesDone or 0) > 0
  if bounced and (s.bounceBonus or 0) > 0 then dmg = dmg * (1 + 0.15 * s.bounceBonus) end
  if bounced and (s.trickShot or 0) > 0 then dmg = dmg * (1.75 + 0.5 * (s.trickShot - 1)) end
  if (b.bouncesDone or 0) >= 2 and (s.cornerPocket or 0) > 0 then dmg = dmg * (3 + (s.cornerPocket - 1)) end
  if b.rubber and (b.bouncesDone or 0) > 0 then dmg = dmg * 0.9 ^ b.bouncesDone end
  return dmg
end

---------------------------------------------------------------- shooting
-- Called as a bullet is made; m = damage multiplier so far. Returns the new multiplier.
function A.shotDamage(p, b)
  local s = p.stats
  if (s.dashShots or 0) > 0 and (p.sinceDash or 10) < 0.5 then b.damage = b.damage * (1 + 0.5 * s.dashShots) end
  if (p.kineticBonus or 0) > 0 then b.damage = b.damage * (1 + p.kineticBonus) end
  if (s.hemorrhage or 0) > 0 then
    b.damage = b.damage * (1.6 + 0.3 * (s.hemorrhage - 1))
    b.pierce = b.pierce + 1
  end
  if (s.rubberRoom or 0) > 0 then
    b.rubber = true
    b.bounces = 999
    b.life = 6 + 3 * (s.rubberRoom - 1)
  end
  if (s.boomerang or 0) > 0 then b.returns = s.boomerang end
  if (s.bodyBounce or 0) > 0 then b.bodyBounces = s.bodyBounce end
  if (p.flipT or 0) > 0 then b.gravity = -math.abs(b.gravity or 0) end
end

-- After a volley: costs and once-per-shot cards.
function A.afterShot(p)
  local s, game = p.stats, p.game
  p.kineticBonus = 0
  p.shotCount = (p.shotCount or 0) + 1
  -- Hemorrhage: every shot costs HP (it can't kill you).
  if (s.hemorrhage or 0) > 0 and p.hp > 4 then p.hp = math.max(1, p.hp - 3); p.hitFlash = 0.05 end
  -- Reprise: every Nth shot fires again a moment later.
  if (s.reprise or 0) > 0 and p.shotCount % math.max(2, 4 - (s.reprise - 1)) == 0 then p.repriseT = 0.2 end
end

-- Which special bullet this shot is (Grenadier, Gravity Bomb, Remote Charge), set before it fires.
function A.specialShot(p, b)
  local s = p.stats
  if (s.grenadier or 0) > 0 and ((p.shotCount or 0) + 1) % math.max(2, 5 - (s.grenadier - 1)) == 0 then
    b.grenadeT = 1.5
    b.bounces = math.max(b.bounces, 8)
    b.explosion = math.max(b.explosion, 90)
    b.grenadeDamage = 50 * A.gadgetDamage(p)
    b.r = b.r * 1.6
  end
  if (s.gravityBomb or 0) > 0 and (p.gravityBombT or 0) <= 0 then
    p.gravityBombT = math.max(1.5, 6 - 1.5 * (s.gravityBomb - 1))
    b.gravOrb = true
    local sp = math.sqrt(b.vx * b.vx + b.vy * b.vy)
    b.vx, b.vy = b.vx / sp * 380, b.vy / sp * 380
    b.gravity = 0
    b.r = b.r * 2
    b.life = 1.2
  end
  if (s.remoteCharge or 0) > 0 and not p.chargeShotUsed then
    p.chargeShotUsed = true
    b.remoteCharge = true
  end
end

---------------------------------------------------------------- blocking
function A.block(p, echo)
  local s, game = p.stats, p.game
  -- Remote Charge: blocking with a charge out sets it off instead (handled before the block).
  if (s.staticGuard or 0) > 0 then
    local zapped = 0
    for _, e in ipairs(enemies(p)) do
      if zapped < s.staticGuard and dist2(e, p) < 300 * 300 and sees(game, p, e) then
        zapped = zapped + 1
        fx.arc(p.x, p.y, e.x, e.y)
        e:hit(20, e.x - p.x, e.y - p.y, 200, p, "shock")
      end
    end
    if zapped > 0 then sfx.play("laserFire", p.x, 0.5, 1.8) end
  end
  if (s.blockDash or 0) > 0 then
    p.dashesLeft = math.max(p.dashesLeft, s.dashes)
    p.dashCd = 0
    if s.blockDash > 1 then p.ammo = math.min(s.ammo, p.ammo + (s.blockDash - 1)) end
  end
  if (s.ward or 0) > 0 then
    local t = 3 + 2 * (s.ward - 1)
    addEffect(game, { type = "ward", x = p.x, y = p.y, radius = 70, life = t, max = t, owner = p, kind = p.slot or 0 })
  end
  if (s.overcharge or 0) > 0 and not echo then
    p.overchargeCount = (p.overchargeCount or 0) + 1
    if p.overchargeCount >= 3 then
      p.overchargeCount = 0
      local dmg = 60 + 30 * (s.overcharge - 1)
      fx.explosion(p.x, p.y, 250, p.color)
      sfx.play("explosion", p.x, 0.8, 1.2)
      for _, e in ipairs(enemies(p)) do
        if dist2(e, p) < 250 * 250 and sees(game, p, e) then e:hit(dmg, e.x - p.x, e.y - p.y, 700, p, "explosion") end
      end
    end
  end
  if (s.spikeTrap or 0) > 0 then
    for i = 1, s.spikeTrap do
      addEffect(game, { type = "trap", x = p.x + (i - (s.spikeTrap + 1) / 2) * 40, y = p.y + p.r + p.leg - 6,
        radius = 22, life = 12, max = 12, owner = p, kind = p.slot or 0 })
    end
  end
  if (s.iceWall or 0) > 0 then
    local dir = p.facing or 1
    local e = addEffect(game, { type = "icewall", x = p.x + dir * (p.r + 40), y = p.y + p.r + p.leg - 48, radius = 96,
      life = 4 + (s.iceWall - 1), max = 4 + (s.iceWall - 1), owner = p, hp = 60 + 30 * (s.iceWall - 1), kind = p.slot or 0 })
    Physics.addEffectWall(game, e, 24, 96)
  end
  if (s.totem or 0) > 0 then
    local t = 5 + 2 * (s.totem - 1)
    addEffect(game, { type = "totem", x = p.x, y = p.y + p.r + p.leg - 20, radius = 200, life = t, max = t, owner = p, kind = p.slot or 0 })
  end
  if (s.fieldTurret or 0) > 0 then
    local out = {}
    for _, e in ipairs(game.effects or {}) do if e.type == "turret" and e.owner == p then out[#out + 1] = e end end
    if #out >= 1 + s.fieldTurret then out[1].life = 0 end
    addEffect(game, { type = "turret", x = p.x, y = p.y - p.r - 30, radius = 12, life = 8, max = 8, owner = p,
      fireT = 0.6, kind = p.slot or 0 })
  end
  if (s.aegis or 0) > 0 and not echo then
    p.blockTimer = 2 + (s.aegis - 1)
    p.aegisHits = 3 + 2 * (s.aegis - 1)
  end
  if (s.upsideDown or 0) > 0 and not echo then
    p.flipT = 3 + 2 * (s.upsideDown - 1)
    fx.ring(p.x, p.y, 60, { 0.8, 0.6, 1 })
  end
end

-- p blocked bullet b (its owner is now p). Called from Bullet:hitPlayer.
function A.blockedBullet(p, b, game, shooter)
  local s = p.stats
  -- Perfect Guard: a block raised at the last moment fires the bullet back harder.
  if (s.perfectGuard or 0) > 0 and (s.blockTime - p.blockTimer) <= 0.15 then
    b.vx, b.vy = b.vx * 2, b.vy * 2
    b.damage = b.damage * (1 + 0.5 * s.perfectGuard)
    fx.ring(p.x, p.y, p.r + 26, { 1, 1, 0.7 })
    sfx.play("parry", p.x, 0.8)
  end
  if (s.kineticGuard or 0) > 0 then
    p.kineticBonus = math.min(0.9 * s.kineticGuard, (p.kineticBonus or 0) + 0.15 * s.kineticGuard)
  end
  if (s.mirrorPlate or 0) > 0 and not b.laser then
    local target = game:nearestEnemy(p, p.x, p.y, true)
    if target then
      for i = 1, s.mirrorPlate do
        local c = b:clone()
        local a = math.atan2(target.y - p.y, target.x - p.x) + (i - (s.mirrorPlate + 1) / 2) * 0.12
        local sp = math.max(600, math.sqrt(b.vx * b.vx + b.vy * b.vy))
        c.vx, c.vy = math.cos(a) * sp, math.sin(a) * sp
        game:addBullet(c)
      end
    end
  end
  if (p.aegisHits or 0) > 0 then
    p.aegisHits = p.aegisHits - 1
    if p.aegisHits <= 0 then p.blockTimer = 0; fx.burst(p.x, p.y, { 0.8, 0.9, 1 }, 16, 260, 3) end
  end
end

---------------------------------------------------------------- dashing
function A.dash(p, dx, dy)
  local s, game = p.stats, p.game
  local now = game.time or 0
  p.sinceDash = 0
  p.dashHits = {}
  p.grazed = {}
  p.rebounded = false
  p.dashFromX, p.dashFromY = p.x, p.y
  if (s.dashShot or 0) > 0 then
    for i = 1, s.dashShot do
      local a = math.atan2(dy, dx) + (i - (s.dashShot + 1) / 2) * 0.12
      p.freeShotAngle = a
      p:spawnBullet(a, 1, false, 1)
    end
  end
  if (s.overdrive or 0) > 0 then
    if now - (p.lastDashAt or -10) <= 2 then
      p.overdriveStacks = math.min(3 + (s.overdrive - 1), (p.overdriveStacks or 0) + 1)
    else
      p.overdriveStacks = math.max(1, p.overdriveStacks or 0)
    end
    p.overdriveT = 3
  end
  p.lastDashAt = now
  if (s.ghostRun or 0) > 0 then p.cloakTimer = math.max(p.cloakTimer or 0, 1.5 + (s.ghostRun - 1)) end
  if (s.airAce or 0) > 0 and not p.onGround then p.fallJump = true end
  if (s.decoy or 0) > 0 then
    local t = 2 + (s.decoy - 1)
    addEffect(game, { type = "decoy", x = p.x, y = p.y, radius = p.r, life = t, max = t, owner = p,
      damage = 30 + 15 * (s.decoy - 1), kind = p.slot or 0 })
  end
  -- Flash Step: the dash is an instant jump to its end; a decoy pops where you were.
  if (s.flashStep or 0) > 0 then
    local reach = s.dashSpeed * 0.14
    local tx, ty = p.x + dx * reach, p.y + dy * reach
    local _, hx, hy = Physics.ray(game, p.x, p.y, tx, ty)
    if hx then tx, ty = hx - dx * (p.r + 4), hy - dy * (p.r + 4) end
    addEffect(game, { type = "bomb", x = p.x, y = p.y, life = 1, max = 1, owner = p, damage = 40 * s.flashStep, radius = 90 })
    fx.ghost(p.x, p.y, p.r, p.color)
    p.x, p.y = tx, ty
    p.dashTimer = 0.02
  end
end

-- Things that happen during a dash (called each step while dashTimer > 0, and just after).
function A.dashing(p, dt)
  local s, game = p.stats, p.game
  p.dashHits = p.dashHits or {}
  for _, e in ipairs(enemies(p)) do
    if not p.dashHits[e] and not e.dead and dist2(e, p) < (p.r + e.r + 8) ^ 2 then
      p.dashHits[e] = true
      if (s.razorDash or 0) > 0 then
        e:hit(25 * s.razorDash, e.x - p.x, e.y - p.y, 300, p, "melee")
        fx.burst(e.x, e.y, { 1, 1, 1 }, 10, 280, 2.5)
      end
      if (s.impactDash or 0) > 0 then
        local d = math.max(1, math.sqrt(dist2(e, p)))
        e.vx, e.vy = (e.x - p.x) / d * 900, (e.y - p.y) / d * 900 - 250
        e:stun(0.3 * s.impactDash)
        sfx.play("meleeHitHeavy", e.x, 0.7)
      end
    end
  end
  -- Rebound: dashing into a wall throws you back off it with your dash refilled.
  if (s.rebound or 0) > 0 and p.wallDir ~= 0 and (p.dashX or 0) * p.wallDir > 0 and not p.rebounded then
    p.rebounded = true
    p.dashX = -p.dashX * (1 + 0.2 * (s.rebound - 1))
    p.vx = p.dashX
    p.dashTimer = math.max(p.dashTimer, 0.12)
    p.dashesLeft = math.max(p.dashesLeft, s.dashes)
    p.dashCd = 0
    fx.burst(p.x + p.wallDir * p.r, p.y, { 1, 1, 1 }, 10, 240, 3)
    sfx.play("bounce", p.x, 0.8, 0.8)
  end
  if (s.emberTrail or 0) > 0 then
    p.emberT = (p.emberT or 0) - dt
    if p.emberT <= 0 then
      p.emberT = 0.05
      local t = 1.5 + (s.emberTrail - 1)
      addEffect(game, { type = "fire", x = p.x, y = p.y, radius = 26, life = t, max = t, owner = p, kind = p.slot or 0 })
    end
  end
  if (s.graze or 0) > 0 then
    p.grazed = p.grazed or {}
    for _, b in ipairs(game.bullets) do
      if b.owner ~= p and not b.dead and not p.grazed[b] and (b.x - p.x) ^ 2 + (b.y - p.y) ^ 2 < (p.r + 40) ^ 2 then
        p.grazed[b] = true
        p.ammo = math.min(s.ammo, p.ammo + s.graze)
        fx.burst(b.x, b.y, { 1, 1, 0.7 }, 4, 120, 2)
      end
    end
  end
end

-- The dash just ended: Thunder Step strikes along the path.
function A.dashEnded(p)
  local s, game = p.stats, p.game
  if (s.thunderStep or 0) > 0 and p.dashFromX then
    local x0, y0 = p.dashFromX, p.dashFromY
    local n = 4
    for i = 0, n do
      local k = i / n
      addEffect(game, { type = "strike", x = x0 + (p.x - x0) * k, y = y0 + (p.y - y0) * k, life = 0.4, max = 0.4,
        owner = p, damage = 35 + 20 * (s.thunderStep - 1), radius = 40 })
    end
  end
  p.dashFromX = nil
end

---------------------------------------------------------------- melee
-- Returns the damage and knockback for a melee hit after the melee cards.
function A.meleeDamage(p, e, heavy, power, dmg, knock)
  local s = p.stats
  if heavy then dmg = dmg * (s.heavyDamage or 1) end
  if not heavy and (s.comboFists or 0) > 0 then
    p.comboHits = (p.comboHits or 0) + 1
    p.comboT = 1.5
    if p.comboHits >= 3 then
      p.comboHits = 0
      dmg = dmg * (3 + 0.5 * (s.comboFists - 1))
      fx.ring(e.x, e.y, 40, { 1, 0.85, 0.4 })
    end
  end
  if heavy and power >= 0.99 and (s.haymaker or 0) > 0 then
    dmg = dmg * 2.5
    knock = knock * 2
    e.haymakerBy, e.haymakerT = p, 0.8
  end
  if (p.riposteHeavy or 0) > 0 and heavy then
    dmg = dmg * (1 + 0.3 * (s.instantHeavy - 1))
    p.riposteHeavy = 0
  end
  return dmg, knock
end

function A.meleeLanded(p, e, heavy, power)
  local s = p.stats
  if (s.bleed or 0) > 0 then A.bleedOn(e, 18 * s.bleed, 3, p) end
  if heavy and (s.secondSwing or 0) > 0 then p.secondSwings = s.secondSwing end
  if heavy and (s.grapple or 0) > 0 and not e.dead then
    local side = (e.x >= p.x) and 1 or -1
    e.x, e.y = p.x + side * (p.r + e.r + 6), p.y
    e.vx, e.vy = 0, 0
    e:stun(0.6 + 0.3 * (s.grapple - 1))
  end
  if (s.airHunter or 0) > 0 and heavy then e.launchedBy = p end
  -- Executioner: low enough, and the hit finishes them.
  if (s.meleeExecute or 0) > 0 and not e.dead and e.hp < e.stats.maxHp * (0.25 + 0.1 * (s.meleeExecute - 1)) then
    fx.burst(e.x, e.y, { 1, 0.3, 0.3 }, 20, 360, 4)
    e.hp = 0
    e.lastAttacker = p
    e:die()
  end
end

-- Meteor Fist: the slam lands.
function A.meteorLanding(p)
  local s = p.stats
  local fall = math.max(0, p.y - (p.meteorFrom or p.y))
  p.meteorFrom = nil
  local dmg = 30 + 10 * fall / 100 + 20 * ((s.meteor or 1) - 1)
  fx.explosion(p.x, p.y + p.r, 150, { 0.85, 0.8, 0.75 })
  sfx.play("thud", p.x, 1)
  for _, e in ipairs(enemies(p)) do
    if dist2(e, p) < 160 * 160 then e:hit(dmg, e.x - p.x, -1, 600, p, "melee") end
  end
end

-- A melee into a block: Guard Break shatters it (returns true when the swing isn't stunned).
function A.meleeBlocked(p, e, heavy)
  local s = p.stats
  if heavy and (s.guardBreak or 0) > 0 then
    e.blockTimer = 0
    e.blockCd = e.stats.blockCooldown
    e.blockStock = 0
    e:stun(0.3 * s.guardBreak)
    fx.burst(e.x, e.y, { 1, 0.9, 0.6 }, 18, 320, 3)
    sfx.play("glassBreak", e.x, 0.7, 0.8)
    return true
  end
  return false
end

---------------------------------------------------------------- bullets
-- A bullet bounced off something (after Bullet:bounce counted it).
function A.bounced(b, game)
  local s = b.owner and b.owner.stats
  b.bouncesDone = (b.bouncesDone or 0) + 1
  if not s then return end
  if (s.superBall or 0) > 0 then b.vx, b.vy = b.vx * (1 + 0.15 * s.superBall), b.vy * (1 + 0.15 * s.superBall) end
  if (s.bounceBomb or 0) > 0 and not b.isChild then
    addEffect(game, { type = "bomb", x = b.x, y = b.y, life = 0.5, max = 0.5, owner = b.owner, damage = 15 * s.bounceBomb, radius = 55 })
  end
  if (s.sonar or 0) > 0 then
    local reach = 150 + 50 * (s.sonar - 1)
    fx.ring(b.x, b.y, reach, { 0.6, 0.9, 1 })
    for _, e in ipairs(enemies(b.owner)) do
      if dist2(e, b) < reach * reach then e.slowTimer = math.max(e.slowTimer, 1) end
    end
  end
end

-- Each step of a live bullet: grenades, gravity orbs, boomerangs, spring walls.
function A.bulletStep(b, dt, game)
  -- Bees chase the nearest enemy they can see, wherever it is (after a moment, even the one they came from).
  if b.isBee and b.age > 0.3 then b.hitSet = nil end
  if b.isBee and b.owner then
    local e = game:nearestEnemy(b.owner, b.x, b.y, true)
    if e then
      local sp = math.max(300, math.sqrt(b.vx * b.vx + b.vy * b.vy))
      local cur = math.atan2(b.vy, b.vx)
      local diff = (math.atan2(e.y - b.y, e.x - b.x) - cur + math.pi) % (math.pi * 2) - math.pi
      cur = cur + math.max(-7 * dt, math.min(7 * dt, diff))
      b.vx, b.vy = math.cos(cur) * sp, math.sin(cur) * sp
    end
  end
  if b.gravOrb and b.life <= 0 then
    b.dead = true
    A.bulletImpact(b, game)
    return
  end
  if b.grenadeT then
    b.grenadeT = b.grenadeT - dt
    if b.grenadeT <= 0 then
      b.dead = true
      require("game.objects").explodeAt(game, b.x, b.y, b.explosion, b.grenadeDamage or 50, b.owner, b.color, b.owner)
    end
  end
  if b.returns and b.age > (b.isGun and 0.35 or 0.6) and not b.coming then
    b.coming = true
  end
  if b.coming and b.owner and not b.owner.dead then
    local o = b.owner
    local dx, dy = o.x - b.x, o.y - b.y
    local d = math.sqrt(dx * dx + dy * dy)
    local sp = math.max(500, math.sqrt(b.vx * b.vx + b.vy * b.vy))
    if d < o.r + 10 then
      -- Back in hand. Boomerang copies send it out again.
      if not b.isGun and (b.returns or 1) > 1 then
        b.returns, b.coming, b.age = b.returns - 1, false, 0
        b.vx, b.vy = (o.aimX or 1) * sp, (o.aimY or 0) * sp
        return
      end
      b.dead = true
      return
    end
    b.vx, b.vy = dx / d * sp, dy / d * sp
    b.gravity = 0
    b.hitSet = nil
  end
  local s = b.owner and b.owner.stats
  if s and (s.springWalls or 0) > 0 and not b.laser then
    local W = require("game.map").W
    local bounced = false
    if b.x < b.r and b.vx < 0 then b.x, b.vx, bounced = b.r, -b.vx, true end
    if b.x > W - b.r and b.vx > 0 then b.x, b.vx, bounced = W - b.r, -b.vx, true end
    if b.y < b.r and b.vy < 0 then b.y, b.vy, bounced = b.r, -b.vy, true end
    if bounced then b:bounce(game, nil) end
  end
end

-- A bullet is done (hit a wall for good, a player, or ran out): leftovers from cards.
function A.bulletImpact(b, game, hitPlayer)
  local o = b.owner
  if b.gravOrb then
    local s = o.stats
    table.insert(game.wells, { x = b.x, y = b.y, t = 2, max = 2, owner = o, radius = 220, strength = 2600 })
    addEffect(game, { type = "bomb", x = b.x, y = b.y, life = 2, max = 2, owner = o, damage = 40 * A.gadgetDamage(o), radius = 110 })
  end
  if b.remoteCharge then
    local follow = hitPlayer and not hitPlayer.dead and hitPlayer or nil
    for _, e in ipairs(game.effects or {}) do if e.type == "charge" and e.owner == o then e.life = 0 end end
    addEffect(game, { type = "charge", x = b.x, y = b.y, life = 12, max = 12, owner = o, follow = follow,
      damage = 80 + 40 * (o.stats.remoteCharge - 1), radius = 120, kind = o.slot or 0 })
  end
  if not hitPlayer and o and (o.stats.magnetMine or 0) > 0 and not b.isChild then
    local mine = 0
    for _, e in ipairs(game.effects or {}) do if e.type == "magnet" and e.owner == o then mine = mine + 1 end end
    if mine < 4 then
      addEffect(game, { type = "magnet", x = b.x, y = b.y, life = 2, max = 2, owner = o, damage = 25 * o.stats.magnetMine,
        radius = 160, kind = o.slot or 0 })
    end
  end
end

-- After a bullet hit a player and did its damage: Bee Swarm, Chain Dash, Body Bounce.
-- Returns true when the bullet carries on (Body Bounce).
function A.bulletLanded(b, p, game)
  local o = b.owner
  local s = o and o.stats
  if not s then return false end
  if (s.chainDash or 0) > 0 and not b.isChild then
    o.dashesLeft = math.max(o.dashesLeft, s.dashes)
    o.dashCd = 0
  end
  if (s.bees or 0) > 0 and not b.isBee then
    local alive = 0
    for _, q in ipairs(game.bullets) do if q.isBee and q.owner == o and not q.dead then alive = alive + 1 end end
    if alive < 6 + 4 * (s.bees - 1) then
      local a = love.math.random() * math.pi * 2
      local bee = b:spawnChild(game, p.x + math.cos(a) * (p.r + 14), p.y + math.sin(a) * (p.r + 14), a, 380,
        10 * A.gadgetDamage(o), p)
      bee.isBee, bee.homing, bee.gravity, bee.life, bee.r = true, 9, 0, 4, 3
    end
  end
  if (b.bodyBounces or 0) > 0 then
    b.hitSet = b.hitSet or {}
    b.hitSet[p] = true
    local best, bestD
    for _, e in ipairs(enemies(o)) do
      if not b.hitSet[e] and not e.dead then
        local d = dist2(e, p)
        if not bestD or d < bestD then best, bestD = e, d end
      end
    end
    if best then
      b.bodyBounces = b.bodyBounces - 1
      b.damage = b.damage * 0.7
      local sp = math.max(600, math.sqrt(b.vx * b.vx + b.vy * b.vy))
      local d = math.max(1, math.sqrt(bestD))
      b.vx, b.vy = (best.x - p.x) / d * sp, (best.y - p.y) / d * sp
      b.x, b.y = p.x + b.vx / sp * (p.r + b.r + 4), p.y + b.vy / sp * (p.r + b.r + 4)
      return true
    end
  end
  return false
end

---------------------------------------------------------------- every step (host)
function A.update(p, dt)
  local s, game = p.stats, p.game
  if p.dead or not game or not game.effects then return end
  A.updateStatus(p, dt)
  p.sinceDash = (p.sinceDash or 10) + dt
  if p.wasDashing and p.dashTimer <= 0 then A.dashEnded(p) end
  p.wasDashing = p.dashTimer > 0
  if p.dashTimer > 0 then A.dashing(p, dt) end
  if (p.comboT or 0) > 0 then p.comboT = p.comboT - dt; if p.comboT <= 0 then p.comboHits = 0 end end
  if (p.rageT or 0) > 0 then p.rageT = p.rageT - dt; if p.rageT <= 0 then p.rageStacks = 0 end end
  if (p.overdriveT or 0) > 0 then p.overdriveT = p.overdriveT - dt; if p.overdriveT <= 0 then p.overdriveStacks = 0 end end
  if (p.flipT or 0) > 0 then p.flipT = p.flipT - dt end
  if (p.lastLightT or 0) > 0 then p.lastLightT = p.lastLightT - dt end
  if (p.haymakerT or 0) > 0 then
    p.haymakerT = p.haymakerT - dt
    -- Haymaker: thrown into a wall, it hurts more.
    if p.wallDir ~= 0 and p.haymakerBy then
      p:hit(30 * p.haymakerBy.stats.haymaker, -p.wallDir, -0.3, 200, p.haymakerBy, "melee")
      fx.burst(p.x + p.wallDir * p.r, p.y, { 1, 1, 1 }, 14, 260, 3)
      p.haymakerT, p.haymakerBy = 0, nil
    end
  end
  if p.onGround then p.launchedBy = nil end
  if p.gunOut and p.gunOut.dead then p.gunOut = nil end
  -- Deflect Swing: a swing sends enemy bullets in front of you back as your own.
  if (s.deflectSwing or 0) > 0 and (p.swingTimer or 0) > 0 then
    local reach = p.r + s.meleeRange + 10
    local aim = math.atan2(p.aimY or 0, p.aimX or 1)
    for _, b in ipairs(game.bullets) do
      if not b.dead and not b.laser and b.owner ~= p and game:isEnemy(b.owner, p) then
        local dx, dy = b.x - p.x, b.y - p.y
        if dx * dx + dy * dy < reach * reach then
          local diff = math.abs((math.atan2(dy, dx) - aim + math.pi) % (math.pi * 2) - math.pi)
          if diff < 1.4 then
            local sp = math.sqrt(b.vx * b.vx + b.vy * b.vy)
            b.owner, b.color, b.age, b.bounced = p, p.color, 0, false
            b.vx, b.vy = (p.aimX or 1) * sp, (p.aimY or 0) * sp
            b.damage = b.damage * (1 + 0.25 * (s.deflectSwing - 1))
            fx.burst(b.x, b.y, { 1, 1, 1 }, 6, 200, 2)
            sfx.play("reflect", b.x, 0.6)
          end
        end
      end
    end
  end
  if (p.gravityBombT or 0) > 0 then p.gravityBombT = p.gravityBombT - dt / A.gadgetRate(p) end
  -- Reprise: the repeat shot.
  if p.repriseT then
    p.repriseT = p.repriseT - dt
    if p.repriseT <= 0 then
      p.repriseT = nil
      p:volley(false, 1)
    end
  end
  -- Mine Layer: a mine every few seconds while you're on the ground.
  if (s.mineDrop or 0) > 0 then
    p.mineT = (p.mineT or 0) - dt * A.gadgetRate(p)
    if p.mineT <= 0 and p.onGround then
      p.mineT = math.max(1.5, 4 - (s.mineDrop - 1))
      local alive = 0
      for _, b in ipairs(game.bullets) do if b.mine and b.owner == p and b.fromMineDrop and not b.dead then alive = alive + 1 end end
      if alive < 3 + (s.mineDrop - 1) then
        local Bullet = require "game.bullet"
        local m = Bullet.new(p, p.x, p.y + p.r + p.leg - 6, 0, 0)
        m.laser = false
        m:becomeMine()
        m.armTime = 1
        m.fromMineDrop = true
        m.damage = 40 * A.gadgetDamage(p)
        game:addBullet(m)
      end
    end
  end
  -- Shield Drones: each blocks one enemy bullet, then needs a few seconds.
  if (s.drones or 0) > 0 then
    p.droneCd = p.droneCd or {}
    for i = 1, s.drones do
      p.droneCd[i] = math.max(0, (p.droneCd[i] or 0) - dt * A.gadgetRate(p))
      if p.droneCd[i] <= 0 then
        local dx, dy = A.dronePos(p, i)
        for _, b in ipairs(game.bullets) do
          if b.owner ~= p and not b.dead and not b.laser and game:isEnemy(b.owner, p)
              and (b.x - dx) ^ 2 + (b.y - dy) ^ 2 < (10 + b.r) ^ 2 then
            b.dead = true
            p.droneCd[i] = 4
            fx.burst(dx, dy, { 0.7, 0.9, 1 }, 8, 160, 2)
            sfx.play("block", dx, 0.4, 1.5)
            break
          end
        end
      end
    end
  end
end

-- Where shield drone i circles (the drawing uses the same).
function A.dronePos(p, i)
  local n = math.max(1, p.stats.drones or 1)
  local a = (love.timer.getTime() * 2.2) + (i - 1) / n * math.pi * 2
  return p.x + math.cos(a) * (p.r + 30), p.y + math.sin(a) * (p.r + 30) * 0.6 - 6
end

-- Fire rate and speed from cards that depend on the moment.
function A.fireDelay(p, delay)
  local s = p.stats
  if (s.cornered or 0) > 0 and p.hp < s.maxHp * 0.5 then delay = delay / (1 + 0.25 * s.cornered) end
  if (s.lastBreath or 0) > 0 and p.hp < s.maxHp * 0.3 then delay = delay / (1.5 + 0.25 * (s.lastBreath - 1)) end
  if (p.overdriveStacks or 0) > 0 then delay = delay / (1 + 0.15 * p.overdriveStacks) end
  return delay
end

function A.moveSpeed(p, speed)
  local s = p.stats
  if (s.rush or 0) > 0 then
    local missing = math.max(0, 1 - p.hp / s.maxHp)
    speed = speed * (1 + 0.3 * s.rush * missing)
  end
  if (p.overdriveStacks or 0) > 0 then speed = speed * (1 + 0.15 * p.overdriveStacks) end
  if p.bunkered then speed = speed * 0.3 end
  if (p.freezeT or 0) > 0 then speed = 0 end
  return speed
end

---------------------------------------------------------------- arena effects (Objects.update)
-- Returns true when it handled e.
function A.updateEffect(world, e, dt)
  local t = e.type
  local o = e.owner
  if t == "ward" then
    for _, b in ipairs(world.bullets) do
      if not b.dead and b.owner ~= o and world:isEnemy(b.owner, o) and (b.x - e.x) ^ 2 + (b.y - e.y) ^ 2 < (e.radius + b.r) ^ 2 then
        b.dead = true
        fx.burst(b.x, b.y, { 0.8, 0.9, 1 }, 5, 140, 2)
      end
    end
    return true
  elseif t == "fire" then
    for _, p in ipairs(world.players) do
      if not p.dead and p ~= o and world:canHurt(o, p) and (p.x - e.x) ^ 2 + (p.y - e.y) ^ 2 < (e.radius + p.r) ^ 2 then
        if (p.burnT or 0) < 0.5 then A.burn(p, 16, 2, o) end
      end
    end
    return true
  elseif t == "trap" then
    for _, p in ipairs(world.players) do
      if not p.dead and p ~= o and world:canHurt(o, p) and (p.x - e.x) ^ 2 + (p.y - e.y) ^ 2 < (e.radius + p.r) ^ 2 then
        p:hit(30, 0, -1, 200, o, "spikes")
        p.slowTimer = math.max(p.slowTimer, 1.5)
        sfx.play("spike", e.x, 0.8)
        e.life = 0
        break
      end
    end
    return true
  elseif t == "icewall" then
    if e.life <= 0 or (e.hp or 1) <= 0 then
      Physics.removeEffectWall(world, e)
      fx.debris(e.x, e.y, { 0.7, 0.9, 1 }, 10, 5)
      sfx.play("glassBreak", e.x, 0.7)
      e.life = 0
    end
    return true
  elseif t == "totem" then
    return true
  elseif t == "turret" then
    e.fireT = (e.fireT or 0) - dt * A.gadgetRate(o)
    if e.fireT <= 0 and not o.dead then
      local target = world:nearestEnemy(o, e.x, e.y, true)
      if target then
        e.fireT = 1
        local Bullet = require "game.bullet"
        local s = o.stats
        local dx, dy = target.x - e.x, target.y - e.y
        local d = math.max(1, math.sqrt(dx * dx + dy * dy))
        local b = Bullet.new(o, e.x, e.y, dx / d * s.bulletSpeed, dy / d * s.bulletSpeed)
        b.damage = b.damage * 0.4 * A.gadgetDamage(o)
        b.poison, b.frost, b.explosion = (b.poison or 0) * 0.4, (b.frost or 0) * 0.4, (b.explosion or 0) * 0.4
        b.r, b.gravity, b.fromTurret = math.max(2.5, b.r * 0.7), 0, true
        world:addBullet(b)
        sfx.play("turretShot", e.x, 0.35)
      else
        e.fireT = 0.2
      end
    end
    return true
  elseif t == "charge" then
    return true
  elseif t == "magnet" then
    for _, p in ipairs(world.players) do
      if not p.dead and p ~= o and world:canHurt(o, p) then
        local dx, dy = e.x - p.x, e.y - p.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < e.radius and d > 1 then p.vx, p.vy = p.vx + dx / d * 900 * dt, p.vy + dy / d * 900 * dt end
      end
    end
    if e.life <= 0 then require("game.objects").explodeAt(world, e.x, e.y, 70, e.damage, o, o.color, o) end
    return true
  elseif t == "decoy" then
    -- Soaks enemy bullets; pops when an enemy touches it or time runs out.
    for _, b in ipairs(world.bullets) do
      if not b.dead and b.owner ~= o and world:isEnemy(b.owner, o) and (b.x - e.x) ^ 2 + (b.y - e.y) ^ 2 < (e.radius + b.r) ^ 2 then
        b.dead = true
      end
    end
    for _, p in ipairs(world.players) do
      if not p.dead and p ~= o and world:canHurt(o, p) and (p.x - e.x) ^ 2 + (p.y - e.y) ^ 2 < (e.radius + p.r + 6) ^ 2 then
        e.life = 0
      end
    end
    if e.life <= 0 then require("game.objects").explodeAt(world, e.x, e.y, 80, e.damage, o, o.color, o) end
    return true
  end
  return false
end

-- Remote Charge: block with a charge out to set it off. Returns true when it did (no block then).
function A.detonate(p)
  if (p.stats.remoteCharge or 0) <= 0 or not p.game.effects then return false end
  for _, e in ipairs(p.game.effects) do
    if e.type == "charge" and e.owner == p and e.life > 0 then
      e.life = 0
      require("game.objects").explodeAt(p.game, e.x, e.y, e.radius, e.damage, p, p.color, p)
      return true
    end
  end
  return false
end

-- Totem: reloading near your totem is faster.
function A.reloadRate(p)
  if (p.stats.totem or 0) <= 0 or not p.game.effects then return 1 end
  for _, e in ipairs(p.game.effects) do
    if e.type == "totem" and e.owner == p and (e.x - p.x) ^ 2 + (e.y - p.y) ^ 2 < e.radius * e.radius then return 1.5 end
  end
  return 1
end

-- Ice Wall: bullets that hit it chip at it.
function A.wallHit(e, damage)
  e.hp = (e.hp or 0) - damage
  e.hitFlash = 0.1
end

-- Final Gambit: dying blows up around you, once a round.
function A.died(p)
  local s = p.stats
  if (s.finalGambit or 0) > 0 and not p.finalGambitUsed then
    p.finalGambitUsed = true
    local dmg = 100 + 50 * (s.finalGambit - 1)
    fx.explosion(p.x, p.y, 250, p.color)
    sfx.play("explosion", p.x, 1, 0.9)
    for _, e in ipairs(enemies(p)) do
      if dist2(e, p) < 250 * 250 and sees(p.game, p, e) then e:hit(dmg, e.x - p.x, e.y - p.y, 900, p, "explosion") end
    end
  end
  -- Wager: a kill for whoever finished you.
  local k = p.lastAttacker
  if k and k ~= p and k.stats and (k.stats.wager or 0) > 0 then k.wagerWon = true end
  if p.game and p.game.effects then
    for _, e in ipairs(p.game.effects) do
      if e.owner == p and (e.type == "charge" or e.type == "turret" or e.type == "totem") then e.life = 0 end
    end
  end
end

-- Plague: every couple of seconds poison jumps between enemies (run once per world step).
function A.worldStep(world, dt)
  world.plagueT = (world.plagueT or 2) - dt
  if world.plagueT > 0 then return end
  world.plagueT = 2
  for _, p in ipairs(world.players) do
    local by = p.lastAttacker
    if not p.dead and p.poisonTimer > 0 and by and by.stats and (by.stats.plague or 0) > 0 then
      local reach = 200 + 100 * (by.stats.plague - 1)
      local best, bestD
      for _, e in ipairs(world:enemiesOf(by)) do
        if e ~= p and not e.dead and e.poisonTimer <= 0 then
          local d = dist2(e, p)
          if d < reach * reach and (not bestD or d < bestD) then best, bestD = e, d end
        end
      end
      if best then
        best:poisonFor(p.poisonDps * p.poisonTimer * 0.75, 3)
        best.lastAttacker = by
        fx.spray(p.x, p.y, math.atan2(best.y - p.y, best.x - p.x), 0.3, { 0.5, 0.9, 0.3 }, 8, 420, 2.5, 0)
      end
    end
  end
end

return A
