-- Player stats: base values plus how each stat is shown on cards and in the card editor.
--   fmt "pct"   : a multiplier row shows "+30% <label>"; an add row of a fraction shows "+30% <label>"
--   fmt "flat"  : an add row shows "+20 <label>"; a multiplier row shows a percentage
--   fmt "rate"  : shown inverted (fireDelay x0.75 -> "+33% fire rate")
--   fmt "secs"  : seconds ("+1.5s <label>")
--   fmt "count" : abilities counted per copy ("+1 <label>")
--   fmt "hidden": internal tuning values; the card's notes describe them
-- better: "high" (more is good) or "low" (less is good) - colours the generated line.
-- Card abilities are counts of copies (0 = not owned), so every card stacks.
local Stats = {}

Stats.GROUPS = { "Gun", "Bullets", "Melee", "Movement", "Defense", "Block", "Abilities" }

Stats.LIST = {
  -- Gun
  { "gunDamage", 34, "Gun", "pct", "high", "gun damage" },
  { "airDamage", 0, "Gun", "pct", "high", "gun damage while airborne" },
  { "bloodPact", 0, "Gun", "count", "high", "blood pact" },
  { "fireDelay", 0.25, "Gun", "rate", "low", "fire rate" },
  { "ammo", 3, "Gun", "flat", "high", "ammo" },
  { "reloadTime", 1.5, "Gun", "pct", "low", "reload time" },
  { "bullets", 1, "Gun", "flat", "high", "bullets per shot" },
  { "spread", 0, "Gun", "pct", "low", "spread" },
  { "knockback", 250, "Gun", "pct", "high", "knockback" },
  { "recoil", 0, "Gun", "hidden", "high", "recoil" },
  { "burst", 0, "Gun", "count", "high", "echo shots" },
  { "spinup", 0, "Gun", "count", "high", "fire-rate ramp" },
  { "backShot", 0, "Gun", "count", "high", "back shots" },
  -- Bullets
  { "bulletSpeed", 950, "Bullets", "pct", "high", "bullet speed" },
  { "bulletGravity", 0.45, "Bullets", "pct", "low", "bullet drop" },
  { "bulletSize", 5, "Bullets", "pct", "high", "bullet size" },
  { "bounces", 0, "Bullets", "flat", "high", "bullet bounces" },
  { "bounceDamage", 0, "Bullets", "pct", "high", "damage per bounce" },
  { "distDamage", 0, "Bullets", "hidden", "high", "damage over distance" },
  { "accel", 0, "Bullets", "hidden", "high", "bullet acceleration" },
  { "explosion", 0, "Bullets", "flat", "high", "explosion radius" },
  { "explosionSize", 1, "Bullets", "pct", "high", "explosion size" },
  { "poison", 0, "Bullets", "pct", "high", "poison damage" },
  { "homing", 0, "Bullets", "hidden", "high", "homing" },
  { "lifesteal", 0, "Bullets", "pct", "high", "lifesteal" },
  { "frost", 0, "Bullets", "hidden", "high", "slow on hit" },
  { "crit", 0, "Bullets", "pct", "high", "crit chance" },
  { "pierce", 0, "Bullets", "hidden", "high", "players pierced" },
  { "split", 0, "Bullets", "count", "high", "wall splits" },
  { "ghost", 0, "Bullets", "count", "high", "ghost bullets" },
  { "sticky", 0, "Bullets", "count", "high", "sticky mines" },
  { "blackhole", 0, "Bullets", "count", "high", "black holes" },
  { "shrapnel", 0, "Bullets", "count", "high", "shrapnel" },
  { "seek", 0, "Bullets", "hidden", "high", "ricochet homing" },
  { "cluster", 0, "Bullets", "count", "high", "cluster blasts" },
  { "hydra", 0, "Bullets", "count", "high", "hydra heads" },
  { "laser", 0, "Bullets", "count", "high", "laser" },
  { "mirror", 0, "Bullets", "count", "high", "mirror shots" },
  { "scavenger", 0, "Bullets", "flat", "high", "ammo refunded per hit" },
  -- Melee
  { "meleeDamage", 20, "Melee", "pct", "high", "melee damage" },
  { "meleeKnockback", 450, "Melee", "pct", "high", "melee knockback" },
  { "meleeRange", 55, "Melee", "pct", "high", "melee range" },
  { "meleeCooldown", 0.45, "Melee", "pct", "low", "melee cooldown" },
  { "heavyCharge", 0.6, "Melee", "pct", "low", "heavy charge time" },
  { "heavyDash", 90, "Melee", "pct", "high", "heavy lunge" },
  { "meleeStun", 0, "Melee", "pct", "high", "stun when you block melee" },
  { "meleeLifesteal", 0, "Melee", "pct", "high", "melee lifesteal" },
  { "stunTaken", 1, "Melee", "pct", "low", "stun when your melee is blocked" },
  { "uppercut", 0, "Melee", "count", "high", "uppercut" },
  { "riposte", 0, "Melee", "count", "high", "riposte" },
  { "boneBreaker", 0, "Melee", "count", "high", "bone breaker" },
  { "objectDamage", 1, "Melee", "pct", "high", "damage to map objects" },
  -- Movement
  { "speed", 340, "Movement", "pct", "high", "move speed" },
  { "jump", 930, "Movement", "pct", "high", "jump power" },
  { "airJumps", 0, "Movement", "flat", "high", "air jumps" },
  { "gravityMul", 1, "Movement", "pct", "low", "gravity" },
  { "dashes", 1, "Movement", "flat", "high", "air dashes" },
  { "dashSpeed", 950, "Movement", "pct", "high", "dash speed" },
  { "dashCooldown", 0.6, "Movement", "pct", "low", "dash cooldown" },
  { "radius", 20, "Movement", "hidden", "low", "body size" },
  -- Defense
  { "maxHp", 100, "Defense", "flat", "high", "HP" },
  { "armor", 0, "Defense", "flat", "high", "damage blocked per hit" },
  { "regen", 0, "Defense", "flat", "high", "HP per second" },
  { "shieldMax", 0, "Defense", "flat", "high", "shield each round" },
  { "lives", 0, "Defense", "count", "high", "revives" },
  { "lastStand", 0, "Defense", "count", "high", "last stands" },
  { "decay", 0, "Defense", "count", "high", "damage decay" },
  { "thorns", 0, "Defense", "hidden", "high", "thorns" },
  { "frostback", 0, "Defense", "hidden", "high", "slow on attackers" },
  { "knockbackImmune", 0, "Defense", "count", "high", "knockback immunity" },
  { "stasis", 0, "Defense", "count", "high", "stasis field" },
  { "repel", 0, "Defense", "count", "high", "bullet repulsion" },
  { "orbs", 0, "Defense", "flat", "high", "orbiting orbs" },
  { "hazardTaken", 1, "Defense", "pct", "low", "hazard damage taken" },
  { "edgeTaken", 1, "Defense", "pct", "low", "edge damage taken" },
  { "edgeLaunch", 1, "Defense", "pct", "high", "edge launch" },
  -- Block
  { "blockCooldown", 4, "Block", "pct", "low", "block cooldown" },
  { "blockTime", 0.3, "Block", "secs", "high", "block duration" },
  { "blockHeal", 0, "Block", "flat", "high", "HP healed when blocking" },
  { "reflect", 0, "Block", "count", "high", "reflected bullets" },
  { "shockwave", 0, "Block", "count", "high", "block shockwave" },
  { "blink", 0, "Block", "hidden", "high", "blink distance" },
  { "empower", 0, "Block", "count", "high", "empowered shots" },
  { "parry", 0, "Block", "count", "high", "parry" },
  { "blockReload", 0, "Block", "count", "high", "block reload" },
  { "cloak", 0, "Block", "hidden", "high", "cloak" },
  { "blockNova", 0, "Block", "hidden", "high", "nova bullets" },
  { "sprintBlock", 0, "Block", "count", "high", "sprint block" },
  { "mineLayer", 0, "Block", "hidden", "high", "mines per block" },
  { "lockLoad", 0, "Block", "count", "high", "lock and load" },
  { "gravityBlock", 0, "Block", "count", "high", "gravity block" },
  { "timeWarp", 0, "Block", "count", "high", "time warp" },
  -- Abilities (damage conditions and effects)
  { "berserk", 0, "Abilities", "count", "high", "berserker" },
  { "underdog", 0, "Abilities", "count", "high", "underdog" },
  { "martyr", 0, "Abilities", "count", "high", "martyr" },
  { "lastRound", 0, "Abilities", "count", "high", "last round" },
  { "spite", 0, "Abilities", "count", "high", "spite" },
  { "execute", 0, "Abilities", "count", "high", "executioner" },
  { "combo", 0, "Abilities", "count", "high", "combo" },
  { "static", 0, "Abilities", "hidden", "high", "static damage per second" },
  { "quickdraw", 0, "Abilities", "count", "high", "quickdraw" },
  { "momentum", 0, "Abilities", "count", "high", "momentum" },
  { "reloadNova", 0, "Abilities", "hidden", "high", "reload nova bullets" },
  { "adrenaline", 0, "Abilities", "count", "high", "adrenaline" },
  { "swap", 0, "Abilities", "count", "high", "swap shot" },
  { "sentry", 0, "Abilities", "count", "high", "sentry" },
  -- Bullets that do something when they land.
  { "thruster", 0, "Bullets", "count", "high", "jet rounds" },
  { "fuse", 0, "Bullets", "count", "high", "fuse bombs" },
  { "dazzle", 0, "Bullets", "count", "high", "flashbang" },
  { "drill", 0, "Bullets", "count", "high", "drilling bullets" },
  { "cloudShot", 0, "Bullets", "count", "high", "poison clouds" },
  { "remote", 0, "Bullets", "count", "high", "steered bullets" },
  { "snare", 0, "Bullets", "count", "high", "tethers" },
  -- Things a block sets off.
  { "blockEcho", 0, "Block", "count", "high", "echo blocks" },
  { "payback", 0, "Block", "count", "high", "payback" },
  { "saw", 0, "Block", "count", "high", "buzzsaw" },
  { "radar", 0, "Block", "count", "high", "sweep shots" },
  { "hush", 0, "Block", "count", "high", "hush" },
  { "star", 0, "Block", "count", "high", "dying star" },
  { "stormCell", 0, "Block", "count", "high", "storm cell" },
  { "ram", 0, "Block", "count", "high", "ram" },
  { "implode", 0, "Block", "count", "high", "undertow" },
  { "carpet", 0, "Block", "count", "high", "carpet bombs" },
  { "lastBlock", 0, "Block", "count", "high", "last word" },
  { "novaFrost", 0, "Block", "hidden", "high", "nova slow" },
  { "pursuit", 0, "Abilities", "count", "high", "pursuit" },
  { "coldAura", 0, "Abilities", "count", "high", "cold aura" },
  { "pristine", 0, "Defense", "count", "high", "fresh start" },
  { "leech", 0, "Abilities", "count", "high", "leech aura" },
  { "stillness", 0, "Abilities", "count", "high", "stillness" },
  { "sunflare", 0, "Abilities", "count", "high", "sunflare" },
  { "demolition", 0, "Abilities", "count", "high", "demolition" },
  { "hillRunner", 0, "Movement", "count", "high", "hill runner" },
  -- v0.7 cards (game/abilities.lua does what they say).
  { "blockSize", 1, "Block", "pct", "high", "block size" },
  { "perfectGuard", 0, "Block", "count", "high", "perfect guard" },
  { "kineticGuard", 0, "Block", "count", "high", "kinetic guard" },
  { "staticGuard", 0, "Block", "count", "high", "static guard" },
  { "blockDash", 0, "Block", "count", "high", "counterweight" },
  { "blockCharges", 0, "Block", "count", "high", "stored blocks" },
  { "bunker", 0, "Block", "count", "high", "bunker" },
  { "guardBreak", 0, "Block", "count", "high", "guard break" },
  { "ward", 0, "Block", "count", "high", "ward" },
  { "instantHeavy", 0, "Block", "count", "high", "riposte" },
  { "mirrorPlate", 0, "Block", "count", "high", "mirror plate" },
  { "overcharge", 0, "Block", "count", "high", "overcharge" },
  { "aegis", 0, "Block", "count", "high", "aegis" },
  { "dashShot", 0, "Movement", "count", "high", "dash shot" },
  { "razorDash", 0, "Movement", "count", "high", "razor dash" },
  { "emberTrail", 0, "Movement", "count", "high", "ember trail" },
  { "rebound", 0, "Movement", "count", "high", "rebound" },
  { "dashShots", 0, "Movement", "count", "high", "momentum rounds" },
  { "graze", 0, "Movement", "count", "high", "graze" },
  { "chainDash", 0, "Movement", "count", "high", "chain dash" },
  { "thunderStep", 0, "Movement", "count", "high", "thunder step" },
  { "impactDash", 0, "Movement", "count", "high", "impact" },
  { "flashStep", 0, "Movement", "count", "high", "flash step" },
  { "ghostRun", 0, "Movement", "count", "high", "ghost run" },
  { "airAce", 0, "Movement", "count", "high", "air ace" },
  { "overdrive", 0, "Movement", "count", "high", "overdrive" },
  { "lightLunge", 0, "Melee", "flat", "high", "light-hit lunge (px)" },
  { "heavyDamage", 1, "Melee", "pct", "high", "heavy melee damage" },
  { "comboFists", 0, "Melee", "count", "high", "combo fists" },
  { "bleed", 0, "Melee", "count", "high", "bleed" },
  { "deflectSwing", 0, "Melee", "count", "high", "deflect swing" },
  { "secondSwing", 0, "Melee", "count", "high", "second swing" },
  { "gunToss", 0, "Melee", "count", "high", "gun toss" },
  { "meteor", 0, "Melee", "count", "high", "meteor fist" },
  { "whirlwind", 0, "Melee", "count", "high", "whirlwind" },
  { "ironJaw", 0, "Melee", "count", "high", "iron jaw" },
  { "airHunter", 0, "Melee", "count", "high", "uppercut chain" },
  { "grapple", 0, "Melee", "count", "high", "grapple" },
  { "haymaker", 0, "Melee", "count", "high", "haymaker" },
  { "meleeExecute", 0, "Melee", "count", "high", "executioner" },
  { "mineDrop", 0, "Abilities", "count", "high", "mine layer" },
  { "grenadier", 0, "Abilities", "count", "high", "grenadier" },
  { "spikeTrap", 0, "Abilities", "count", "high", "spike trap" },
  { "decoy", 0, "Abilities", "count", "high", "decoy" },
  { "iceWall", 0, "Abilities", "count", "high", "ice wall" },
  { "totem", 0, "Abilities", "count", "high", "totem" },
  { "magnetMine", 0, "Abilities", "count", "high", "magnet mine" },
  { "drones", 0, "Abilities", "count", "high", "shield drones" },
  { "fieldTurret", 0, "Abilities", "count", "high", "field turret" },
  { "remoteCharge", 0, "Abilities", "count", "high", "remote charge" },
  { "bees", 0, "Abilities", "count", "high", "bee swarm" },
  { "gravityBomb", 0, "Abilities", "count", "high", "gravity bomb" },
  { "hiveMind", 0, "Abilities", "count", "high", "hive mind" },
  { "bounceBonus", 0, "Bullets", "count", "high", "angle play" },
  { "superBall", 0, "Bullets", "count", "high", "super ball" },
  { "bounceBomb", 0, "Bullets", "count", "high", "bounce bomb" },
  { "springWalls", 0, "Bullets", "count", "high", "spring walls" },
  { "bodyBounce", 0, "Bullets", "count", "high", "body bounce" },
  { "trickShot", 0, "Bullets", "count", "high", "trick shot" },
  { "sonar", 0, "Bullets", "count", "high", "sonar bounce" },
  { "cornerPocket", 0, "Bullets", "count", "high", "corner pocket" },
  { "rubberRoom", 0, "Bullets", "count", "high", "rubber room" },
  { "boomerang", 0, "Bullets", "count", "high", "boomerang" },
  { "burnOnHit", 0, "Bullets", "count", "high", "kindle" },
  { "brittle", 0, "Abilities", "count", "high", "brittle" },
  { "corrode", 0, "Abilities", "count", "high", "corrode" },
  { "shockOnHit", 0, "Bullets", "count", "high", "static rounds" },
  { "toxicPuddle", 0, "Abilities", "count", "high", "toxic puddle" },
  { "cinders", 0, "Abilities", "count", "high", "cinders" },
  { "sap", 0, "Bullets", "count", "high", "sap" },
  { "wildfire", 0, "Abilities", "count", "high", "wildfire" },
  { "conductor", 0, "Abilities", "count", "high", "conductor" },
  { "frostbite", 0, "Abilities", "count", "high", "frostbite" },
  { "thermal", 0, "Abilities", "count", "high", "thermal shock" },
  { "plague", 0, "Abilities", "count", "high", "plague" },
  { "shatterpoint", 0, "Abilities", "count", "high", "shatterpoint" },
  { "overload", 0, "Abilities", "count", "high", "overload" },
  { "cornered", 0, "Abilities", "count", "high", "cornered" },
  { "daredevil", 0, "Abilities", "count", "high", "daredevil" },
  { "rush", 0, "Abilities", "count", "high", "adrenaline rush" },
  { "wager", 0, "Abilities", "count", "high", "wager" },
  { "lastBreath", 0, "Abilities", "count", "high", "last breath" },
  { "rage", 0, "Abilities", "count", "high", "berserker" },
  { "ironWill", 0, "Defense", "count", "high", "iron will" },
  { "bloodAmmo", 0, "Gun", "count", "high", "blood ammo" },
  { "hemorrhage", 0, "Gun", "count", "high", "hemorrhage" },
  { "finalGambit", 0, "Abilities", "count", "high", "final gambit" },
  { "lastLight", 0, "Abilities", "count", "high", "last light" },
  { "reprise", 0, "Gun", "count", "high", "reprise" },
  { "upsideDown", 0, "Abilities", "count", "high", "upside down" },
}

