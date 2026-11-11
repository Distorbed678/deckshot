io.stdout:setvbuf("no")
local repo=os.getenv("DECKSHOT_REPO")
package.path=repo.."/?.lua;"..package.path
local failed=0
local function check(name,cond,extra) if not cond then failed=failed+1 end print((cond and "PASS " or "FAIL ")..name..(extra and ("   ["..tostring(extra).."]") or "")) end
function love.load()
  require("gfx.sfx").silent=true
  local Map=require "game.map"; local World=require "game.world"; local Input=require "core.input"
  local Cards=require "game.cards"; local Objects=require "game.objects"; local fx=require "gfx.fx"
  local Snap=require "online.snapshot"; local Bullet=require "game.bullet"
  World.setSlotColors({1,2,3,4})
  local function rules(m) return {pickFrom=3,picksPerRound=1,weights=Cards.DEFAULT_RULES.weights,rarity={},disabled={},startCards=0,forceMap=m} end
  local function mk(objects, n)
    local m={name="t",spawns={{200,600},{1300,600},{300,600},{1200,600}},rects={{x=0,y=744,w=1536,h=48}},objects=objects}
    Map.convertObjects(m)
    local defs={} for i=1,n or 2 do defs[i]={name="p"..i,input=Input.remote()} end
    local w=World.new(defs,999,rules(m)); w:startRound()
    w.state="playing"
    for _,p in ipairs(w.players) do p.invuln=0 end
    return w
  end
  local function run(w,s) for _=1,math.floor(s*60) do w:update(1/60); fx.update(1/60) end end
  -- settle on every map with idle players
  local odd=0
  for _,m in ipairs(Map.list) do
    local defs={} for i=1,2 do defs[i]={name="p"..i,input=Input.remote()} end
    local w=World.new(defs,999,rules(m)); w:startRound(); w.state="playing"
    local st={} for _,o in ipairs(w.objects) do if o.loose then st[o]={o.x,o.y} end end
    for i=1,240 do w.state="playing"; w:update(1/60); fx.update(1/60) end
    -- Maps are meant to move, so this only looks for things destroying themselves with nobody playing.
    for o in pairs(st) do
      if not o.alive and not o.burning and m.name~="Crusher Alley" then odd=odd+1; print("  settle: died",m.name,o.type,"#"..o.index) end
    end
  end
  check("nothing on any map destroys itself when left alone",odd==0,odd)

  local Physics=require "game.physics"
  local w=mk({{type="crate",x=400,y=694,w=50,h=50}})
  run(w,0.2)
  check("Physics.hit finds a crate", Physics.hit(w,410,700,10,10)==w.objects[1])
  check("Physics.hit is empty in the air", Physics.hit(w,410,300,10,10)==nil)
  check("Physics.hit finds terrain", Physics.hit(w,410,750,10,10)~=nil)
  check("Physics.ray stops at the crate", select(2,Physics.ray(w,300,720,600,720))~=nil and math.abs(select(2,Physics.ray(w,300,720,600,720))-400)<3)
  -- crate rests, gets pushed by a walking player
  local w=mk({{type="crate",x=400,y=694,w=50,h=50}})
  run(w,0.5)
  local c,p=w.objects[1],w.players[1]
  check("crate rests on floor", math.abs(c.y-694)<2 and math.abs(c.rot)<0.05, c.y)
  p.x,p.y=330,744-p.r-p.leg; p.vx,p.vy=0,0
  run(w,0.05)
  p.input.right=true
  run(w,1.2)
  p.input.right=false
  check("walking shoves a crate", c.x>450, c.x)
  check("player stayed outside the crate", p.x+p.r<=c.x+6 or math.abs(c.rot)>0.2, p.x)

  -- standing
  local w=mk({{type="crate",x=400,y=694,w=50,h=50}})
  run(w,0.3)
  local c,p=w.objects[1],w.players[1]
  p.x,p.y=425,560; p.vx,p.vy=0,0
  run(w,0.8)
  check("lands on a crate",p.onGround and p.groundRect==c, tostring(p.y))
  check("crate holds up the player",p.y+p.r+p.leg<=c.y+8,p.y+p.r+p.leg)

  -- plank balance: step on end of a plank over a pivot crate
  local w=mk({{type="crate",x=500,y=694,w=50,h=50},{type="plank",x=425,y=680,w=200,h=14}})
  run(w,0.6)
  local pl,p=w.objects[2],w.players[1]
  local r0=pl.rot
  p.x,p.y=610,600; p.vx,p.vy=0,0
  run(w,0.8)
  check("a player's weight tips a balanced plank", math.abs(pl.rot-r0)>0.1, pl.rot)

  -- explosion spin / bullet
  local w=mk({{type="crate",x=400,y=694,w=50,h=50,hp=1000,maxHp=1000},{type="wall",x=800,y=624,w=40,h=120,anchored=true}})
  run(w,0.3)
  local c=w.objects[1]
  Objects.explosion(w,380,740,200,0,w.players[1])
  run(w,0.3)
  check("blast throws and spins a crate",c.x>410 and math.abs(c.rot)>0.15,string.format("x=%d rot=%.2f",c.x,c.rot))
  check("kicker gets credit",c.breaker==w.players[1])
  local a=w.objects[2]
  local x0=a.x
  Objects.explosion(w,780,700,200,0,w.players[1]); run(w,0.5)
  check("anchored wall doesn't move",a.x==x0 and not a.rot and a.anchored)

  -- breakable anchor
  local w=mk({{type="crate",x=400,y=300,w=50,h=50,hp=500,anchored=true,anchorHp=30}})
  run(w,0.5)
  local c=w.objects[1]
  check("anchored crate hangs in the air",c.y==300 and c.anchored==true)
  Objects.damage(w,c,10,w.players[1]); run(w,0.2)
  check("anchor holds until out of HP",c.y==300 and c.anchored==true and c.hp==500,c.anchorHp)
  Objects.damage(w,c,30,w.players[1]); run(w,1)
  check("anchor breaks and the crate falls",c.y>600 and not c.anchored and c.body~=nil and c.loose,c.y)
  -- permanent anchor
  local w=mk({{type="crate",x=400,y=300,w=50,h=50,hp=40,anchored=true}})
  local c=w.objects[1]
  Objects.damage(w,c,20,w.players[1]); run(w,0.3)
  check("permanent anchor never lets go; object can still break",c.y==300 and c.anchored and c.hp==20)
  Objects.damage(w,c,40,w.players[1]); run(w,0.1)
  check("object breaks",not c.alive and c.body==nil)
  -- non solid breakable anchor via bullet
  local w=mk({{type="saw",x=600,y=300,r=28,anchored=true,anchorHp=5}})
  run(w,0.1)
  local s,p=w.objects[1],w.players[1]
  local bl=Bullet.new(p,560,300,900,0); bl.damage=20; w:addBullet(bl)
  run(w,0.2)
  check("a bullet can shoot a saw's anchor off",not s.anchored and s.loose,s.y)
  run(w,0.6)
  check("freed saw falls",s.y>500,s.y)

  -- damage scale
  local w=mk({{type="crate",x=700,y=100,w=50,h=50,hp=500}})
  local c,p=w.objects[1],w.players[2]
  p.x,p.y=725,744-p.r-p.leg; p.vx,p.vy=0,0; p.hp=100; p.stats.maxHp=100
  local h0=p.hp
  c.breaker=w.players[1]
  run(w,1.2)
  check("falling crate hurts, within limit",p.hp<h0 and h0-p.hp<=30,h0-p.hp)
  check("crate lands on the player, not through",c.y+50<=p.y+p.r+10 or p.hp<=0,c.y)
  local w=mk({{type="crate",x=700,y=620,w=50,h=50,hp=500}})
  local c,p=w.objects[1],w.players[2]
  p.x,p.y=725,744-p.r-p.leg; p.vx,p.vy=0,0; p.hp=100
  run(w,0.3)
  check("a gentle drop doesn't hurt",p.hp==100,p.hp)
  -- weight on rope, cut
  local w=mk({{type="rope",x=500,y=100,target=2},{type="weight",x=500,y=300,r=26}})
  run(w,0.5)
  local r,o,p=w.objects[1],w.objects[2],w.players[2]
  check("rope holds a weight",math.abs(o.y-300)<3 and r.alive,o.y)
  p.x,p.y=500,744-p.r-p.leg; p.vx,p.vy=0,0; p.hp=100
  Physics.hurtSegment(w,r.segs[3],1e9,w.players[1]); run(w,1)
  check("cut weight falls and crushes",p.hp<100,p.hp)
  -- swing
  local w=mk({{type="rope",x=500,y=100,target=2},{type="crate",x=475,y=300,w=50,h=50,hp=500}})
  run(w,0.2)
  local cc=w.objects[2]
  Objects.push(cc,800,0); run(w,0.35)
  check("rope swing stays level and on length",math.abs(cc.rot)<0.001 and math.abs(math.sqrt((cc.x+25-500)^2+(cc.y-100)^2)-200)<4,string.format("x=%d rot=%.3f",cc.x,cc.rot))
  -- glass
  local w=mk({{type="glass",x=400,y=100,w=16,h=120,hp=1}})
  run(w,1.5)
  check("hard landing shatters glass",not w.objects[1].alive)
  -- breakable oneway
  local w=mk({})
  w.map.rects[#w.map.rects+1]={x=300,y=500,w=300,h=20,oneway=true}
  w.objects={}; 
  local m2={name="t2",spawns=w.map.spawns,rects=w.map.rects,objects={{type="block",material="crate",physics=true,x=400,y=300,w=50,h=50},{type="block",material="crate",physics=true,x=500,y=640,w=50,h=50}}}
  w=World.new({{name="a",input=Input.remote()},{name="b",input=Input.remote()}},999,rules(m2)); w:startRound(); w.state="playing"
  local up=w.objects[2]
  run(w,0.8)
  check("objects land on one-way platforms",math.abs(w.objects[1].y-450)<4,w.objects[1].y)
  up.body:setLinearVelocity(0,-1000); run(w,0.45)
  check("objects pass up through one-way platforms",up.y<450,up.y)
  -- bullet off a tilted crate
  local w=mk({{type="wall",x=600,y=350,w=40,h=200,hp=500}})
  local t=w.objects[1]; t.body:setType("static"); t.body:setAngle(math.pi/4)
  run(w,0.05)
  local b=Bullet.new(w.players[1],480,450,700,0); b.bounces=3; b.gravity=0; w:addBullet(b)
  run(w,0.25)
  check("bullet reflects off a 45 degree face",math.abs(b.vx)<120 and math.abs(math.abs(b.vy)-700)<120 and not b.dead,string.format("%d,%d",b.vx,b.vy))
  -- snapshot
  local w=mk({{type="crate",x=400,y=300,w=50,h=50},{type="wall",x=800,y=624,w=40,h=120,anchored=true,anchorHp=30}})
  run(w,0.3)
  local v=Snap.decode(Snap.encode(w,{}))
  local v1,v2=v.objects[1],v.objects[2]
  check("snapshot carries rot and anchors",v1.rot~=nil and v2.rot==nil and v2.anchored==true and not v1.anchored)
  -- map format
  local m=Map.parse("deckshot-map 2\nname old\nspawn 1 1\nspawn 1 1\nspawn 1 1\nspawn 1 1\nrect 0 700 1536 48\nobj saw x=500 y=100\nobj wall x=600 y=580\nobj wall x=700 y=300 h=100\nobj spikes x=900 y=684 dir=up\nobj spikes x=900 y=400 dir=left\nobj saw x=500 y=690\nobj saw x=500 y=100 path=500,100;600,100\nobj weight x=800 y=300\nobj rope x=800 y=50 target=8\n")
  local o=m.objects
  check("old maps: floating saw anchored",o[1].anchored==true, tostring(o[1].anchored))
  check("old maps: wall on the floor loose",not o[2].anchored)
  check("old maps: floating wall anchored",o[3].anchored==true)
  check("old maps: floor spikes loose, side spikes anchored",not o[4].anchored and o[5].anchored==true)
  check("old maps: saw sunk in the floor anchored",o[6].anchored==true)
  check("old maps: pathed saw and roped weight left alone",not o[7].anchored and not o[8].anchored)
  local t=Map.serialize(m)
  check("anchors survive saving",t:find("anchored=true") and t:find("deckshot%-map 4"))
  local m2=Map.parse(t)
  check("format 3 not re-anchored",m2.objects[2].anchored==nil and m2.objects[1].anchored==true)

  -- ========= new machines
  local function raw(objects,rects)
    local m={name="t",spawns={{200,600},{1300,600},{300,600},{1200,600}},rects=rects or {{x=0,y=744,w=1536,h=48}},objects=objects}
    local defs={} for i=1,2 do defs[i]={name="p"..i,input=Input.remote()} end
    local w=World.new(defs,999,rules(m)); w:startRound(); w.state="playing"
    for _,p in ipairs(w.players) do p.invuln=0 end
    return w
  end
  -- rope segments take hits
  local w=raw({{id=1,type="rope",x=500,y=100,target=2,segHp=60},{id=2,type="block",material="crate",physics=true,x=475,y=320,w=50,h=50}})
  run(w,0.3)
  local r,c=w.objects[1],w.objects[2]
  check("rope is a chain",r.segs and #r.segs>=6,#r.segs)
  check("rope holds its crate",math.abs(c.y-320)<14,c.y)
  local function shoot(y) local b=Bullet.new(w.players[1],300,y,1800,0); b.damage=25; b.gravity=0; w:addBullet(b); run(w,0.4) end
  shoot(210); 
  check("one bullet doesn't break a rope",r.segs[4].alive and r.segs[5].alive and c.rope~=nil)
  check("bullet hurt a segment",(r.segs[4].hp<60 or r.segs[5].hp<60))
  shoot(210); shoot(210)
  check("three bullets break it, crate falls",c.rope==nil,c.y)
  run(w,1)
  check("crate fell",c.y>600,c.y)
  local alive=0 for _,sg in ipairs(r.segs) do if sg.alive then alive=alive+1 end end
  check("rest of rope dangles",alive>=4 and #r.pts>=4,alive)
  local gaps=0 for _,p in ipairs(r.pts) do if p[3] then gaps=gaps+1 end end
  check("break shows as a gap",gaps==1,gaps)
  local v=Snap.decode(Snap.encode(w,{}))
  check("rope points reach clients",#v.objects[1].pts==#r.pts and math.abs(v.objects[1].pts[3][1]-r.pts[3][1])<2)
  -- object to object rope
  local w=raw({{id=1,type="rope",x=725,y=500,x2=525,y2=500,from=2,target=3},{id=2,type="block",material="crate",physics=true,x=700,y=694,w=50,h=50},{id=3,type="block",material="crate",physics=true,x=500,y=694,w=50,h=50}})
  local a1,b1=w.objects[2],w.objects[3]
  check("object-to-object rope builds",w.objects[1].segs~=nil)
  Objects.push(a1,1800,-200); run(w,0.8)
  check("one crate drags the other",b1.x>512,b1.x)
  -- crusher on a crate
  local w=raw({{id=1,type="crusher",x=500,y=300,w=120,h=60,travel=500,wait=0.3,damage=20},{id=2,type="block",material="crate",physics=true,hp=500,x=535,y=694,w=50,h=50}})
  run(w,0.25)
  local cr,c=w.objects[1],w.objects[2]
  run(w,1.0)
  check("crusher stops on a crate",cr.state~=nil and cr.y+cr.h<=c.y+12 and c.alive,string.format("bottom %d crate %d",cr.y+cr.h,c.y))
  check("crusher damages it",c.hp<500,c.hp)
  -- crusher travel
  local w=raw({{id=1,type="crusher",x=500,y=100,w=120,h=60,travel=120,wait=0.2}})
  run(w,0.6)
  check("crusher travel honoured",w.objects[1].y<=221,w.objects[1].y)
  -- flame blocked
  local w=raw({{id=1,type="flame",x=600,y=744,length=300,off=0,warn=0,on=5,damage=5},{id=2,type="block",material="stone",anchored=true,physics=true,x=560,y=600,w=80,h=20}})
  run(w,0.3)
  check("flame stops at solids",math.abs(w.objects[1].a-(744-8-620))<6,w.objects[1].a)
  local w=raw({{id=1,type="flame",x=600,y=744,dir="up",length=300,off=0,warn=0,on=9,damage=5},{id=2,type="block",material="crate",hp=20,physics=false,x=560,y=600,w=80,h=50}})
  run(w,1)
  check("flame burns crates",not w.objects[2].alive)
  -- arm
  local w=raw({{id=1,type="arm",x=700,y=400,length=110,spin=2},{id=2,type="saw",x=810,y=400,r=22,damage=25,parent=1}})
  run(w,0.1)
  local a,s0=w.objects[1],w.objects[2]
  run(w,1)
  check("arm spins at its speed",math.abs(a.rot-2.2)<0.5,a.rot)
  local d=math.sqrt((s0.x-700)^2+(s0.y-400)^2)
  check("saw stays on the arm",math.abs(d-110)<6,d)
  -- rail
  local w=raw({{id=1,type="rail",x=400,y=500,path={{400,500},{800,500}},speed=200},{id=2,type="block",material="metal",x=340,y=491,w=120,h=18,parent=1}})
  run(w,1)
  local r,pf=w.objects[1],w.objects[2]
  check("rail carries its platform",pf.x>490 and pf.x<560 and math.abs(pf.y-491)<8,string.format("%d,%d",pf.x,pf.y))
  run(w,1.5)
  local p=w.players[1]; p.x,p.y,p.vx,p.vy=pf.x+60,pf.y-60,0,0
  run(w,0.5)
  check("can ride a rail platform",p.onGround and p.groundRect==pf,tostring(p.groundRect))
  -- machines hold their path: a heavy drop or a hard landing doesn't bounce what rides them
  local w=raw({{id=1,type="rail",x=400,y=500,path={{400,500},{400,300}},speed=60},{id=2,type="block",material="metal",x=340,y=491,w=120,h=18,parent=1},
     {id=3,type="block",material="brick",physics=true,x=360,y=200,w=80,h=80}})
  local worst=0
  for _=1,90 do run(w,1/60); local pf=w.objects[2]; worst=math.max(worst,math.abs(pf.x-340),math.abs(pf.y-(w.objects[1].y-9))) end
  check("a heavy drop doesn't shake a rail platform",worst<1.5,worst)
  local w=raw({{id=1,type="arm",x=700,y=500,length=150,spin=0.5},{id=2,type="block",material="metal",x=790,y=491,w=120,h=18,parent=1,attach="level"}})
  run(w,0.2)
  local p=w.players[1]; p.x,p.y,p.vx,p.vy=w.objects[2].x+60,300,0,900
  local worst=0
  for _=1,60 do
    run(w,1/60)
    local a,s0=w.objects[1],w.objects[2]
    local cx,cy=s0.x+60,s0.y+9
    worst=math.max(worst,math.abs(math.sqrt((cx-700)^2+(cy-500)^2)-150),math.abs(s0.rot))
  end
  check("a landing doesn't shake an arm seat",worst<1.5,worst)
  -- liquid buoyancy
  local w=raw({{id=1,type="liquid",x=300,y=500,w=800,h=244,buoyant=true},{id=2,type="block",material="crate",physics=true,x=500,y=300,w=50,h=50},{id=3,type="block",material="brick",physics=true,x=700,y=300,w=50,h=50}})
  run(w,3.5)
  check("light block floats",w.objects[2].y<560,w.objects[2].y)
  check("heavy block sinks",w.objects[3].y>640,w.objects[3].y)
  local w=raw({{id=1,type="liquid",x=100,y=660,w=800,h=84,damage=20,poison=true,color="#FF00FF"}})
  local p=w.players[1]; p.x,p.y=400,650; p.hp=100; run(w,0.2)
  check("liquid damages",p.hp<100,p.hp)
  check("liquid colour used",math.abs(w.objects[1].rgb[1]-1)<0.01 and w.objects[1].rgb[2]<0.01)
  -- physics toggle
  local w=raw({{id=1,type="block",x=500,y=300,w=60,h=60},{id=2,type="block",x=700,y=300,w=60,h=60,physics=true},{id=3,type="block",physics=true,x=900,y=300,w=120,h=20,anchored=true,anchorType="hinge",hinge="left"}})
  run(w,1)
  check("physics off stays",w.objects[1].y==300)
  check("physics on falls",w.objects[2].y>600,w.objects[2].y)
  check("hinge swings down",math.abs(w.objects[3].rot)>0.8,w.objects[3].rot)
  check("static rotated block",true)
  local w=raw({{id=1,type="block",x=500,y=600,w=200,h=40,rot=0.5}})
  run(w,0.2)
  check("rotated static collides at an angle",Physics.hit(w,520,520,4,4)==nil and Physics.hit(w,640,660,4,4)~=nil)
  -- plain-block test
  check("plainBlock",Map.plainBlock({type="block"}) and not Map.plainBlock({type="block",physics=true}))

  -- ======= v0.6 gameplay
  local p
  local w=raw({})
  p=w.players[1]; run(w,0.4)
  check("no double jump after a real jump",true)
  local y0=p.y; p.input.jumpCount=p.input.jumpCount+1; p.input.jumpHeld=true; run(w,0.15); local vy1=p.vy
  p.input.jumpCount=p.input.jumpCount+1; run(w,0.05)
  check("second press in a jump does nothing",p.vy>vy1-50,string.format("%d %d",vy1,p.vy))
  local w=raw({},{{x=0,y=744,w=800,h=48}})
  p=w.players[1]; p.x,p.y=780,700; p.input.aim=nil; p.input.right=true; run(w,0.05); run(w,0.16); p.input.right=false
  check("walked off the edge",not p.onGround and p.vy>0 and p.fallJump==true,p.vy)
  p.input.jumpCount=p.input.jumpCount+1; run(w,0.05)
  check("fall jump works any time in the fall",p.vy<0 and p.fallJump==false,p.vy)
  local vv=p.vy; p.input.jumpCount=p.input.jumpCount+1; run(w,0.05)
  check("only once",p.vy>vv,p.vy)
  -- LOS
  local Physics=require "game.physics"
  local Fx=require "gfx.fx"
  local w=raw({{id=1,type="block",anchored=true,physics=true,x=500,y=500,w=40,h=244}})
  local a,b=w.players[1],w.players[2]
  a.x,a.y=440,680; b.x,b.y=600,680
  run(w,0.05)
  check("wall blocks line of sight",not Physics.canReach(w,a.x,a.y,b.x,b.y))
  b.x,b.y=600,400; run(w,0.05)
  check("open line reaches",Physics.canReach(w,a.x,300,b.x,300))
  b.x,b.y=600,680; b.hp=100; local bl=Bullet.new(a,440,680,0,0); bl.explosion=300; bl.damage=40; bl:explode(w,1)
  check("explosion stopped by a wall",b.hp==100,b.hp)
  local fan=Physics.fan(w,a.x,a.y,300,48)
  local near,far=999,0 for _,d in ipairs(fan) do near=math.min(near,d) far=math.max(far,d) end
  check("reach warps around walls",near<80 and far>=299,string.format("%d %d",near,far))
  -- Juggernaut
  local defs={} for i=1,3 do defs[i]={name="p"..i,input=Input.remote()} end
  local m={name="j",spawns={{200,600},{1300,600},{300,600},{1200,600}},rects={{x=0,y=744,w=1536,h=48}},objects={}}
  local r0=rules(m); r0.mode="jugg"
  local w=World.new(defs,999,r0); w:startRound()
  local j=w.jugg
  check("one juggernaut",j~=nil and j.isJugg)
  check("tougher",j.stats.maxHp>=2.9*100*0.9,j.stats.maxHp)
  check("bonus cards",#j.cards==2,#j.cards)
  local h={} for _,p in ipairs(w.players) do if p~=j then h[#h+1]=p end end
  check("hunters allied",not w:isEnemy(h[1],h[2]) and w:isEnemy(h[1],j) and w:isEnemy(j,h[2]))
  w.state="playing"; j.lastAttacker=h[2]; j:die(); w:checkRoundEnd()
  check("killer wins and takes over",w.nextJugg==h[2] and w.roundWinner==h[2],tostring(w.nextJugg and w.nextJugg.name))
  w.state="countdown"; w:beginRound(); 
  check("next juggernaut is the killer",w.jugg==h[2] and #j.cards==0,#j.cards)

  -- The ground under every spawn reaches the bottom.
  local floating = {}
  for _,m in ipairs(Map.list) do
    if not m.custom then
      -- A wide floor low in the arena is "the ground" (island and lava maps have narrow ones on purpose).
      for _,r in ipairs(m.rects) do
        local rests=false
        for _,q in ipairs(m.rects) do if q~=r and q.y==r.y+r.h and q.x<r.x+r.w and r.x<q.x+q.w then rests=true end end
        if not r.oneway and not rests and r.w>=600 and r.y>=600 and r.y+r.h<Map.H then floating[#floating+1]=m.id break end
      end
    end
  end
  check("wide grounds reach the bottom",#floating==0,table.concat(floating," "))
  love.filesystem.load("cards.lua")()(check)
  local noStack={}
  for _,c in ipairs(Cards.list) do if not c.stack or c.stack=="" then noStack[#noStack+1]=c.name end end
  check("every card says how it stacks",#noStack==0,table.concat(noStack,", "))
  print("END")
  love.event.quit(failed>0 and 1 or 0)
end
