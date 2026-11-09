local Map = require "game.map"
local Physics = require "game.physics"
local fx = require "gfx.fx"
local Bullet = require "game.bullet"
local sfx = require "gfx.sfx"
local Triggers = require "game.triggers"
local CardData = require "game.carddata"
local Cosmetics = require "core.cosmetics"
local Body = require "game.body"

local Player = {}
Player.__index = Player

-- Movement tuning (Celeste / Hollow Knight style). Cards scale speed, jump, gravityMul and airJumps.
local MOVE = {
  groundAccel = 6000, groundDecel = 7000, turnMul = 1.5,
  airAccel = 3900, airDecel = 2600,
  overDecelGround = 2400, overDecelAir = 900, -- above max speed (knockback, dash, launches)
  lockAccel = 600,                            -- while knocked back
  gravity = 2400, apexGravityMul = 0.5, apexThreshold = 90, fallGravityMul = 1.5,
  maxFall = 900, fastFallMax = 1400, fastFallMul = 2,
  jumpCut = 0.45, coyote = 0.1, jumpBuffer = 0.12,
  wallSlide = 160, wallCoyote = 0.08,
  cornerCeiling = 8, cornerLedge = 6,
  dashTime = 0.14, dashKeep = 0.6, dropTime = 0.25,
}
Player.MOVE = MOVE

-- Wall jump: upward speed (fraction of jump), push away from the wall (fraction of move
-- speed) and how long steering is weakened afterwards.
Player.WALL_JUMP = { up = 0.95, push = 0.65, lock = 0.12 }

-- Melee: a tap is a light swing, holding charges a heavy swing with a lunge.
local MELEE = {
  lightThreshold = 0.15, -- held longer than this = heavy
  overHold = 0.35,       -- a full charge releases by itself after this extra hold
  cone = math.rad(75),
  lightStun = 0.25, heavyStunMin = 0.25, heavyStunMax = 0.8,
  lungeTime = 0.12, swingShow = 0.16, chargeSpeedMul = 0.85,
}
Player.MELEE = MELEE

-- Arena edges (left, right, bottom): damage and a launch back in. The top is open.
-- blockBounce: blocking at an edge throws you back in harder (enough to recover from the bottom).
local EDGE = { damage = 30, launch = 900, launchUp = 650, bottomLaunch = 1150, cooldown = 0.3, blockBounce = 1.3,
  intoMul = 0.5 } -- holding your movement key into it halves the launch
Player.EDGE = EDGE

local ORB_DISTANCE = 55
local ORB_SIZE = 9
local SHOCKWAVE_RADIUS = 170
local STATIC_RADIUS = 130
local SENTRY_DELAY = 0.9
local ARENA_W, ARENA_H = Map.W, Map.H

local Stats = require "game.stats"
local BASE = Stats.BASE -- base stats; cards change copies of these (see game/stats.lua)

Player.stasisRadius = Bullet.stasisRadius

local function approach(v, target, amount)
  if v < target then return math.min(v + amount, target) end
  return math.max(v - amount, target)
end

-- `input` is an input state table (see input.lua) that this player reads every frame.
function Player.new(id, color, input)
  local p = setmetatable({ id = id, color = color, input = input, cards = {}, score = 0, r = 20, leg = 14 }, Player)
  p:resetStats()
  p:recompute()
  return p
end

