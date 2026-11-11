-- Functional checks for the v0.7 cards (game/abilities.lua). Called from main.lua.
return function(check)
  local Map=require "game.map"; local World=require "game.world"; local Input=require "core.input"; local Cards=require "game.cards"
  local Bullet=require "game.bullet"
  World.setSlotColors({1,2,3,4})
  local base={name="t",spawns={{300,700},{1200,700},{400,700},{1100,700}},rects={{x=0,y=768,w=1536,h=96}},objects={}}
  local function mk(cardsA, cardsB, map)
    local m=map or Map.parse(Map.serialize(base))
    local defs={} for i=1,2 do defs[i]={name="p"..i,input=Input.remote()} end
    local w=World.new(defs,999,{pickFrom=3,picksPerRound=1,weights=Cards.DEFAULT_RULES.weights,rarity={},disabled={},startCards=0,forceMap=m,barrier=false})
    local a,b=w.players[1],w.players[2]
    for _,id in ipairs(cardsA or {}) do a.cards[#a.cards+1]=assert(Cards.byId[id], id) end
    for _,id in ipairs(cardsB or {}) do b.cards[#b.cards+1]=assert(Cards.byId[id], id) end
    a:recompute(); b:recompute()
    w:startRound(); w.state="playing"
    for _=1,30 do w.state="playing"; w:update(1/60) end
    a.invuln, b.invuln = 0, 0
    a.hp, b.hp = a.stats.maxHp, b.stats.maxHp
    return w,a,b
  end
  local function run(w,s) for _=1,math.floor(s*60) do w.state="playing"; w:update(1/60) end end
  local function shootAt(w,a,b)
    local dx,dy=b.x-a.x,b.y-a.y; local d=math.sqrt(dx*dx+dy*dy)
    local bl=Bullet.new(a,a.x+dx/d*30,a.y+dy/d*30,dx/d*1500,dy/d*1500); bl.gravity=0
    w:addBullet(bl); return bl
  end

  -- Kindle: hits burn.
  do local w,a,b=mk({"kindle"}); a.x,b.x=300,500; shootAt(w,a,b); run(w,0.3)
    check("Kindle sets enemies burning", (b.burnT or 0)>0, b.burnT) end
  -- Static Rounds: next hit amplified.
  do local w,a,b=mk({"static_rounds"}); a.x,b.x=300,500; shootAt(w,a,b); run(w,0.3)
    check("Static Rounds shocks", (b.shockT or 0)>0, b.shockT) end
  -- Spare Guard: two blocks in a row.
  do local w,a,b=mk({"spare_guard"}); a.input.blockCount=a.input.blockCount+1; run(w,0.4)
    local first=a.st.blocks; a.blockTimer=0; a.input.blockCount=a.input.blockCount+1; run(w,0.1)
    check("Spare Guard blocks twice without waiting", a.blockTimer>0, a.blockTimer) end
  -- Overcharge: third block blasts.
  do local w,a,b=mk({"overcharge"}); b.x=a.x+150
    for k=1,3 do a.blockStock=nil; a.blockCd=0; a.input.blockCount=a.input.blockCount+1; run(w,0.2) end
    check("Overcharge's third block hurts nearby enemies", b.hp<b.stats.maxHp, b.hp) end
  -- Static Guard: blocking zaps.
  do local w,a,b=mk({"static_guard"}); b.x=a.x+200; a.input.blockCount=a.input.blockCount+1; run(w,0.2)
    check("Static Guard zaps on block", b.hp<b.stats.maxHp, b.hp) end
  -- Fortress: bigger block.
  do local w,a=mk({"fortress"}); check("Fortress grows the block", a.stats.blockSize>1, a.stats.blockSize) end
  -- Flash Step: dash teleports.
  do local w,a=mk({"flash_step"}); local x0=a.x; a.input.aim=0; a.input.dashCount=a.input.dashCount+1; run(w,1/60*2)
    check("Flash Step jumps ahead at once", a.x-x0>80, a.x-x0) end
  -- Razor Dash: cuts on the way through.
  do local w,a,b=mk({"razor_dash"}); b.x=a.x+60; a.input.aim=0; a.input.dashCount=a.input.dashCount+1; run(w,0.3)
    check("Razor Dash cuts", b.hp<b.stats.maxHp, b.hp) end
  -- Gun Toss.
  do local w,a,b=mk({"gun_toss"}); a.input.aim=0; a.input.meleeCount=a.input.meleeCount+1; a.input.meleeHeld=true; run(w,0.5); a.input.meleeHeld=false; run(w,1/30)
    local out=a.gunOut~=nil; run(w,2)
    check("Gun Toss throws the gun and it comes back", out and a.gunOut==nil, tostring(out)) end
  -- Rubber Room keeps bouncing.
  do local w,a=mk({"rubber_room"}); local bl=Bullet.new(a,a.x,a.y-100,0,-900); a:spawnBullet(-math.pi/2,1,false,1)
    run(w,0.05); local found
    for _,q in ipairs(w.bullets) do if q.owner==a and q.rubber then found=q end end
    check("Rubber Room bullets are bouncy", found and found.bounces>100, found and found.bounces) end
  -- Body Bounce: carries on to a second enemy.
  do local m=Map.parse(Map.serialize(base))
    local defs={} for i=1,3 do defs[i]={name="p"..i,input=Input.remote()} end
    local w=World.new(defs,999,{pickFrom=3,picksPerRound=1,weights=Cards.DEFAULT_RULES.weights,rarity={},disabled={},startCards=0,forceMap=m,barrier=false})
    local a,b,c=w.players[1],w.players[2],w.players[3]
    a.cards={Cards.byId.body_bounce}; a:recompute(); w:startRound(); w.state="playing"; run(w,0.5)
    b.invuln,c.invuln=0,0; a.x,b.x,c.x=300,500,500; c.y=b.y-140; b.vx,c.vx=0,0
    local bl=Bullet.new(a,a.x+30,b.y,1500,0); bl.gravity=0; require("game.abilities").shotDamage(a,bl); w:addBullet(bl); run(w,0.5)
    check("Body Bounce hits a second enemy", b.hp<b.stats.maxHp and c.hp<c.stats.maxHp, string.format("%d %d", b.hp, c.hp)) end
  -- Executioner.
  do local w,a,b=mk({"executioner"}); b.x=a.x+50; b.hp=b.stats.maxHp*0.2; a.input.aim=0; a.input.meleeCount=a.input.meleeCount+1; run(w,0.3)
    check("Executioner finishes low enemies", b.dead, b.hp) end
  -- Wager: start lower.
  do local w,a=mk({"wager"}); a.roundStartPending=true; run(w,0.1)
    check("Wager starts the round at 70% HP", a.hp<=a.stats.maxHp*0.7+0.01, a.hp) end
  -- Last Light.
  do local w,a,b=mk({"last_light"}); b.x=a.x+150; a:hit(a.stats.maxHp*0.8,0,0,0,b)
    check("Last Light blasts when you drop low", b.hp<b.stats.maxHp and (a.lastLightT or 0)>0, b.hp) end
  -- Final Gambit.
  do local w,a,b=mk({"final_gambit"}); b.x=a.x+150; a:hit(999,0,0,0,b)
    check("Final Gambit explodes on death", b.hp<b.stats.maxHp, b.hp) end
  -- Blood Ammo.
  do local w,a=mk({"blood_ammo"}); a.ammo=0; a.reloadTimer=5; local hp=a.hp; a.fireTimer=0; a:tryFire()
    check("Blood Ammo fires for HP when empty", a.hp<hp, hp-a.hp) end
  -- Upside Down: you end up near the top.
  do local w,a=mk({"upside_down"}); a.input.blockCount=a.input.blockCount+1; run(w,2)
    check("Upside Down sends you up to the ceiling", a.y<200, a.y) end
  -- Ice Wall: makes a wall that stops a bullet.
  do local w,a,b=mk({"ice_wall"},{}); a.facing=1; b.x=a.x+300; a.input.blockCount=a.input.blockCount+1; run(w,0.2)
    local wall; for _,e in ipairs(w.effects) do if e.type=="icewall" then wall=e end end
    check("Ice Wall goes up", wall and wall.body, tostring(wall))
    if wall then local hp=wall.hp; local bl=Bullet.new(b,b.x-30,wall.y,-1500,0); bl.gravity=0; w:addBullet(bl); run(w,0.4)
      check("Ice Wall takes the bullet", wall.hp<hp and a.hp==a.stats.maxHp, string.format("%s %s", tostring(wall.hp), a.hp)) end end
  -- Remote Charge: shot sticks, block detonates.
  do local w,a,b=mk({"remote_charge"}); a.x,b.x=300,700; a.input.aim=0; a.fireTimer=0; a:tryFire(); run(w,0.6)
    local ch; for _,e in ipairs(w.effects) do if e.type=="charge" then ch=e end end
    local hp=b.hp; a.input.blockCount=a.input.blockCount+1; run(w,0.1)
    check("Remote Charge sticks and detonates on block", ch~=nil and b.hp<hp, tostring(ch)) end
  -- Grenadier.
  do local w,a=mk({"grenadier"}); a.shotCount=4; a.fireTimer=0; a.ammo=3; a.input.aim=-1; a:tryFire(); run(w,0.05)
    local gren; for _,q in ipairs(w.bullets) do if q.grenadeT then gren=q end end
    check("Grenadier's 5th shot is a grenade", gren~=nil) end
  -- Bee Swarm.
  do local w,a,b=mk({"bee_swarm"}); a.x,b.x=300,500; local bl=shootAt(w,a,b); require("game.abilities").shotDamage(a,bl); run(w,0.2)
    local bees=0; for _,q in ipairs(w.bullets) do if q.isBee then bees=bees+1 end end
    check("Bee Swarm releases a bee on hit", bees>0, bees) end
  -- Mine Layer.
  do local w,a=mk({"mine_layer"}); run(w,4.5); local n=0; for _,q in ipairs(w.bullets) do if q.fromMineDrop then n=n+1 end end
    check("Mine Layer drops mines", n>0, n) end
  -- Totem: faster reload near it.
  do local w,a=mk({"totem"}); a.input.blockCount=a.input.blockCount+1; run(w,0.1)
    check("Totem speeds up reloading nearby", require("game.abilities").reloadRate(a)>1) end
  -- Frostbite: long slow freezes.
  do local w,a,b=mk({"frostbite"}); b.slowTimer=3; run(w,2.2)
    check("Frostbite freezes after 2s of slow", (b.freezeT or 0)>0 or b.stunTimer>0, b.freezeT) end
  -- Plague: poison jumps.
  do local m=Map.parse(Map.serialize(base))
    local defs={} for i=1,3 do defs[i]={name="p"..i,input=Input.remote()} end
    local w=World.new(defs,999,{pickFrom=3,picksPerRound=1,weights=Cards.DEFAULT_RULES.weights,rarity={},disabled={},startCards=0,forceMap=m,barrier=false})
    local a,b,c=w.players[1],w.players[2],w.players[3]
    a.cards={Cards.byId.plague}; a:recompute(); w:startRound(); w.state="playing"; run(w,0.3)
    b.x,c.x=800,900; b:poisonFor(30,3); b.lastAttacker=a; run(w,2.5)
    check("Plague spreads poison", c.poisonTimer>0, c.poisonTimer) end
  -- Iron Will caps a hit.
  do local w,a,b=mk({"iron_will"}); local hp=a.hp; a:hit(200,0,0,0,b)
    check("Iron Will caps a big hit", not a.dead and hp-a.hp<=a.stats.maxHp*0.6+0.1, hp-a.hp) end
  -- Hemorrhage costs HP.
  do local w,a=mk({"hemorrhage"}); local hp=a.hp; a.fireTimer=0; a.input.aim=0; a:tryFire()
    check("Hemorrhage shots cost HP", a.hp<hp, hp-a.hp) end
  -- Reprise fires again.
  do local w,a=mk({"reprise"}); a.input.aim=-1.2; run(w,0.05); a.shotCount=3; a.fireTimer=0; a.ammo=3; a:tryFire(); local t0=a.repriseT; run(w,0.3)
    local n=0; for _,q in ipairs(w.bullets) do if q.owner==a then n=n+1 end end
    check("Reprise repeats every 4th shot", a.st.shots>=1 and a.repriseT==nil and n>=1, n) end
  -- Boomerang returns.
  do local w,a=mk({"boomerang"}); a.input.aim=0; a.fireTimer=0; a:tryFire(); run(w,0.05)
    local bl; for _,q in ipairs(w.bullets) do if q.owner==a then bl=q end end
    run(w,0.8); check("Boomerang turns back", bl and (bl.coming or bl.dead), tostring(bl and bl.coming)) end
  -- Guard Break.
  do local w,a,b=mk({"guard_break"}); b.x=a.x+60; b.blockTimer=1; a.input.aim=0; a.meleeCharge=2; a.charging=true; a:meleeRelease(); run(w,0.3)
    check("Guard Break shatters a block", b.blockTimer<=0 and b.blockCd>0 and a.stunTimer<=0, string.format("%.2f %.2f", b.blockTimer, a.stunTimer)) end
  -- Counterweight.
  do local w,a=mk({"counterweight"}); a.dashesLeft=0; a.dashCd=1; a.input.blockCount=a.input.blockCount+1; run(w,0.05)
    check("Counterweight refills the dash on block", a.dashesLeft>0 and a.dashCd==0) end
  -- Bleed.
  do local w,a,b=mk({"bleed_edge"}); b.x=a.x+50; a.input.aim=0; a.input.meleeCount=a.input.meleeCount+1; run(w,0.3)
    check("Bleed Edge makes hits bleed", (b.bleedT or 0)>0, b.bleedT) end
  -- Sap.
  do local w,a,b=mk({"sap"}); a.x,b.x=300,500; shootAt(w,a,b); run(w,0.3)
    check("Sap weakens", (b.sapT or 0)>0) end
  -- Thunder Step strikes along the dash.
  do local w,a=mk({"thunder_step"}); a.input.aim=0; a.input.dashCount=a.input.dashCount+1; run(w,0.3)
    local n=0; for _,e in ipairs(w.effects) do if e.type=="strike" then n=n+1 end end
    check("Thunder Step lays strikes along the path", n>=3, n) end
  -- Ward stops bullets.
  do local w,a,b=mk({"ward"}); b.x=a.x+300; a.input.blockCount=a.input.blockCount+1; run(w,0.4); a.x=a.x-0
    local bl=Bullet.new(b,b.x-30,a.y,-1500,0); bl.gravity=0; w:addBullet(bl); a.invuln=0; run(w,0.4)
    check("Ward stops enemy bullets", a.hp==a.stats.maxHp, a.hp) end
  -- Kinetic Guard charges the next shot.
  do local w,a,b=mk({"kinetic_guard"}); a.x,b.x=300,700; a.input.blockCount=a.input.blockCount+1; run(w,0.05)
    local bl=Bullet.new(b,b.x-30,a.y,-1800,0); bl.gravity=0; w:addBullet(bl); run(w,0.4)
    check("Kinetic Guard stores damage from blocked bullets", (a.kineticBonus or 0)>0, a.kineticBonus) end
  -- Overdrive stacks.
  do local w,a=mk({"overdrive"}); for k=1,2 do a.dashCd=0; a.dashesLeft=1; a.input.dashCount=a.input.dashCount+1; run(w,0.3) end
    check("Overdrive stacks on quick dashes", (a.overdriveStacks or 0)>=2, a.overdriveStacks) end
  -- Gravity bomb.
  do local w,a=mk({"gravity_bomb"}); a.fireTimer=0; a.input.aim=0; a:tryFire(); run(w,1.5)
    check("Gravity Bomb opens a well", #w.wells>0, #w.wells) end
  -- Shield Drone stops a bullet.
  do local w,a,b=mk({"shield_drone"}); local hits=0
    for k=1,30 do local dx,dy=require("game.abilities").dronePos(a,1); local bl=Bullet.new(b,dx+40,dy,-900,0); bl.gravity=0; w:addBullet(bl); run(w,1/30) end
    check("Shield Drone stops bullets", a.droneCd and (a.droneCd[1] or 0)>0, a.droneCd and a.droneCd[1]) end
end
