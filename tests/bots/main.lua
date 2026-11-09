io.stdout:setvbuf("no")
local repo=os.getenv("DECKSHOT_REPO")
package.path=repo.."/?.lua;"..package.path
function love.load()
  love.math.setRandomSeed(tonumber(os.getenv("SEED")) or os.time())
  local sfx=require "gfx.sfx"; sfx.silent=true
  local Map=require "game.map"; local World=require "game.world"; local Input=require "core.input"
  local Cards=require "game.cards"; local Objects=require "game.objects"; local fx=require "gfx.fx"
  local Physics=require "game.physics"
  World.setSlotColors({1,2,3,4})
  local function rules(m) return {pickFrom=3,picksPerRound=1,weights=Cards.DEFAULT_RULES.weights,rarity={},disabled={},startCards=0,forceMap=m} end
  local totals,ok={},true
  local typeCount={}
  print("maps",#Map.list)
  local worstMs=0
  local kills,flung,stuckRounds=0,0,0
  for mi,m in ipairs(Map.list) do
    local defs={}
    for i=1,4 do defs[i]={name="b"..i,input=Input.bot(3),bot=3} end
    local w=World.new(defs,999,rules(m))
    w:startRound()
    local t=0
    local firstCheck=false
    local start={}
    for _,o in ipairs(w.objects) do if o.loose then start[o]={o.x,o.y}; end
      local k=o.type..(o.anchored and ":anchored" or (o.loose and ":loose" or ":fixed")); typeCount[k]=(typeCount[k] or 0)+1 end
    local roundsDone=0
    local sawRoundOver=false
    while t<45 do
      local dt=1/60
      local c=love.timer.getTime()
      local good,err=xpcall(function() w:update(dt) end,debug.traceback)
      worstMs=math.max(worstMs,(love.timer.getTime()-c)*1000)
      if not good then print("ERROR on",m.name,err); ok=false; break end
      fx.update(dt)
      t=t+dt
      if w.state=="playing" and not firstCheck and w.time>1.2 then
        firstCheck=true
        for o,s in pairs(start) do
          local d=math.sqrt((o.x-s[1])^2+(o.y-s[2])^2)
          if o.alive and d>40 and not o.rope and o.type~="crate" and o.type~="barrel" and o.type~="gas" then
            flung=flung+1; print("MOVED at start",m.name,o.type,o.index,math.floor(d)) end
          if o.alive and o.rope and d>25 then print("ROPE moved",m.name,o.type,o.index,math.floor(d)) end
        end
      end
      for _,o in ipairs(w.objects) do
        if o.alive and (o.x~=o.x or o.y~=o.y or (o.rot and o.rot~=o.rot)) then print("NAN",m.name,o.type); ok=false end
      end
      if w.state=="roundOver" then sawRoundOver=true end
      if (w.state=="cardPick" and not w.pick) or w.state=="matchOver" then w:startRound() end
      if w.state=="cardPick" and w.pick then local pk=w.pick; w:choose(pk.slot,1,pk.serial) end
      if w.state=="mapVote" then w:beginRound() end
    end
    if not sawRoundOver then stuckRounds=stuckRounds+1; print("NO ROUND END in 45s",m.name) end
    if not ok then break end
  end
  print("flung",flung,"stuck maps",stuckRounds,"worst update ms",worstMs)
  local keys={} for k in pairs(typeCount) do keys[#keys+1]=k end table.sort(keys)
  for _,k in ipairs(keys) do print(k,typeCount[k]) end
  print(ok and "DONE OK" or "FAILED")
  love.event.quit(ok and 0 or 1)
end