Stats.BASE = {}
Stats.INFO = {}
for i, row in ipairs(Stats.LIST) do
  local info = { key = row[1], base = row[2], group = row[3], fmt = row[4], better = row[5], label = row[6], order = i }
  Stats.INFO[info.key] = info
  Stats.BASE[info.key] = info.base
end

-- These are shown in seconds when a card adds to them ("+0.25s reload time").
Stats.INFO.reloadTime.addSecs = true
Stats.INFO.blockCooldown.addSecs = true

-- Renamed stats (old card files / settings).
Stats.ALIAS = { damage = "gunDamage" }

local function round(v) return math.floor(v + 0.5) end

Stats.SINGULAR = {
  ["air jumps"] = "air jump", ["air dashes"] = "air dash", ["bullets per shot"] = "bullet per shot",
  ["bullet bounces"] = "bullet bounce", ["orbiting orbs"] = "orbiting orb", ["revives"] = "revive",
}

local function num(v)
  if math.abs(v - round(v)) < 0.001 then return tostring(round(v)) end
  return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
end
Stats.num = num

-- The text line for one card row, and whether it's good for the player (nil = neutral/hidden).
-- row = { op = "add" | "mul" | "set", stat = key, value = number }
function Stats.describe(row)
  local info = Stats.INFO[row.stat]
  if not info or info.fmt == "hidden" or info.fmt == "count" then return nil end
  local v = row.value
  local text, up
  if row.op == "set" then
    if info.fmt == "rate" then return nil end -- explained by the card's notes
    if v == 0 then return "+no " .. info.label, nil end
    return "+" .. info.label .. " set to " .. num(v), nil
  elseif row.op == "mul" then
    if v == 1 then return nil end
    if info.fmt == "rate" then
      local pct = round((1 / v - 1) * 100)
      up = pct > 0
      text = (pct > 0 and "+" or "") .. pct .. "% " .. info.label
      return text, up
    end
    local pct = round((v - 1) * 100)
    if pct == 0 then return nil end
    up = pct > 0
    text = (pct > 0 and "+" or "") .. pct .. "% " .. info.label
  else -- add
    if v == 0 then return nil end
    up = v > 0
    if info.fmt == "pct" and math.abs(info.base) <= 1.5 and not info.addSecs then
      text = (v > 0 and "+" or "") .. round(v * 100) .. "% " .. info.label
    elseif info.fmt == "secs" or info.addSecs then
      text = (v > 0 and "+" or "") .. num(v) .. "s " .. info.label
    elseif info.fmt == "rate" then
      text = (v > 0 and "+" or "") .. num(v) .. "s between shots"
      up = v < 0
    else
      local label = info.label
      if math.abs(v) == 1 then label = Stats.SINGULAR[label] or label end -- "+1 air jump"
      text = (v > 0 and "+" or "") .. num(v) .. " " .. label
    end
  end
  local good = up
  if info.better == "low" then good = not up end
  return text, good
end

return Stats