-- Rebuild stats from the base values plus every card collected.
function Player:recompute()
  local s = {}
  for k, v in pairs(BASE) do s[k] = v end
  -- Each copy applies again (copyIndex lets cards treat the first copy differently),
  -- and each copy adds its trigger rules again.
  local copies = {}
  self.triggerList = {}
  for _, card in ipairs(self.cards) do
    copies[card] = (copies[card] or 0) + 1
    card.apply(s, copies[card])
    for _, rule in ipairs(card.triggers or {}) do
      self.triggerList[#self.triggerList + 1] = { rule = rule, ready = 0, t = 0 }
    end
  end
  s.maxHp = math.max(10, s.maxHp)
  s.fireDelay = math.max(0.06, s.fireDelay)
  s.reloadTime = math.max(0.3, s.reloadTime)
  s.blockCooldown = math.max(1, s.blockCooldown)
  s.ammo = math.max(1, math.floor(s.ammo + 0.5))
  s.bullets = math.max(1, math.floor(s.bullets + 0.5))
  s.crit = math.min(0.9, s.crit)
  s.orbs = math.min(8, s.orbs)
  s.radius = math.max(10, s.radius)
  self.stats = s
  self.r = s.radius
  self.leg = self.r * 0.7 -- the body rides this far above the ground on its legs
end

-- Match statistics (scoreboard): kills, deaths, damage dealt, shots, bullet hits, blocks, melee hits.
function Player:resetStats()
  self.st = { kills = 0, deaths = 0, dmg = 0, shots = 0, hits = 0, blocks = 0, melee = 0 }
end

-- Fire this player's trigger rules for an event. ctx: { target = player } or { x, y }.
function Player:trigger(when, ctx)
  if self.inTrigger or self.dead or not self.game or not self.triggerList then return end
  local now = self.game.time or 0
  for _, inst in ipairs(self.triggerList) do
    local rule = inst.rule
    if rule.when == when and now >= inst.ready and love.math.random() < (rule.chance or 1) then
      inst.ready = now + (rule.cd or 0)
      self.inTrigger = true
      Triggers.run(self, rule, ctx)
      self.inTrigger = false
    end
  end
end

function Player:addCard(card)
  table.insert(self.cards, card)
  self:recompute()
end

function Player:spawn(x, y, facing, game)
  self.game = game
  -- Maps made before characters stood on legs can have spawns too close to the ground.
  if game and game.physics then
    for _ = 1, 10 do
      if self:freeAt(x, y) then break end
      y = y - 6
    end
  end
  self.spawnX, self.spawnY = x, y
  self.x, self.y = x, y
  self.vx, self.vy = 0, 0
  self.facing = facing
  self.aimX, self.aimY = facing, 0
  self.hp = self.stats.maxHp
  self.dead = false
  self.ammo = self.stats.ammo
  self.reloadTimer = 0
  self.fireTimer = 0
  self.sinceShot = 0
  self.blockTimer = 0
  self.blockCd = 0
  self.onGround = false
  self.coyote = 0
  self.wallDir = 0
  self.jumpsLeft = self.stats.airJumps
  self.controlLock = 0
  self.poisonTimer, self.poisonDps = 0, 0
  self.decay = {}
  self.hitFlash = 0
  self.livesLeft = self.stats.lives
  self.invuln = 0
  self.slowTimer = 0
  self.cloakTimer = 0
  self.empowered = false
  self.empowerShots = 0
  self.spin = 0
  self.burstLeft, self.burstTimer = 0, 0
  self.orbAngle = 0
  self.orbHit = {}
  self.shield = self.stats.shieldMax
  self.lastStandLeft = self.stats.lastStand
  self.spiteReady = false
  self.quickdrawReady = false
  self.comboCount, self.comboTimer = 0, 0
  self.sprintTimer = 0
  self.freeAmmo = 0
  self.warpTimer = 0
  self.swapCd = 0
  self.sentryTimer = 1
  self.staticTimer = 0
  self.seenJump = self.input.jumpCount
  self.seenBlock = self.input.blockCount
  self.seenDash = self.input.dashCount or 0
  self.seenMelee = self.input.meleeCount or 0
  self.jumpWasHeld = self.input.jumpHeld
  self.jumpBuffer = 0
  self.jumping = false       -- rising from our own jump (release cuts it short)
  self.wallCoyote, self.lastWallDir = 0, 0
  self.groundOneway = false  -- standing on a one-way platform
  self.dropTimer = 0         -- falling through one-way platforms
  self.dashesLeft = self.stats.dashes
  self.dashTimer, self.dashCd = 0, 0
  self.dashX, self.dashY = 0, 0
  self.edgeCd = 0
  self.stunTimer = 0
  self.meleeCd = 0
  self.charging, self.meleeCharge = false, 0
  self.lungeTimer, self.lungePower = 0, 0
  self.lungeHit = nil
  self.swingTimer, self.swingHeavy, self.swingPower = 0, false, 0
  self.lastAttacker = nil
  self.boostSpeed, self.boostSpeedTimer, self.boostDamage, self.boostShots = 0, 0, 0, 0
  self.roundStartPending = true
  for _, inst in ipairs(self.triggerList or {}) do inst.ready, inst.t = 0, 0 end
end

function Player:isBlocking()
  return self.blockTimer > 0
end

-- Where the Sentry turret hovers (behind the player's shoulder).
function Player:sentryPos()
  return self.x - self.facing * (self.r + 16), self.y - self.r - 14
end

-- Adrenaline is active below half HP.
function Player:adrenalineActive()
  return self.stats.adrenaline > 0 and self.hp < self.stats.maxHp * 0.5
end

function Player:orbPos(i)
  local a = self.orbAngle + (i - 1) / self.stats.orbs * math.pi * 2
  return self.x + math.cos(a) * ORB_DISTANCE, self.y + math.sin(a) * ORB_DISTANCE
end

function Player:update(dt, frozen)
  if self.dead then return end
  local s, game = self.stats, self.game

  self.fireTimer = math.max(0, self.fireTimer - dt)
  self.blockTimer = math.max(0, self.blockTimer - dt)
  self.blockCd = math.max(0, self.blockCd - dt)
  self.controlLock = math.max(0, self.controlLock - dt)
  self.hitFlash = math.max(0, self.hitFlash - dt)
  self.shotT = math.max(0, (self.shotT or 0) - dt)
  self.invuln = math.max(0, self.invuln - dt)
  self.slowTimer = math.max(0, self.slowTimer - dt)
  self.cloakTimer = math.max(0, self.cloakTimer - dt)
  self.sprintTimer = math.max(0, self.sprintTimer - dt)
  self.freeAmmo = math.max(0, self.freeAmmo - dt)
  self.warpTimer = math.max(0, self.warpTimer - dt)
  self.swapCd = math.max(0, self.swapCd - dt)
  if self.comboTimer > 0 then
    self.comboTimer = self.comboTimer - dt
    if self.comboTimer <= 0 then self.comboCount = 0 end
  end
  self.sinceShot = self.sinceShot + dt

  -- Reload when empty, or top up after a short pause in firing.
  if self.reloadTimer > 0 then
    self.reloadTimer = self.reloadTimer - dt
    if self.reloadTimer <= 0 then
      self.reloadTimer = 0
      self.ammo = s.ammo
      self:emitSound("reloaded", 0.7)
      self:reloaded()
    end
  elseif self.ammo < s.ammo and self.sinceShot > 1.0 then
    self.reloadTimer = s.reloadTime
    self:emitSound("reload", 0.6)
  end

  -- Damage over time: poison and Decay
  if self.poisonTimer > 0 then
    self.poisonTimer = self.poisonTimer - dt
    self.hp = self.hp - self.poisonDps * dt
    if love.math.random() < dt * 12 then
      fx.burst(self.x, self.y, { 0.4, 0.9, 0.2 }, 1, 60, 3)
    end
  end
  for i = #self.decay, 1, -1 do
    local d = self.decay[i]
    local amount = math.min(d.remaining, d.rate * dt)
    d.remaining = d.remaining - amount
    self.hp = self.hp - amount
    if d.remaining <= 0 then table.remove(self.decay, i) end
  end
  if s.regen > 0 and self.hp > 0 then self.hp = math.min(s.maxHp, self.hp + s.regen * dt) end
  if self.hp <= 0 then
    self:die()
    if self.dead then return end
  end

  local inp = self.input
  local stunned = self.stunTimer > 0
  self.stunTimer = math.max(0, self.stunTimer - dt)
  self.dashCd = math.max(0, self.dashCd - dt)
  self.meleeCd = math.max(0, self.meleeCd - dt)
  self.edgeCd = math.max(0, self.edgeCd - dt)
  self.dropTimer = math.max(0, self.dropTimer - dt)
  self.swingTimer = math.max(0, self.swingTimer - dt)
  self.jumpBuffer = math.max(0, self.jumpBuffer - dt)

  -- Jump/block/dash/melee are edge-triggered from press counters, so no press is ever lost.
  -- While frozen (countdown) or stunned, presses are swallowed.
  local acting = not frozen and not stunned
  if not acting then
    self.seenJump, self.seenBlock = inp.jumpCount, inp.blockCount
    self.seenDash, self.seenMelee = inp.dashCount or 0, inp.meleeCount or 0
    self.charging = false
  else
    if inp.jumpCount ~= self.seenJump then
      self.seenJump = inp.jumpCount
      self:jumpPressed()
    end
    if inp.blockCount ~= self.seenBlock then
      self.seenBlock = inp.blockCount
      self:blockPressed()
    end
    if (inp.dashCount or 0) ~= self.seenDash then
      self.seenDash = inp.dashCount or 0
      self:dashPressed()
    end
    if (inp.meleeCount or 0) ~= self.seenMelee then
      self.seenMelee = inp.meleeCount or 0
      if self.meleeCd <= 0 and not self.charging and self.lungeTimer <= 0 then
        self.charging, self.meleeCharge = true, 0
      end
    end
    if self.jumpWasHeld and not inp.jumpHeld then self:jumpReleased() end
  end
  self.jumpWasHeld = inp.jumpHeld

  if acting then
    if self.roundStartPending then
      self.roundStartPending = false
      self:trigger("roundStart")
    end
    for _, inst in ipairs(self.triggerList or {}) do
      if inst.rule.when == "interval" then
        inst.t = inst.t + dt
        if inst.t >= ((inst.rule.params and inst.rule.params.every) or 5) then
          inst.t = 0
          if not self.inTrigger then
            self.inTrigger = true
            Triggers.run(self, inst.rule)
            self.inTrigger = false
          end
        end
      end
    end
  end
  self.boostSpeedTimer = math.max(0, (self.boostSpeedTimer or 0) - dt)
  self.riposteTimer = math.max(0, (self.riposteTimer or 0) - dt)
  if (self.boostShots or 0) > 0 then
    self.boostTimer = (self.boostTimer or math.huge) - dt
    if self.boostTimer <= 0 then self.boostShots, self.boostDamage = 0, 0 end
  end

  -- Melee charge: release (or overholding a full charge) swings.
  if self.charging then
    local before = self.meleeCharge
    self.meleeCharge = self.meleeCharge + dt
    if before < MELEE.lightThreshold and self.meleeCharge >= MELEE.lightThreshold then self:emitSound("meleeCharge") end
    if not inp.meleeHeld or self.meleeCharge >= MELEE.lightThreshold + s.heavyCharge + MELEE.overHold then
      self:meleeRelease()
    end
  end

  -- Horizontal movement
  local dir = 0
  if acting then
    if inp.left then dir = dir - 1 end
    if inp.right then dir = dir + 1 end
  end
  if dir ~= 0 and self.controlLock <= 0 and not inp.aim then self.facing = dir end
  local speed = s.speed * (self.slowTimer > 0 and 0.5 or 1)
  if self.sprintTimer > 0 then speed = speed * (1 + 0.4 * s.sprintBlock) end
  if self:adrenalineActive() then speed = speed * (1 + 0.2 * s.adrenaline) end
  if self.charging and self.meleeCharge > MELEE.lightThreshold then speed = speed * MELEE.chargeSpeedMul end
  if (self.boostSpeedTimer or 0) > 0 then speed = speed * (1 + self.boostSpeed) end

  self.forceX, self.gravScale, self.groundMu = 0, 0, 0
  if self.dashTimer > 0 or self.lungeTimer > 0 then
    -- Dashing / lunging: fixed velocity, no gravity.
    if self.dashTimer > 0 then
      self.dashTimer = self.dashTimer - dt
      self.vx, self.vy = self.dashX, self.dashY
      if self.dashTimer <= 0 then
        self.vx, self.vy = self.vx * MOVE.dashKeep, self.vy * MOVE.dashKeep
      end
    else
      self.lungeTimer = self.lungeTimer - dt
      self.vx, self.vy = self.dashX, self.dashY
      self:meleeHitCheck()
      if self.lungeTimer <= 0 then
        self.vx, self.vy = self.preLungeVx or self.vx * 0.35, self.vy * 0.35
        self:meleeHitCheck(true)
      end
    end
  else
    self:runPhysics(dt, dir, speed, acting)
  end

  -- Enemy black holes pull you in
  for _, w in ipairs(game.wells) do
    if w.owner ~= self then
      local dx, dy = w.x - self.x, w.y - self.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d > 1 and d < w.radius then
        local f = w.strength * (1 - d / w.radius) * dt
        self.vx = self.vx + dx / d * f
        self.vy = self.vy + dy / d * f
        self.controlLock = math.max(self.controlLock, 0.05)
      end
    end
  end

  -- Box2D moves the body now; Player:afterStep picks up from where it ended up.
  self.stepState = { acting = acting, frozen = frozen, wasGround = self.onGround, fallSpeed = self.vy }
  Physics.pushPlayer(self)
end

-- The second half of a frame, after the physics step.
function Player:afterStep(dt)
  local st = self.stepState
  self.stepState = nil
  if self.dead or not st then return end
  local s, game, inp = self.stats, self.game, self.input
  local acting, frozen, wasGround, fallSpeed = st.acting, st.frozen, st.wasGround, st.fallSpeed
  Physics.pullPlayer(self)
  self:checkEdges()
  if self.dead then return end

  if self.onGround then
    self.coyote = MOVE.coyote
    self.jumping = false
  else
    self.coyote = math.max(0, self.coyote - dt)
  end
  if self.wallDir ~= 0 then
    self.wallCoyote, self.lastWallDir = MOVE.wallCoyote, self.wallDir
  else
    self.wallCoyote = math.max(0, self.wallCoyote - dt)
  end
  if self.onGround or self.wallDir ~= 0 then
    self.jumpsLeft = s.airJumps
    if self.dashTimer <= 0 and self.dashesLeft < s.dashes then self.dashesLeft = s.dashes end
  end
  if self.onGround and not wasGround then self:landed(fallSpeed) end
  self.landSquash = math.max(0, (self.landSquash or 0) - dt * 2.5)

  -- Footstep dust, wall-slide sparks, dash afterimages, refilled dash.
  if self.onGround and math.abs(self.vx) > 250 and love.math.random() < dt * 7 then
    fx.spray(self.x, self.y + self.r + self.leg, self.vx > 0 and math.pi * 1.15 or -math.pi * 0.15, 0.5,
      { 0.7, 0.7, 0.75 }, 2, 90, 2.5, 0.15)
  end
  if self.wallDir ~= 0 and not self.onGround and self.vy >= MOVE.wallSlide - 1 and love.math.random() < dt * 28 then
    fx.spray(self.x + self.wallDir * self.r, self.y + self.r * 0.5, self.wallDir > 0 and math.pi or 0, 1.2,
      { 1, 0.85, 0.5 }, 1, 120, 2, 0.6)
  end
  if self.dashTimer > 0 or self.lungeTimer > 0 then
    self.ghostTimer = (self.ghostTimer or 0) - dt
    if self.ghostTimer <= 0 then
      self.ghostTimer = 0.03
      fx.ghost(self.x, self.y, self.r, self.color)
    end
  end
  if self.dashesLeft > 0 and self.hadNoDash and self.dashCd <= 0 then
    self.hadNoDash = false
    fx.ring(self.x, self.y, self.r + 8, self.color)
    self:emitSound("dashReady", 0.6)
  end
  if self.dashesLeft == 0 then self.hadNoDash = true end
  -- A buffered jump fires as soon as it can.
  if self.jumpBuffer > 0 and acting and (self.onGround or self.wallDir ~= 0) then self:jumpPressed(true) end

  if inp.aim then
    -- Mouse aim (online): free angle, facing follows the aim.
    self.aimX, self.aimY = math.cos(inp.aim), math.sin(inp.aim)
    if math.abs(self.aimX) > 0.05 and self.controlLock <= 0 then
      self.facing = self.aimX > 0 and 1 or -1
    end
  else
    -- Keyboard aim: facing direction, tilted 45 degrees up or down while holding up/down.
    local angle = 0
    if not frozen then
      if inp.up and not inp.down then angle = -math.pi / 4 elseif inp.down and not inp.up then angle = math.pi / 4 end
    end
    self.aimX, self.aimY = math.cos(angle) * self.facing, math.sin(angle)
  end

  local holding = acting and inp.fire
  if holding then self:tryFire() end
  -- Overclock copies make the ramp drain more slowly.
  if not holding or self.ammo == 0 then self.spin = math.max(0, self.spin - dt * 1.5 / math.max(1, s.spinup)) end

  -- Echo shots
  if self.burstLeft > 0 then
    self.burstTimer = self.burstTimer - dt
    if self.burstTimer <= 0 then
      self.burstLeft = self.burstLeft - 1
      self.burstTimer = 0.09
      self:volley(false)
    end
  end

  if s.orbs > 0 then self:updateOrbs(dt) end
  if not frozen then
    if s.static > 0 then self:updateStatic(dt) end
    if s.sentry > 0 then self:updateSentry(dt) end
  end

end

-- Running, gravity and wall sliding (not while dashing).
function Player:runPhysics(dt, dir, speed, acting)
  local s, inp = self.stats, self.input
  local belt = self.beltVx or 0 -- standing on a conveyor
  self.beltVx = nil
  local target = dir * speed + belt
  local accel
  if self.controlLock > 0 then
    accel = MOVE.lockAccel
  elseif math.abs(self.vx - belt) > speed and (dir == 0 or (self.vx > 0) == (dir > 0)) then
    accel = self.onGround and MOVE.overDecelGround or MOVE.overDecelAir -- keep momentum from launches
    target = belt + (dir == 0 and 0 or (self.vx > 0 and speed or -speed))
  elseif dir == 0 then
    accel = self.onGround and MOVE.groundDecel or MOVE.airDecel
  else
    accel = self.onGround and MOVE.groundAccel or MOVE.airAccel
    if self.vx ~= 0 and (self.vx > 0) ~= (dir > 0) then accel = accel * MOVE.turnMul end
  end
  -- Shoving something heavy takes more of your effort.
  local effort = accel
  if self.pushing and self.pushing.mass then effort = accel / (1 + self.pushing.mass * 1.2) end

  -- Gravity: light near the apex while jump is held, heavier when falling.
  local g = MOVE.gravity * s.gravityMul
  if math.abs(self.vy) < MOVE.apexThreshold and inp.jumpHeld and acting then
    g = g * MOVE.apexGravityMul
  elseif self.vy > 0 then
    g = g * MOVE.fallGravityMul
  end
  local maxFall = MOVE.maxFall
  local fastFall = acting and inp.down and not self.onGround and self.vy > -MOVE.apexThreshold
  if fastFall then
    g = g * MOVE.fastFallMul
    maxFall = MOVE.fastFallMax
  end
  -- Gravity comes from the body's gravity scale; capping the fall speed just lowers the scale.
  local nextVy
  if self.vy < maxFall then
    nextVy = math.min(self.vy + g * dt, maxFall)
  else
    nextVy = approach(self.vy, maxFall, g * dt) -- launched faster than the clamp: ease back
  end
  if self.vy > 0 then self.jumping = false end
  if not self.onGround and self.wallDir ~= 0 and dir == self.wallDir and nextVy > MOVE.wallSlide then
    nextVy = MOVE.wallSlide
  end
  local gEffective = (nextVy - self.vy) / dt
  self.gravScale = gEffective / Physics.GRAVITY

  -- Walking is a force; letting go on the ground is friction against what you stand on.
  if self.onGround and dir == 0 and belt == 0 then
    self.forceX = 0
    self.groundMu = accel / math.max(200, g)
  else
    self.forceX = Physics.PLAYER_MASS * (approach(self.vx, target, effort * dt) - self.vx) / dt
    self.groundMu = 0
  end
end

-- Just touched the ground. fallSpeed: vertical speed just before landing.
function Player:landed(fallSpeed)
  if fallSpeed > 250 then
    local k = math.min(1, (fallSpeed - 250) / 900)
    fx.spray(self.x - self.r * 0.6, self.y + self.r + self.leg, math.pi, 0.6, { 0.75, 0.75, 0.8 }, 2 + math.floor(4 * k), 160 + 200 * k, 3, 0.2)
    fx.spray(self.x + self.r * 0.6, self.y + self.r + self.leg, 0, 0.6, { 0.75, 0.75, 0.8 }, 2 + math.floor(4 * k), 160 + 200 * k, 3, 0.2)
    self:emitSound("land", 0.35 + 0.65 * k, 1.1 - 0.3 * k)
    if fallSpeed > 600 then
      self.landImpact = math.min(1.5, (fallSpeed - 600) / 900) -- landing shockwaves hit harder from higher up
      self:trigger("land")
      self.landImpact = nil
    end
  end
  self.landSquash = math.min(0.35, fallSpeed / 3000)
end

-- Left, right and bottom edges hurt and launch you back in; blocking makes it a free bounce.
function Player:checkEdges()
  self:checkBounds(0, 0, ARENA_W, ARENA_H, false)
end

-- Damaging bounds (arena edges, the sudden-death barrier). top: the top edge counts too.
-- damageMul: scales the damage (the barrier's strength setting).
function Player:checkBounds(x0, y0, x1, y1, top, damageMul)
  local r = self.r
  local side
  if self.x - r < x0 then
    self.x = x0 + r
    side = "left"
  elseif self.x + r > x1 then
    self.x = x1 - r
    side = "right"
  elseif self.y + r + self.leg > y1 then
    self.y = y1 - r - self.leg
    side = "bottom"
  elseif top and self.y - r < y0 then
    self.y = y0 + r
    side = "top"
  end
  if not side then return end
  local L = (self.stats.edgeLaunch or 1) * (self:isBlocking() and EDGE.blockBounce or 1)
  local inp = self.input
  if inp and not self:isBlocking() and ((side == "left" and inp.left) or (side == "right" and inp.right)
      or (side == "bottom" and inp.down) or (side == "top" and (inp.up or inp.jumpHeld))) then
    L = L * EDGE.intoMul
  end
  if side == "left" then
    self.vx, self.vy = EDGE.launch * L, math.min(self.vy, -EDGE.launchUp * L)
  elseif side == "right" then
    self.vx, self.vy = -EDGE.launch * L, math.min(self.vy, -EDGE.launchUp * L)
  elseif side == "bottom" then
    self.vy = -EDGE.bottomLaunch * L
  else
    self.vy = EDGE.launchUp * L
  end
  self.controlLock = math.max(self.controlLock, 0.15)
  self.dashTimer, self.lungeTimer = 0, 0
  self.jumping = false
  if self.edgeCd > 0 then return end
  self.edgeCd = EDGE.cooldown
  local ex = side == "left" and x0 or side == "right" and x1 or self.x
  local ey = side == "bottom" and y1 or side == "top" and y0 or self.y
  if self:isBlocking() then
    fx.burst(ex, ey, { 1, 1, 1 }, 10, 260, 3)
    self:blocked()
    self:emitSound("edgeBlock")
    return
  end
  fx.burst(ex, ey, { 1, 0.25, 0.2 }, 14, 320, 4)
  self:emitSound("edge")
  self:hit(EDGE.damage * (self.stats.edgeTaken or 1) * (damageMul or 1), 0, 0, 0, nil, "edge")
end

function Player:emitSound(name, volume, pitch)
  sfx.play(name, self.x, volume, pitch)
end

function Player:updateOrbs(dt)
  local game = self.game
  self.orbAngle = self.orbAngle + dt * 3
  for i = 1, self.stats.orbs do
    local ox, oy = self:orbPos(i)
    for _, b in ipairs(game.bullets) do
      if b.owner ~= self and not b.dead and not b.laser then
        local dx, dy = b.x - ox, b.y - oy
        local reach = ORB_SIZE + b.r
        if dx * dx + dy * dy < reach * reach then
          b.dead = true
          fx.burst(ox, oy, { 1, 1, 1 }, 5, 150, 2)
        end
      end
    end
    self.orbHit[i] = (self.orbHit[i] or 0) - dt
    if self.orbHit[i] <= 0 then
      for _, enemy in ipairs(game:enemiesOf(self)) do
        local dx, dy = enemy.x - ox, enemy.y - oy
        local reach = ORB_SIZE + enemy.r
        if dx * dx + dy * dy < reach * reach then
          enemy:hit(10, enemy.x - self.x, enemy.y - self.y, 300, self)
          self.orbHit[i] = 0.5
          break
        end
      end
    end
  end
end

-- Static Field: enemies close by take damage over time (pulses a ring so it's visible online).
function Player:updateStatic(dt)
  local s = self.stats
  self.staticTimer = self.staticTimer - dt
  if self.staticTimer <= 0 then
    self.staticTimer = 0.8
    fx.ring(self.x, self.y, STATIC_RADIUS, { 0.55, 0.8, 1 })
  end
  for _, e in ipairs(self.game:enemiesOf(self)) do
    local dx, dy = e.x - self.x, e.y - self.y
    local reach = STATIC_RADIUS + e.r
    if dx * dx + dy * dy < reach * reach and e.invuln <= 0 and not e:isBlocking() then
      e.hp = e.hp - s.static * dt
      if s.frost > 0 then e.slowTimer = math.max(e.slowTimer, s.frost) end
      if e.hp <= 0 then e:die() end
    end
  end
end

-- Sentry: a turret that shoots the nearest visible enemy.
function Player:updateSentry(dt)
  local s, game = self.stats, self.game
  self.sentryTimer = self.sentryTimer - dt
  if self.sentryTimer > 0 then return end
  local sx, sy = self:sentryPos()
  local target = game:nearestEnemy(self, sx, sy, true)
  if not target then
    self.sentryTimer = 0.2
    return
  end
  self.sentryTimer = SENTRY_DELAY / (1 + 0.5 * (s.sentry - 1))
  local dx, dy = target.x - sx, target.y - sy
  local d = math.max(1, math.sqrt(dx * dx + dy * dy))
  local b = Bullet.new(self, sx, sy, dx / d * s.bulletSpeed, dy / d * s.bulletSpeed)
  b.damage = b.damage * 0.4
  b.r = math.max(2.5, b.r * 0.7)
  b.gravity = 0
  game:addBullet(b)
  fx.burst(sx, sy, self.color, 3, 100, 2)
end

-- A reload just finished.
function Player:reloaded()
  local s = self.stats
  self:trigger("reload")
  if s.quickdraw > 0 then self.quickdrawReady = true end
  for i = 1, s.reloadNova do
    self:spawnBullet(i / s.reloadNova * math.pi * 2, 0.8, false)
  end
end

-- Is the player's box at (x, y) free of solid rects? One-way platforms don't count.
-- Would the player's body fit at (x, y)? exclude: an object to ignore.
function Player:freeAt(x, y, exclude)
  local r, leg = self.r, self.leg
  return Physics.hit(self.game, x - r, y - r, r * 2, r * 2 + leg, exclude) == nil
end

-- fromBuffer: a buffered press retried on landing / touching a wall.
function Player:jumpPressed(fromBuffer)
  if self.dead then return end
  local s, inp = self.stats, self.input
  self.jumpBuffer = 0
  -- Down + Jump on a one-way platform drops through it.
  if inp.down and self.onGround and self.groundOneway then
    self.dropTimer = MOVE.dropTime
    self.onGround = false
    self.coyote = 0
    self.y = self.y + 2
    return
  end
  if self.onGround or self.coyote > 0 then
    self.vy = -s.jump
    self.coyote = 0
    self.onGround = false
    self.jumping = true
    self.dashTimer = 0
    fx.burst(self.x, self.y + self.r + self.leg, { 0.8, 0.8, 0.85 }, 5, 110, 3)
    self:emitSound("jump")
    fx.spray(self.x, self.y + self.r + self.leg, math.pi / 2, 2.6, { 0.75, 0.75, 0.8 }, 6, 150, 2.5, 0.15)
    self:trigger("jump")
  elseif self.wallDir ~= 0 or self.wallCoyote > 0 then
    local wall = self.wallDir ~= 0 and self.wallDir or self.lastWallDir
    local wj = Player.WALL_JUMP
    self.vy = -s.jump * wj.up
    self.vx = -wall * s.speed * wj.push
    self.facing = -wall
    self.controlLock = wj.lock
    self.wallCoyote = 0
    self.jumping = true
    self.dashTimer = 0
    fx.burst(self.x + wall * self.r, self.y, { 0.8, 0.8, 0.8 }, 5, 120, 3)
    self:emitSound("wallJump")
    fx.spray(self.x, self.y, 0, 6.2, { 1, 0.85, 0.5 }, 7, 170, 2.5, 0.3)
    self:trigger("wallJump")
  elseif self.jumpsLeft > 0 and not fromBuffer then
    self.jumpsLeft = self.jumpsLeft - 1
    self.vy = -s.jump * 0.9
    self.jumping = true
    self.dashTimer = 0
    fx.burst(self.x, self.y + self.r + self.leg, self.color, 6, 150, 3)
    self:emitSound("doubleJump")
    fx.ring(self.x, self.y + self.r + self.leg, 36, self.color)
    self:trigger("jump")
  elseif not fromBuffer then
    self.jumpBuffer = MOVE.jumpBuffer -- try again on landing
  end
end

-- Releasing jump early cuts the jump short (variable jump height).
function Player:jumpReleased()
  if not self.dead and self.jumping and self.vy < 0 then self.vy = self.vy * MOVE.jumpCut end
  self.jumping = false
end

-- 8-way dash: held direction keys, else the aim (mouse / stick), else facing.
function Player:dashPressed()
  local s, inp = self.stats, self.input
  if self.dead or self.dashCd > 0 or self.dashesLeft <= 0 or self.lungeTimer > 0 then return end
  -- Always where you're aiming: the cursor or stick, otherwise the way you're facing.
  local dx, dy = self.aimX, self.aimY
  if inp.aim then dx, dy = math.cos(inp.aim), math.sin(inp.aim) end
  if dx == 0 and dy == 0 then dx = self.facing end
  local len = math.sqrt(dx * dx + dy * dy)
  dx, dy = dx / len, dy / len
  self.dashesLeft = self.dashesLeft - 1
  self.dashCd = s.dashCooldown
  self.dashTimer = MOVE.dashTime
  self.dashX, self.dashY = dx * s.dashSpeed, dy * s.dashSpeed
  self.jumping = false
  if math.abs(dx) > 0.2 then self.facing = dx > 0 and 1 or -1 end
  fx.burst(self.x, self.y, self.color, 8, 180, 3)
  fx.spray(self.x, self.y, math.atan2(-dy, -dx), 0.8, self.color, 12, 340, 3, 0)
  self:emitSound("dash")
  self:trigger("dash")
end

---------------------------------------------------------------- melee
-- The held melee button was released (or a full charge was overheld).
function Player:meleeRelease()
  local s = self.stats
  local held = self.meleeCharge
  self.charging, self.meleeCharge = false, 0
  if held < MELEE.lightThreshold then
    self.swingHeavy, self.swingPower = false, 0
    self.meleeCd = s.meleeCooldown
    self.swingTimer = MELEE.swingShow
    self.lungeHit = {}
    self:emitSound("meleeLight")
    self:meleeHitCheck(true)
  else
    local p = math.max(0, math.min(1, (held - MELEE.lightThreshold) / s.heavyCharge))
    self.swingHeavy, self.swingPower = true, p
    self.meleeCd = s.meleeCooldown * 2
    self.swingTimer = MELEE.swingShow + MELEE.lungeTime
    self.lungeHit = {}
    local dist = s.heavyDash * (0.45 + 0.55 * p)
    self.lungeTimer = MELEE.lungeTime
    self.preLungeVx = self.vx -- you keep moving after the lunge
    self.dashX, self.dashY = self.aimX * dist / MELEE.lungeTime, self.aimY * dist / MELEE.lungeTime
    self.dashTimer = 0
    self:emitSound("meleeHeavy", 0.7 + 0.3 * p)
  end
end

-- Hit every enemy in the swing cone once. final: the end of the swing (heavy) or the light swing.
function Player:meleeHitCheck(final)
  local s, game = self.stats, self.game
  if not self.lungeHit then return end
  local heavy, p = self.swingHeavy, self.swingPower
  local reach = s.meleeRange * (heavy and 1.2 or 1)
  local aimAng = math.atan2(self.aimY, self.aimX)
  for _, e in ipairs(game:enemiesOf(self)) do
    if not self.lungeHit[e] then
      local dx, dy = e.x - self.x, e.y - self.y
      local d = math.sqrt(dx * dx + dy * dy)
      local diff = math.abs((math.atan2(dy, dx) - aimAng + math.pi) % (math.pi * 2) - math.pi)
      if d <= self.r + reach + e.r and (diff <= MELEE.cone or d < self.r + e.r + 6) then
        self.lungeHit[e] = true
        self:meleeHit(e, heavy, p, dx, dy)
      end
    end
  end
  if game.meleeObjects then game:meleeObjects(self, reach, heavy, p) end
  if final then self.lungeHit = nil end
end

function Player:meleeHit(e, heavy, p, dx, dy)
  local s = self.stats
  local dmg = heavy and s.meleeDamage * (1.5 + 1.0 * p) or s.meleeDamage
  if (self.riposteTimer or 0) > 0 and s.riposte > 0 then dmg = dmg * (1 + 0.25 * s.riposte) end
  local knock = heavy and s.meleeKnockback * (1.2 + 0.8 * p) or s.meleeKnockback
  if e:isBlocking() then
    -- A blocked melee stuns the attacker; harder swings stun longer.
    local stun = heavy and (MELEE.heavyStunMin + (MELEE.heavyStunMax - MELEE.heavyStunMin) * p) or MELEE.lightStun
    stun = stun * (1 + (e.stats.meleeStun or 0)) * (s.stunTaken or 1)
    self:stun(stun)
    e:blocked()
    e:trigger("meleeBlocked", { target = self })
    local d = math.max(1, math.sqrt(dx * dx + dy * dy))
    self.vx, self.vy = -dx / d * 350, -dy / d * 350 - 150
    self.lungeTimer = 0
    fx.burst((self.x + e.x) / 2, (self.y + e.y) / 2, { 1, 1, 1 }, 12, 260, 3)
    self:emitSound("stun")
    return
  end
  if e:hit(dmg, dx, dy - math.abs(dx) * 0.3, knock, self, "melee") then
    if s.meleeLifesteal > 0 then self:heal(dmg * s.meleeLifesteal) end
    if heavy and s.uppercut > 0 and not e.dead then
      e.vy = -(550 + 500 * p) * (1 + 0.25 * (s.uppercut - 1))
      e.vx = e.vx * 0.3
      e.jumping = false
    end
    if heavy and s.boneBreaker > 0 then
      for _, o in ipairs(self.game:enemiesOf(self)) do
        if (o.x - e.x) ^ 2 + (o.y - e.y) ^ 2 < 130 * 130 then o.slowTimer = math.max(o.slowTimer, 0.5 * s.boneBreaker) end
      end
    end
    fx.burst(e.x, e.y, { 1, 1, 1 }, heavy and 14 or 7, heavy and 320 or 200, 3)
    self:emitSound(heavy and "meleeHitHeavy" or "meleeHit")
    self:trigger("meleeHit", { target = e })
    self.st.melee = self.st.melee + 1
    if heavy then self:trigger("heavyHit", { target = e }) end
  end
end

function Player:stun(t)
  self.stunTimer = math.max(self.stunTimer, t)
  self.charging = false
  self.dashTimer, self.lungeTimer = 0, 0
end

function Player:blockPressed()
  if self.dead or self.blockCd > 0 then return end
  local s, game = self.stats, self.game
  self.blockTimer = s.blockTime
  self.blockCd = s.blockCooldown
  fx.ring(self.x, self.y, self.r + 18, { 1, 1, 1 })
  self:emitSound("block", 0.45, 1.25)
  self:trigger("block")

  if s.blockHeal > 0 then
    self:heal(s.blockHeal)
    fx.burst(self.x, self.y, { 0.4, 1, 0.5 }, 10, 160, 3)
  end
  if s.blockReload > 0 then
    -- Extra Supply Drops overfill the magazine.
    self.ammo = math.max(self.ammo, s.ammo + s.blockReload - 1)
    self.reloadTimer = 0
  end
  if s.empower > 0 then
    self.empowered = true
    self.empowerShots = s.empower
  end
  if s.cloak > 0 then self.cloakTimer = s.cloak end
  if s.blink > 0 then self:blink(s.blink) end
  if s.sprintBlock > 0 then self.sprintTimer = 2 end
  if s.lockLoad > 0 then self.freeAmmo = 1.5 + (s.lockLoad - 1) end
  if s.timeWarp > 0 then
    self.warpTimer = 1.5 + (s.timeWarp - 1)
    fx.ring(self.x, self.y, 140, { 0.65, 0.5, 1 })
  end
  if s.gravityBlock > 0 then
    local mult = 1 + 0.3 * (s.gravityBlock - 1)
    table.insert(game.wells, {
      x = self.x, y = self.y, t = 1.4, max = 1.4, owner = self, radius = 280 * mult, strength = 3200 * mult,
    })
  end
  for i = 1, s.mineLayer do
    local m = Bullet.new(self, self.x + (i - (s.mineLayer + 1) / 2) * 22, self.y + self.r + self.leg - 6, 0, 0)
    m.laser = false
    m:becomeMine()
    m.armTime = 0.8
    game:addBullet(m)
  end

  if s.shockwave > 0 then
    fx.ring(self.x, self.y, SHOCKWAVE_RADIUS, self.color)
    fx.addShake(6)
    for _, e in ipairs(game:enemiesOf(self)) do
      local dx, dy = e.x - self.x, e.y - self.y
      local reach = SHOCKWAVE_RADIUS + e.r
      if dx * dx + dy * dy < reach * reach then e:hit(15 * s.shockwave, dx, dy, 650, self) end
    end
    for _, b in ipairs(game.bullets) do
      if b.owner ~= self and not b.laser then
        local dx, dy = b.x - self.x, b.y - self.y
        if dx * dx + dy * dy < SHOCKWAVE_RADIUS * SHOCKWAVE_RADIUS then b.dead = true end
      end
    end
  end

  if s.blockNova > 0 then
    for i = 1, s.blockNova do
      self:spawnBullet(i / s.blockNova * math.pi * 2, 0.8, false)
    end
  end
end

-- Teleport along the aim direction, as far as possible up to `dist`.
function Player:blink(dist)
  for d = dist, 30, -15 do
    local nx, ny = self.x + self.aimX * d, self.y + self.aimY * d
    if nx > 20 and nx < Map.W - 20 and ny > 20 and ny < Map.H - 20 and self:freeAt(nx, ny) then
      fx.burst(self.x, self.y, self.color, 14, 220, 3)
      self.x, self.y = nx, ny
      self.vy = math.min(self.vy, 0)
      fx.burst(nx, ny, { 1, 1, 1 }, 14, 220, 3)
      return
    end
  end
end

function Player:tryFire()
  local s = self.stats
  if self.ammo <= 0 and self.fireTimer <= 0 and (self.emptyCd or 0) <= love.timer.getTime() then
    self.emptyCd = love.timer.getTime() + 0.35
    self:emitSound("empty", 0.7)
  end
  if self.fireTimer > 0 or self.ammo <= 0 then return end

  local delay = s.fireDelay
  if s.spinup > 0 then
    self.spin = math.min(1, self.spin + 0.12 * s.spinup)
    delay = delay / (1 + 2 * self.spin)
  end
  if self:adrenalineActive() then delay = delay / (1 + 0.4 * s.adrenaline) end

  -- One-shot damage bonuses for this volley.
  local mult = 1
  local free = self.freeAmmo > 0 -- Lock and Load
  if s.lastRound > 0 and self.ammo == 1 and not free then mult = mult * (1 + s.lastRound) end
  if self.quickdrawReady then
    mult = mult * (1 + 0.5 * s.quickdraw)
    self.quickdrawReady = false
  end
  if (self.boostShots or 0) > 0 then
    mult = mult * (1 + self.boostDamage)
    self.boostShots = self.boostShots - 1
    if self.boostShots <= 0 then self.boostDamage = 0 end
  end
  if self.spiteReady and s.spite > 0 then
    mult = mult * (1 + 0.6 * s.spite)
    self.spiteReady = false
  end

  if not free then self.ammo = self.ammo - 1 end
  self.fireTimer = delay
  self.sinceShot = 0
  self.reloadTimer = (self.ammo == 0) and s.reloadTime or 0
  if self.ammo == 0 then self:emitSound("reload", 0.6) end

  self:volley(true, mult)
  self.st.shots = self.st.shots + s.bullets
  self:trigger("shoot")
  if s.bloodPact > 0 and self.hp > 1 then -- Blood Pact: every shot costs HP (can't kill you)
    self.hp = math.max(1, self.hp - 5 * s.bloodPact)
    self.hitFlash = 0.05
  end
  if s.burst > 0 then
    self.burstLeft = s.burst
    self.burstTimer = 0.09
  end
end

-- Fire one volley (all pellets). Echo repeats call this with primary = false.
-- mult: one-shot damage multiplier (Last Round, Quickdraw, Spite).
function Player:volley(primary, mult)
  local s = self.stats
  local empowered = primary and self.empowered
  if empowered then
    self.empowerShots = self.empowerShots - 1
    self.empowered = self.empowerShots > 0
  end

  local base = math.atan2(self.aimY, self.aimX)
  for i = 1, s.bullets do
    local t = s.bullets > 1 and ((i - 1) / (s.bullets - 1) - 0.5) or 0
    local ang = base + t * s.spread + (love.math.random() - 0.5) * s.spread * 0.3
    local speedMul = s.bullets > 1 and (0.9 + love.math.random() * 0.2) or 1
    self:spawnBullet(ang, speedMul, empowered, mult)
  end
  for i = 1, s.backShot do
    self:spawnBullet(base + math.pi + (i - (s.backShot + 1) / 2) * 0.18, 1, empowered, mult)
  end

  local mx, my = self.x + self.aimX * Body.muzzleDist(self), self.y + self.aimY * Body.muzzleDist(self)
  fx.muzzle(mx, my, base, s.bulletSize / 5)
  fx.kick(-self.aimX * 1.5, -self.aimY * 1.5)
  self.shotT = 0.12
  local size = s.bulletSize / 5
  if s.laser > 0 then
    self:emitSound("laser")
  elseif s.bullets >= 3 then
    self:emitSound("shotgun", 0.8)
  else
    self:emitSound("shoot", primary and 0.8 or 0.5, math.max(0.55, math.min(1.4, 1 / size ^ 0.4)))
  end

  if s.recoil > 0 then
    if self.aimY > 0 and self.vy > 0 then self.vy = 0 end
    self.vx = self.vx - self.aimX * s.recoil
    self.vy = self.vy - self.aimY * s.recoil
    self.controlLock = math.max(self.controlLock, 0.12)
  end
end

function Player:spawnBullet(ang, speedMul, empowered, mult)
  local s, game = self.stats, self.game
  local speed = s.bulletSpeed * (speedMul or 1)
  local bx = self.x + math.cos(ang) * (self.r + 8)
  local by = self.y + math.sin(ang) * (self.r + 8)
  -- If the muzzle is inside a wall, spawn from the body instead.
  if Physics.hit(game, bx - s.bulletSize, by - s.bulletSize, s.bulletSize * 2, s.bulletSize * 2) then
    bx, by = self.x, self.y
  end

  local b = Bullet.new(self, bx, by, math.cos(ang) * speed, math.sin(ang) * speed)
  if self.inTrigger then b.fromTrigger = true end
  if s.airDamage > 0 and not self.onGround then b.damage = b.damage * (1 + s.airDamage) end
  if s.berserk > 0 then
    b.damage = b.damage * (1 + s.berserk * (1 - math.max(0, self.hp) / s.maxHp))
  end
  if s.underdog > 0 then
    local best = 0
    for _, p in ipairs(game.players) do
      if p ~= self then best = math.max(best, p.score) end
    end
    local behind = math.max(0, best - self.score)
    b.damage = b.damage * (1 + 0.2 * s.underdog * behind)
  end
  if empowered then
    b.damage = b.damage * 2
    b.r = b.r * 1.5
    b.vx, b.vy = b.vx * 1.2, b.vy * 1.2
  end
  if mult and mult ~= 1 then b.damage = b.damage * mult end
  if s.momentum > 0 then
    local frac = math.min(1, math.abs(self.vx) / math.max(1, s.speed))
    b.damage = b.damage * (1 + 0.5 * s.momentum * frac)
  end
  if s.crit > 0 and love.math.random() < s.crit then b:makeCrit() end
  game:addBullet(b)
  if s.mirror > 0 then self:mirrorBullet(b) end
end

-- Mirror Shot: copies of a bullet from the mirrored side(s) of the arena.
local MIRRORS = { { true, false }, { false, true }, { true, true } }
function Player:mirrorBullet(b)
  local s, game = self.stats, self.game
  if s.mirror > 3 then b.damage = b.damage * (1 + 0.15 * (s.mirror - 3)) end
  for i = 1, math.min(3, s.mirror) do
    local c = b:clone()
    if MIRRORS[i][1] then c.x, c.vx = ARENA_W - c.x, -c.vx end
    if MIRRORS[i][2] then c.y, c.vy = ARENA_H - c.y, -c.vy end
    if not Physics.hit(game, c.x - c.r, c.y - c.r, c.r * 2, c.r * 2) then game:addBullet(c) end
  end
end

-- An attack hit our block. Parry recharges the block; extra copies also heal.
function Player:blocked()
  local s = self.stats
  self.st.blocks = self.st.blocks + 1
  self.riposteTimer = 1
  self:trigger("parry")
  if s.parry > 0 then
    self:emitSound("parry")
    self.blockCd = 0
    if s.parry > 1 then self:heal(10 * (s.parry - 1)) end
  end
end

-- Returns true if damage landed (false when blocked, invulnerable or already dead).
-- source: the player who caused it (for Thorns and Frostback), or nil.
-- kind: optional cause ("melee", "edge", hazard names...) for the kill feed.
function Player:hit(amount, dx, dy, knock, source, kind)
  if self.dead then return false end
  if source and source ~= self then self.lastAttacker = source end
  self.lastHitKind = kind
  if self:isBlocking() and kind ~= "blackhole" then
    fx.burst(self.x, self.y, { 1, 1, 1 }, 8, 200, 3)
    self:emitSound("block")
    self:blocked()
    return false
  end
  if self.invuln > 0 then return false end

  local s = self.stats
  local taken = amount
  if s.armor > 0 then amount = math.max(amount * 0.25, amount - s.armor) end
  if self.shield > 0 then
    local absorbed = math.min(self.shield, amount)
    self.shield = self.shield - absorbed
    amount = amount - absorbed
    fx.burst(self.x, self.y, { 0.5, 0.8, 1 }, 6, 160, 3)
  end

  if s.decay > 0 then
    local duration = 4 + 2 * (s.decay - 1)
    table.insert(self.decay, { remaining = amount, rate = amount / duration })
  else
    self.hp = self.hp - amount
  end
  if s.spite > 0 then self.spiteReady = true end
  if source and source ~= self and not source.dead and kind ~= "blackhole" then -- a black hole's owner isn't touching you
    if s.frostback > 0 then source.slowTimer = math.max(source.slowTimer, s.frostback) end
    if s.thorns > 0 and source.invuln <= 0 then
      source.hp = source.hp - taken * s.thorns
      source.hitFlash = 0.1
      if source.hp <= 0 then source:die() end
    end
  end
  if self.hp < s.maxHp * 0.3 and self.hp + amount >= s.maxHp * 0.3 and self.hp > 0 then self:trigger("lowHp") end
  if source and source ~= self and source.st then source.st.dmg = source.st.dmg + amount end
  fx.number(self.x, self.y - self.r, amount, self.slot or 0, kind == "crit")
  self:trigger("hurt", { target = source })
  self.hitFlash = 0.1
  if kind ~= "melee" and kind ~= "edge" then
    self:emitSound(taken >= 40 and "hitHeavy" or "hit", math.min(1, 0.5 + taken / 60))
  end
  fx.burst(self.x, self.y, self.color, 10, 220, 4)
  fx.addShake(4)
  local len = math.sqrt(dx * dx + dy * dy)
  if len > 0 and self.stats.knockbackImmune <= 0 then
    self.vx = self.vx + dx / len * knock
    self.vy = self.vy + dy / len * knock - knock * 0.3
    self.controlLock = 0.12
  end
  if self.hp <= 0 then self:die() end
  return true
end

function Player:heal(amount)
  if self.dead then return end
  self.hp = math.min(self.stats.maxHp, self.hp + amount)
end

function Player:poisonFor(total, duration)
  local remaining = self.poisonDps * self.poisonTimer
  self.poisonTimer = duration
  self.poisonDps = (remaining + total) / duration
end

function Player:die(outOfBounds)
  if self.dead then return end

  -- Last Stand: shrug off a lethal hit (not falling out of the arena).
  if (self.lastStandLeft or 0) > 0 and not outOfBounds then
    self.lastStandLeft = self.lastStandLeft - 1
    self.hp = 1
    self.poisonTimer = 0
    self.decay = {}
    self.invuln = 1
    fx.ring(self.x, self.y, 70, { 1, 1, 1 })
    fx.burst(self.x, self.y, { 1, 0.95, 0.6 }, 20, 300, 4)
    self:emitSound("revive", 0.7, 1.4)
    return
  end

  fx.burst(self.x, self.y, self.color, 40, 450, 6)
  fx.addShake(12)

  -- Phoenix: come back instead of dying.
  if self.livesLeft > 0 then
    self.livesLeft = self.livesLeft - 1
    self:martyrBlast()
    self.hp = self.stats.maxHp * 0.5
    self.poisonTimer = 0
    self.decay = {}
    self.invuln = 1.2
    if outOfBounds then
      self.x, self.y = self.spawnX, self.spawnY
      self.vx, self.vy = 0, 0
    end
    fx.ring(self.x, self.y, 90, { 1, 0.6, 0.15 })
    fx.burst(self.x, self.y, { 1, 0.7, 0.2 }, 30, 350, 5)
    self:emitSound("revive")
    return
  end

  self.dead = true
  self.hp = 0
  local killer = self.lastAttacker
  if killer and killer ~= self and killer.trigger and not killer.dead then killer:trigger("kill", { target = self }) end
  self.st.deaths = self.st.deaths + 1
  if killer and killer ~= self and killer.st then killer.st.kills = killer.st.kills + 1 end
  if self.game and self.game.emit then self.game:emit("kill", self, killer ~= self and killer or nil, self.lastHitKind) end
  fx.burst(self.x, self.y, { 1, 1, 1 }, 15, 300, 4)
  fx.gibs(self.x, self.y, self.color, 12, 11)
  self:emitSound("death")
  self:emitSound("gibs")

  self:martyrBlast()
end

-- Martyr: a blast whenever you go down, even if Phoenix brings you back.
function Player:martyrBlast()
  if self.stats.martyr <= 0 then return end
  local radius = 200
  fx.explosion(self.x, self.y, radius, self.color)
  fx.addShake(18)
  for _, e in ipairs(self.game:enemiesOf(self)) do
    local dx, dy = e.x - self.x, e.y - self.y
    if math.sqrt(dx * dx + dy * dy) < radius + e.r then
      e:hit(60 * self.stats.martyr, dx, dy, 800, self)
    end
  end
end

-- Emissive parts only, drawn into the bloom buffer.
function Player:drawGlow()
  if self.dead then return end
  local A = self.cloakTimer > 0 and 0.08 or 1
  local c = self.color
  love.graphics.setColor(c[1], c[2], c[3], 0.45 * A)
  love.graphics.circle("fill", self.x, self.y, self.r)
  if self:isBlocking() then
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.setLineWidth(4)
    love.graphics.circle("line", self.x, self.y, self.r + 14)
  end
  if self.empowered then
    love.graphics.setColor(1, 0.9, 0.5, 0.8 * A)
    love.graphics.circle("fill", self.x + self.aimX * (self.r + 12), self.y + self.aimY * (self.r + 12), 6)
  end
  for i = 1, self.stats.orbs do
    local ox, oy = self:orbPos(i)
    love.graphics.setColor(c[1], c[2], c[3], 0.9)
    love.graphics.circle("fill", ox, oy, ORB_SIZE)
  end
end

-- Melee charge ring, swing arc and stun stars.
function Player:drawMelee(A)
  local r, c = self.r, self.color
  local aim = math.atan2(self.aimY, self.aimX)
  if self.charging and (self.meleeCharge or 0) > MELEE.lightThreshold then
    local p = math.min(1, (self.meleeCharge - MELEE.lightThreshold) / math.max(0.05, self.stats.heavyCharge or 0.6))
    love.graphics.setColor(1, 1, 1, 0.25 * A)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", self.x, self.y, r + 10)
    love.graphics.setColor(1, p >= 1 and 0.85 or 1, p >= 1 and 0.3 or 1, 0.9 * A)
    love.graphics.arc("line", "open", self.x, self.y, r + 10, -math.pi / 2, -math.pi / 2 + math.pi * 2 * p)
  end
  if (self.swingTimer or 0) > 0 then
    local t = self.swingTimer / (MELEE.swingShow + (self.swingHeavy and MELEE.lungeTime or 0))
    local reach = r + (self.stats.meleeRange or 55) * (self.swingHeavy and 1.2 or 1)
    local spread = MELEE.cone
    local sweep = aim - spread + (1 - t) * spread * 2
    love.graphics.setColor(1, 1, 1, 0.55 * t * A)
    love.graphics.setLineWidth(self.swingHeavy and 8 or 5)
    love.graphics.arc("line", "open", self.x, self.y, reach, aim - spread, sweep)
    love.graphics.setColor(c[1], c[2], c[3], 0.35 * t * A)
    love.graphics.arc("fill", self.x, self.y, reach, aim - spread, sweep)
  end
  if (self.stunTimer or 0) > 0 then
    local t = love.timer.getTime()
    love.graphics.setColor(1, 0.95, 0.4, A)
    for i = 1, 3 do
      local a = t * 5 + i * math.pi * 2 / 3
      love.graphics.circle("fill", self.x + math.cos(a) * r * 0.9, self.y - r - 8 + math.sin(a) * 4, 3)
    end
  end
end

function Player:draw()
  if self.dead then return end
  local r, s = self.r, self.stats
  local c = self.color

  local A = 1
  if self.cloakTimer > 0 then
    A = 0.12
  elseif self.invuln > 0 and math.floor(self.invuln * 15) % 2 == 0 then
    A = 0.4
  end

  if s.stasis > 0 then
    local sr = Player.stasisRadius(s.stasis)
    love.graphics.setColor(0.6, 0.8, 1, 0.06 * A)
    love.graphics.circle("fill", self.x, self.y, sr)
    love.graphics.setColor(0.6, 0.8, 1, 0.15 * A)
    love.graphics.setLineWidth(1)
    love.graphics.circle("line", self.x, self.y, sr)
  end

  if self:isBlocking() then
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.circle("fill", self.x, self.y, r + 14)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", self.x, self.y, r + 14)
  end

  -- Shield Generator bubble
  if (self.shield or 0) > 0 then
    love.graphics.setColor(0.5, 0.8, 1, (0.25 + 0.35 * math.min(1, self.shield / 60)) * A)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", self.x, self.y, r + 5)
  end

  -- Sentry turret
  if (s.sentry or 0) > 0 then
    local sx, sy = self:sentryPos()
    love.graphics.setColor(0.85, 0.85, 0.9, A)
    love.graphics.rectangle("fill", sx - 7, sy - 5, 14, 10, 3, 3)
    love.graphics.setColor(c[1], c[2], c[3], A)
    love.graphics.circle("fill", sx, sy, 3.5)
  end

  for i = 1, s.orbs do
    local ox, oy = self:orbPos(i)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.circle("fill", ox, oy, ORB_SIZE + 1.5)
    love.graphics.setColor(c)
    love.graphics.circle("fill", ox, oy, ORB_SIZE)
  end

  self:drawMelee(A)

  Body.update(self, love.timer.getDelta())
  Body.drawLegs(self, A)

  -- Body
  if self.hitFlash > 0 then
    love.graphics.setColor(1, 1, 1, A)
  elseif self.poisonTimer > 0 then
    love.graphics.setColor(c[1] * 0.6 + 0.16, c[2] * 0.6 + 0.36, c[3] * 0.6 + 0.08, A)
  elseif self.slowTimer > 0 then
    love.graphics.setColor(c[1] * 0.5 + 0.3, c[2] * 0.5 + 0.4, c[3] * 0.5 + 0.5, A)
  else
    love.graphics.setColor(c[1], c[2], c[3], A)
  end
  -- Squash and stretch: stretched while moving fast vertically, squashed on landing.
  local sx, sy, by0 = 1, 1, self.y
  love.graphics.ellipse("fill", self.x, by0, r * sx, r * sy)
  if self.slowTimer > 0 then
    love.graphics.setColor(0.7, 0.9, 1, 0.7 * A)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", self.x, self.y, r + 2)
  end

  -- Face and hat. The eyes follow your aim, blink, and react to shooting and getting hurt.
  local blink = (love.timer.getTime() * 0.31 + (self.slot or 1) * 0.37) % 1 < 0.045
  local lookY = self.aimY + ((self.vy or 0) < -250 and -0.4 or (self.vy or 0) > 350 and 0.4 or 0)
  Cosmetics.drawFace(self.x + self.facing * r * 0.14, by0 - r * 0.22 * sy, r,
    { self.aimX, math.max(-1, math.min(1, lookY)) },
    { blink = blink, hurt = self.hitFlash > 0, firing = (self.shotT or 0) > 0, expr = Body.expression(self) }, A,
    self.eyes, self.mouth, self.detail)
  if A > 0.3 then Cosmetics.drawHat(self.x, by0 - r * 0.92 * sy, r, self.hat, c) end
  Body.drawArms(self, A)

  -- HP bar (pending Decay damage shown faded)
  local pending = 0
  for _, d in ipairs(self.decay) do pending = pending + d.remaining end
  local bw, bx, by = 56, self.x - 28, self.y - r - 18
  local hpFrac = math.max(0, self.hp) / s.maxHp
  local solidFrac = math.max(0, self.hp - pending) / s.maxHp
  love.graphics.setColor(0, 0, 0, 0.6 * A)
  love.graphics.rectangle("fill", bx - 1, by - 1, bw + 2, 8)
  love.graphics.setColor(c[1], c[2], c[3], 0.35 * A)
  love.graphics.rectangle("fill", bx, by, bw * hpFrac, 6)
  love.graphics.setColor(c[1], c[2], c[3], A)
  love.graphics.rectangle("fill", bx, by, bw * solidFrac, 6)

  -- Phoenix lives
  for i = 1, self.livesLeft do
    love.graphics.setColor(1, 0.6, 0.15, A)
    love.graphics.circle("fill", bx + bw + 4 + i * 8, by + 3, 3)
  end

  -- Ammo pips, or a reload bar while reloading from empty
  local py = by - 8
  if self.ammo == 0 and self.reloadTimer > 0 then
    love.graphics.setColor(1, 1, 1, 0.8 * A)
    love.graphics.rectangle("fill", bx, py - 1, bw * (1 - self.reloadTimer / s.reloadTime), 3)
  else
    local slots = math.max(s.ammo, self.ammo) -- Supply Drop can overfill
    local spacing = math.min(9, bw / math.max(1, slots))
    local startX = self.x - (slots - 1) * spacing / 2
    for i = 1, slots do
      love.graphics.setColor(1, 1, 1, (i <= self.ammo and 0.9 or 0.2) * A)
      love.graphics.circle("fill", startX + (i - 1) * spacing, py, 2.5)
    end
  end

  if Body.showNames and A > 0.3 then
    local font = require("core.app").fonts.small
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.printf(self.name or "", self.x - 90, py - 8 - font:getHeight(), 180, "center")
    if Body.speakingSlot and Body.speakingSlot(self) then
      require("online.voice").drawIcon(self.x + font:getWidth(self.name or "") / 2 + 14, py - 8 - font:getHeight() / 2)
    end
  end
end

return Player
