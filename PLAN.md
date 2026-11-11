# v0.7 plan

Everything below is a proposal for you to edit. Nothing is implemented yet.

**About ROUNDS:** I won't extract or decompile files from the ROUNDS install, and I won't port its cards or maps under new names. All the cards and maps below are original designs. They use mechanics that are common to the genre (bouncing, homing, block-triggered effects, statuses), the same way the game already does. I left out ROUNDS' card names, and any card that copies one of its cards one to one.

Rules every new card follows (from CLAUDE.md and your memory notes):
- every card stacks
- no easy healing
- no synergy bonuses
- works with 4 players
- effects go through the existing systems (triggers, `world.effects`, child bullets)

Online play: `session.PROTOCOL` → `"14"`. New effects, statuses and turret state change the snapshot.

## What I took from ROUNDS (research, from its community wiki)
The wiki lists all 67 cards with their stats; it has no map pages. What the card list shows:
- **Pacing:** players start with 3 ammo and a shot takes about 60% of a player's HP, so 2 hits kill. Ours: 25 damage against 100 HP, so 4 hits kill. Rounds there are short and a single +X% damage card matters a lot. **See question Q4.**
- **A fixed tax on effects:** almost every gun effect card costs +0.25s reload (bigger ones +0.5s), and almost every block card is "+30% HP, +0.25s block cooldown". Effects are paid for in reload and block time rather than in custom downsides, so a deep stack slows you down in a readable way. **See question Q5.**
- **Rarity:** commons are plain numbers (some big: +100% HP, +100% damage with -2 ammo). Uncommons are a stat plus one effect. Rares are rule changers (revive, block teleport, steering, reload on block, block back on damage). There's no epic or legendary tier.
- **Block is the main build axis:** about 16 of 67 cards trigger on block. There are no melee or dash cards at all. So our melee, dash, status and gadget sets are where Deckshot can stand apart. The new block cards below avoid what ROUNDS already does there (bombs, slows, pulls, saws, teleports, echoes) and add parries, stored blocks, wards and bunkering instead.
- **Overlap:** much of our current deck already mirrors ROUNDS mechanics closely (Payback, Undertow, Pulse Ring, Carpet Bomb, Aftershock, Charged Guard, Fresh Start, Spare Life, Sweep, Slow Burn, Snowball, Pursuit, Top Up, Last Word, ...). That's fine for familiar basics, but the 100 new cards deliberately go elsewhere. Three of my new names borrowed ROUNDS words (Supernova, Echo), so they're renamed below.
- **Maps:** from what's generally known about ROUNDS, its arenas are single-screen rooms of plain blocks with lots of loose and hanging physics boxes and very few machines or hazards. Ours lean much more on machines. **See question Q6.**

---

## Part A: bugs and fixes

| # | Item | Cause / plan |
|---|---|---|
| 1 | Steam invite button doesn't work | The lobby's "Steam Invite..." calls `ActivateGameOverlayInviteDialog`, which silently does nothing when the Steam overlay isn't running, e.g. the game wasn't launched through Steam (an AppImage or `love .` started outside Steam). Fix: check `Utils.IsOverlayEnabled()`; when the overlay is off, open our own friends picker (the friends list already in the lobby, as a popup) and say why. Also add the invite button to the in-match pause menu (online, Steam). **See question Q1.** |
| 2 | Hold down to drop through one-way platforms | Terraria-style: while down is held you don't land on one-way platforms (you fall through every one you meet), and releasing it makes them solid again. Down + jump keeps working. Bots use the same rule. Goes in the prediction fields (down is already sent). |
| 3 | Maps not aligned to the grid (e.g. Home Plate) | The generated maps were never on the editor's 24 px grid, and my v0.6.2 nudges moved some more. Snap every built-in map's blocks, objects, ropes and spawns to 24 px (12 px for thin heights like one-way platforms), keep mirrored pairs symmetric, then re-run the reachability check and the bot suite. |
| 4 | Lasers go through other objects | The beam is marched with box tests against `world.solids` only, and it hurts every player along its whole length. Fix: cast a Box2D ray (`Physics.ray`) that stops at the first solid, loose prop, weight, saw, crate or **player**. Only that first player is hit, and the beam visibly ends on them. Lasers on arms also follow the arm's rotation. |
| 5 | Platforms on arms rotate with the arm | New "Stay level" toggle on attached objects (Edit Object popup, saved as `level=true`). A level child rides the end of the arm but keeps its own angle (0), like a Ferris wheel. Carousel and Clockwork use it. |
| 6 | Grounds float above the bottom edge | Home Plate, Ziggurat, Crossfire, Facets and any others found by a check: extend the ground blocks down to the bottom of the arena (`Map.H`). A check is added to `Editor:validate()` as a warning, and to the tests. |
| 7 | Weights can't be collided with | Weights hanging on ropes have a collision mask that skips players. Make them solid to players and props, still hurting on a fast hit (`damage`), and shovable when they swing. |
| 8 | Scoreboard cut off | The Ping column runs past the panel. Recompute column widths from the panel width, shrink the name column, and fit the numbers with `ui.printFit`. Test at 2, 3 and 4 players and at the larger text sizes. |
| 9 | Limbs overstretch, mostly at spawn | The physics limbs take their lengths from the spring points (`b.gunE`, `b.knee`, ...) when they're built. After a death the rig is rebuilt from the old points, and when a player respawns within 260 px of where they died, those points are stale and can be hundreds of px away, so the rebuilt limbs are huge. Fix: build limbs from fixed lengths based on the body size, posed around the player, and reset the spring points whenever a rig is built or a round starts. Add a harness that respawns players at many distances and asserts limb lengths. |
| 10 | Replay UI at the bottom with a timeline | See the mockup in Part E. Seeking backwards replays the message stream from the start at high speed (simple and exact). |
| 11 | Card editor overhaul + stat audit | See the mockup in Part E, plus a Settings option for the input method used in tests ("Test with: keyboard / mouse / gamepad / ask"). |

---

## Part B: changes to existing cards

### Removed (9)
Hill Runner, Reload Roll, Edge Padding, Hazard Suit, Wrecker, Wall Spring, Skyshot, Mag Dump, Tangle.
Their files move to `legacy/cards/`. Their stats and code stay unless they become dead (the stat audit decides).

### Specific requests
| Card | Change |
|---|---|
| Singularity Rounds, Collapse | Black holes no longer pull or hurt their owner (or teammates). Pull +25%, damage +50%. |
| Thunderhead | Charges in 0.5s (was 0.75s), strikes for 50 (was 30), every 5s. New look: a crackling ring marks the target during the charge, then a jagged, branching bolt drops from the top of the arena with a flash and a scorch mark on the ground. |
| Spare Life ↔ Death's Door | Spare Life becomes **legendary** with -50 max HP (was -35). Death's Door becomes **epic**. |
| Looking Glass | The mirrored shot fires 1s after yours. |
| Miasma | Rare → **epic**. |
| Stillness | A circular charge ring fills around you while you stand still. A chime and a star-shaped glint on the muzzle when it's charged; the glint stays until you fire. The charged shot is a Sunbeam-style laser beam with the +200% damage. |
| Turret Buddy | A round turret with a barrel floats above you and aims at its target. Each copy adds one turret (they space out in an arc). Each fires once a second at the nearest visible enemy, with your bullet stats and effects at 40% of their values (damage, size, speed, bounces, poison, explosions, ...). With Sunbeam its shots are beams too. |
| Joystick | Live bullets keep turning toward where you're aiming right now: your cursor, or a point along your stick aim. You can curve shots around cover. Bullets are 40% slower and -25% damage; each extra copy turns sharper. |
| Bloodhound, Bank Shot (and every homing effect) | Bullets only home on enemies inside a **45° cone** ahead of the bullet and in line of sight. Each homing player's cone is drawn faintly from their gun for everyone to see. Turn rates cut ~40%. Bloodhound: -25% damage stays. |
| All bullets | Bullet size grows with the square root of damage relative to base: 4x damage ≈ 2x size. Hitbox and visuals both. Bullet Size cards multiply on top. |
| All cards | Every card shows its stacking line (item 13). Cards that simply add their stats again get an automatic line, e.g. "Stacking: adds the same again". The test fails if any card has no stacking text. |

### Pacing and the standard tax (decided: Q4, Q5)
- **3 hits to kill:** base gun damage 25 → 34 (100 HP). Every damage, HP and armor number in this plan gets re-tuned around it in the win-rate pass. Armor and flat damage effects scale by about 1.35.
- **Standard tax on effect cards** (custom downsides only where a card needs one):

  | Card type | Tax |
  |---|---|
  | Gun effect | +0.25s reload (strong ones +0.5s) |
  | Block trigger | +0.25s block cooldown, +20 HP |
  | Dash effect | +0.1s dash cooldown (base is 0.6s) |
  | Melee effect | +0.1s melee cooldown (base is 0.45s) |
  | Gadgets | nothing extra (they live on another card's trigger), unless strong |

  The new cards below get this tax added on top of what's written. Existing effect cards are brought into line.

### Rarity rules (item 27)
- **Common:** one stat, about +30%, sometimes with a small cost. No effects.
- **Uncommon:** a stat plus a small effect, or one clear effect.
- **Rare:** a new mechanic.
- **Epic:** build-defining, with a real cost.
- **Legendary:** rule-bending.

Commons that have effects move up to uncommon: Chill Rounds, Cold Slam, Kickback, Three-Round, Venom Tip.

### Common nerfs (item 26): proposed new values
| Card | Now | New |
|---|---|---|
| Afterburn | -30% dash cd, +15% dash speed | -25% dash cooldown |
| Coil Springs | +25% jump | +15% jump |
| Deep Pockets | +4 ammo | +3 ammo |
| Fat Rounds | x1.8 size, +15% dmg, +0.25s reload | +60% bullet size, -10% bullet speed |
| Flat Shot | no drop, +60% speed | no bullet drop, +20% speed |
| Fleet | +20% speed | +12% speed |
| Greased Slide | -40% reload | -25% reload time |
| Guard Drill | -30% block cd, +25 HP | -20% block cooldown |
| Heavy Bat | +60% melee knockback, +15% dmg | +40% melee knockback |
| Hollow Point | +60% dmg, +0.25s reload | +30% gun damage, +0.25s reload |
| Hot Load | +120% bullet speed, +0.25s reload | +60% bullet speed, +0.15s reload |
| Knuckle Wraps | +50% melee dmg | +30% melee damage |
| Light Frame | -3 radius, -10 HP | unchanged |
| Light Trigger | +60% fire rate, -20% dmg | +30% fire rate, -10% damage |
| Long Arm | +40% melee range | +30% melee range |
| Long Barrel | x2 speed, +40% dmg, x2 fire delay | +35% gun damage, -30% fire rate |
| Long Guard | +0.25s block time | +0.15s block time |
| Pinball | +2 bounces, +15% dmg, +0.25s reload | +1 bounce |
| Plating | +4 armor, -5% speed | +3 armor, -5% speed |
| Pounce | +50% heavy lunge, +15% range | +40% heavy lunge |
| Quick Jab | -35% melee cd | -25% melee cooldown |
| Scattergun | +3 bullets, +3 ammo, x0.45 dmg | +2 bullets, +2 ammo, +0.4 spread, x0.55 damage |
| Shove Rounds | +120% knockback | +60% knockback |
| Skyhop | +1 air jump | +1 air jump, -10 max HP |
| Slab | +100 HP, -20% fire rate, +0.5s reload | +60 HP, -10% speed |
| Slugger | +80% dmg, -2 ammo, +0.5s reload | +45% damage, -2 ammo, +0.25s reload |
| Snap Swing | -30% heavy charge, +20% dmg | -25% heavy charge time |
| Spare Dash | +1 dash, -10 HP | unchanged |
| Thick Hide | +50 HP | +30 HP |

Other notable trims:
- Paper Tiger: x2 damage / -50 HP → x1.6 / -40 HP
- Siphon: 15% lifesteal → 10%
- Bullet Hose: -60% damage → -65%
- Bank Shot: +2 bounces → +1

I'll also do a final pass on numbers with bot-vs-bot win rates per card (a harness that gives one bot a card and measures how often it wins). I'll report outliers to you before changing anything else.

---

## Part C: 100 new cards

Format: **Name** (rarity): effect. *Stacking.* Rarity totals: 16 common, 28 uncommon, 28 rare, 18 epic, 10 legendary.

### Block / parry (14)
1. **Fortress** (common): +25% block size. *+25% per copy.*
2. **Quick Guard** (common): -15% block cooldown, -10 max HP. *Same again.*
3. **Perfect Guard** (uncommon): blocking in the last 0.15s before a bullet hits is a parry: the reflected bullet flies 2x faster with +50% damage. *+50% damage per copy.*
4. **Kinetic Guard** (uncommon): each bullet you block adds +15% damage to your next shot (max +90%). *+15% per bullet per copy.*
5. **Static Guard** (uncommon): blocking zaps the nearest enemy within 300 px for 20. *+1 extra target per copy.*
6. **Counterweight** (uncommon): blocking refills your dash. *Also +1 ammo per copy.*
7. **Spare Guard** (rare): store 2 blocks; the cooldown refills them one at a time. *+1 stored block per copy.*
8. **Bunker** (rare): hold block to keep it up for up to 1s, unmovable, but you walk 70% slower while holding. *+0.5s per copy.*
9. **Guard Break** (rare): a heavy melee on a blocking enemy puts their block on full cooldown. *Also stuns 0.3s per copy.*
10. **Ward** (rare): blocking leaves a ring where you stood for 3s that stops enemy bullets crossing it. *+2s per copy.*
11. **Riposte** (rare): after a parry or a blocked melee, your next melee within 1.5s is an instant heavy. *+30% heavy damage per copy.*
12. **Mirror Plate** (epic): every bullet you block also fires a copy at the nearest enemy. Block cooldown +0.5s. *+1 copy per copy.*
13. **Overcharge** (epic): every 3rd block releases a nova: 60 damage in 250 px. *+30 damage per copy.*
14. **Aegis** (legendary): your block becomes a shield bubble for 2s that you can move and shoot from, but it breaks after 3 hits; block cooldown x2. *+1s and +2 hits per copy.*

### Dash (14)
15. **Long Stride** (common): +25% dash distance. *Same again.*
16. **Dash Shot** (uncommon): dashing fires a free bullet the way you dash. *+1 bullet per copy.*
17. **Razor Dash** (uncommon): dashing through an enemy cuts them for 25. *+25 per copy.*
18. **Ember Trail** (uncommon): dashes leave a 1.5s fire trail that sets enemies burning. *+1s per copy.*
19. **Rebound** (uncommon): dashing into a wall bounces you off it and refills the dash. *+20% bounce speed per copy.*
20. **Momentum Rounds** (uncommon): shots fired during, and for 0.5s after, a dash deal +50%. *+50% per copy.*
21. **Graze** (rare): each enemy bullet that passes within 40 px of you during a dash gives back 1 ammo. *+1 ammo per bullet per copy.*
22. **Chain Dash** (rare): landing a gun hit refills your dash. *Also -20% dash cooldown per copy.*
23. **Thunder Step** (rare): your dash path is struck by lightning 0.4s later for 35. *+20 per copy.*
24. **Impact** (rare): dashing into an enemy knocks them back hard and stuns for 0.3s. *+0.3s per copy.*
25. **Flash Step** (epic): your dash is an instant teleport. The spot you left holds a decoy that explodes after 1s for 40. Dash cooldown +0.5s. *+40 damage per copy.*
26. **Ghost Run** (epic): dashing makes you invisible for 1.5s. *+1s per copy.*
27. **Air Ace** (epic): +2 air dashes, and dashing resets your mid-air jump. *+1 air dash per copy.*
28. **Overdrive** (legendary): each dash within 2s of the last adds a stack (max 3): +15% speed, damage and fire rate for 3s. *+1 max stack per copy.*

### Melee (14)
29. **Lunge** (common): +30% light-hit lunge. *Same again.*
30. **Heavy Hands** (common): +20% heavy melee damage. *Same again.*
31. **Combo Fists** (uncommon): every 3rd light hit in a row deals triple. *+50% damage on the 3rd hit per copy.*
32. **Bleed Edge** (uncommon): melee hits bleed for 18 over 3s. *+18 per copy.*
33. **Deflect Swing** (uncommon): melee swings knock enemy bullets back as your own. *+25% reflected damage per copy.*
34. **Second Swing** (uncommon): after a heavy hit, your next light hit within 1s is free (no cooldown). *+1 free hit per copy.*
35. **Gun Toss** (rare): heavy melee throws your gun like a boomerang for 60; you can't shoot until it's back. *+30 per copy.*
36. **Meteor Fist** (rare): a heavy melee in mid-air slams you down; landing deals 30 + 10 per 100 px fallen around you. *+20 per copy.*
37. **Whirlwind** (rare): your heavy melee hits all around you. *+20% range per copy.*
38. **Iron Jaw** (rare): you take 50% less damage while charging a heavy. *Another 50% less per copy.*
39. **Uppercut Chain** (rare): enemies you launch with melee take +50% damage from you while airborne. *+50% per copy.*
40. **Grapple** (epic): a heavy hit pulls the enemy to you and holds them for 0.6s. *+0.3s per copy.*
41. **Haymaker** (epic): a fully charged heavy deals x2.5 and throws the enemy; if they hit a wall they take 30 more. *+30 wall damage per copy.*
42. **Executioner** (legendary): melee hits kill enemies below 25% HP outright. *+10% threshold per copy.*

### Summons / gadgets (14)
43. **Moon** (uncommon): +1 small moon orbits you; it blocks enemy bullets and hits for 10 on touch. *+1 moon per copy.*
44. **Mine Layer** (uncommon): every 4s you drop a mine at your feet (max 3): arms in 1s, 40 blast. *+1 max mine and -1s per copy.*
45. **Grenadier** (uncommon): every 5th shot is a grenade that bounces and explodes after 1.5s for 50. *Every shot one sooner per copy (min every 2nd).*
46. **Spike Trap** (uncommon): blocking drops a trap: the first enemy to step on it takes 30 and is slowed. *+1 trap per copy.*
47. **Decoy** (rare): dashing leaves a decoy for 2s that bots and homing bullets go after; it pops for 30. *+15 and +1s per copy.*
48. **Ice Wall** (rare): blocking raises a breakable ice wall (60 HP) in front of you for 4s. *+1s and +30 HP per copy.*
49. **Totem** (rare): blocking plants a totem for 5s; you reload 50% faster near it. *+2s per copy.*
50. **Magnet Mine** (rare): your bullets that hit walls stick there as mines that slowly pull enemies in, then pop for 25. *+25 per copy.*
51. **Shield Drone** (rare): a drone circles you and blocks one bullet every 4s. *+1 drone per copy.*
52. **Field Turret** (epic): blocking deploys a turret on the spot for 8s (max 2 out), same rules as Turret Buddy. *+1 max turret per copy.*
53. **Remote Charge** (epic): your first shot each reload sticks where it hits; blocking detonates it for 80 (no block happens). *+40 per copy.*
54. **Bee Swarm** (epic): each hit spawns a homing bee (10 damage, max 6 alive). *+4 max bees per copy.*
55. **Gravity Bomb** (epic): every 6s your next shot is a slow orb that pulls enemies in for 2s, then pops for 40. *-1.5s cooldown per copy.*
56. **Hive Mind** (legendary): all your gadgets (moons, drones, turrets, bees, mines) deal +100% and fire/act 50% faster. *+50% per copy.*

### Bounce / ricochet (10)
57. **Angle Play** (common): bounced bullets deal +15%. *+15% per copy.*
58. **Super Ball** (uncommon): bullets gain +15% speed per bounce. *+15% per copy.*
59. **Bounce Bomb** (uncommon): each bounce leaves a small bomb (15). *+15 per copy.*
60. **Spring Walls** (uncommon): bullets bounce off the arena's top and side edges instead of leaving. *+1 bounce per copy.*
61. **Splitter** (rare): bullets split in two on their first bounce (60% damage each). *+1 extra split per copy.*
62. **Body Bounce** (rare): bullets carry on bouncing after hitting a player, toward another enemy, at 70% damage. *+1 player bounce per copy.*
63. **Trick Shot** (rare): a bullet that has bounced at least once crits for +75%. *+50% per copy.*
64. **Sonar Bounce** (rare): each bounce sends out a ping that slows enemies within 150 px by 30% for 1s. *+50 px per copy.*
65. **Corner Pocket** (epic): bullets that have bounced twice deal triple damage. *+1x per copy.*
66. **Rubber Room** (legendary): bullets keep bouncing for up to 6s until they hit someone; -10% damage per bounce. *+3s per copy.*

### Status effects (14)
New statuses: **Burn** (damage over time that can spread), **Shock** (the next hit is amplified), **Freeze** (a short stun after enough slow). They show on players like Poison and Frost do now.
67. **Kindle** (common): hits burn for 12 over 2s. *+12 per copy.*
68. **Brittle** (common): slowed enemies take +15% damage from you. *+15% per copy.*
69. **Corrode** (uncommon): poisoned enemies take +20% damage from you. *+20% per copy.*
70. **Static Rounds** (uncommon): hits shock: the next damage the target takes within 2s is +25%. *+25% per copy.*
71. **Toxic Puddle** (uncommon): poisoned enemies leave small poison puddles as they move. *+30% puddle size per copy.*
72. **Cinders** (uncommon): your explosions set enemies burning. *+1s burn per copy.*
73. **Sap** (uncommon): hits weaken enemies: -20% damage for 2s. *+1s per copy.*
74. **Wildfire** (rare): burning enemies spread their fire to enemies within 120 px. *+60 px per copy.*
75. **Conductor** (rare): hitting a shocked enemy arcs 15 to another enemy within 200 px. *+1 arc per copy.*
76. **Frostbite** (rare): an enemy slowed for 2s straight freezes for 0.6s. *+0.3s per copy.*
77. **Thermal Shock** (rare): hitting an enemy that is both burning and slowed sets off a 40 burst and clears both. *+20 per copy.*
78. **Plague** (epic): every 2s, poison jumps from each poisoned enemy to the nearest other enemy within 200 px. *+100 px per copy.*
79. **Shatterpoint** (epic): hitting a frozen enemy ends the freeze with +100% damage. *+50% per copy.*
80. **Overload** (legendary): every 5th status you apply to the same enemy sets off that status's burst: a fire nova, a 1s freeze, a poison cloud, or a chain shock. *1 fewer needed per copy (min 2).*

### Risk / HP (12) (no healing)
81. **Thin Skin** (common): +20% gun damage, -20 max HP. *Same again.*
82. **Cornered** (common): +25% fire rate while below 50% HP. *+25% per copy.*
83. **Daredevil** (uncommon): +30% damage while an enemy is within 250 px. *+30% per copy.*
84. **Adrenaline** (uncommon): +3% move speed for every 10% HP you're missing. *+3% per copy.*
85. **Wager** (uncommon): start each round at 70% HP; your first kill of the round gives +40% damage for the rest of it. *+40% per copy.*
86. **Last Breath** (rare): below 30% HP: +50% damage and fire rate. *+25% per copy.*
87. **Berserker** (rare): each hit you take gives +10% damage for 4s (max 5 stacks). *+5% per stack per copy.*
88. **Barbs** (rare): 30% of the damage you take is dealt back to the attacker. *+30% per copy.*
89. **Iron Will** (rare): no single hit can take more than 60% of your max HP. *-10% cap per copy (min 30%).*
90. **Blood Ammo** (epic): when empty, you can keep firing by spending 8 HP per bullet (it can't kill you). *-2 HP cost per copy.*
91. **Hemorrhage** (epic): shots cost 3 HP but deal +60% and pierce one target. *+30% per copy.*
92. **Final Gambit** (legendary): once per round, when you die you explode for 100 in 250 px. *+50 per copy.*

### Gun / general (8)
93. **Steady Aim** (common): -50% spread, +10% damage. *Same again.*
94. **Scope** (common): +30% bullet speed, -50% bullet drop. *Same again.*
95. **Heavy Slug** (uncommon): +100% push on players and props, +20% damage to objects. *Same again.*
96. **Boomerang** (rare): bullets fly back to you after 0.6s and can hit on the way back. *+1 return per copy.*
97. **Reprise** (epic): every 4th shot fires again 0.2s later. *One sooner per copy (min every 2nd).*
98. **Annihilator** (legendary): bullets are 3x size, x2.5 damage and explode, but you have 1 ammo and +1s reload. *+50% damage per copy.*
99. **Upside Down** (legendary): blocking flips your gravity for 3s; bullets fired while flipped fall upward. *+2s per copy.*
100. **Last Light** (legendary): when your HP drops below 25% for the first time each round, you release a 400 px blast for 80 and become immune to knockback for 4s. *+40 damage per copy.*

New card art: most use existing motifs (there are 91) with new badges and tints. I'll draw about 15 new SVG motifs where nothing fits: bee, trap, totem, boomerang, ward, gravity flip, combo, grapple, shock, burn, freeze and others.

---

## Part D: 50 new maps

**25 simple physics-prop arenas, marked ◆:** plain static blocks plus loose, stacked and hanging props, with no machines and at most one hazard. **25 set pieces:** the same mix as the current maps (hazards, moving platforms, destructible cover, physics props).

Every map:
- has 4 spawns
- passes the reachability check and `Editor:validate()`
- sits on the 24 px grid
- has ground that reaches the bottom
- finishes bot rounds

Two new themes: **sky** (clouds, floating rock, bright) and **caverns** (dark stone, glowing crystals, drips). Both get backdrops in `gfx/atmosphere.lua`.

**Sky (7):**
- Updraft (fans lift you between floating isles)
- ◆ Kite Line (platforms hang from a line of kites on ropes that sway)
- Cloudbreak (cloud blocks that crumble and reform)
- Sky Ferry (two airships on rails pass each other)
- Wind Vane (a big arm turns slowly with level platforms)
- ◆ Balloon Pop (balloon-held platforms that drop when shot)
- ◆ Loose Cargo (an open cargo deck of stacked crates and pallets hanging on chains)

**Caverns (7):**
- Stalactite (ceiling spikes drop when shot)
- Crystal Grotto (glass crystals as breakable cover)
- Mine Cart (carts on a rail carry you across a pit)
- ◆ Amphitheatre (a bowl-shaped arena with ramps and loose boulders)
- Cave-In (the stone ceiling crumbles as the round goes on)
- ◆ Rubble (a plain cave room strewn with boulders and planks)
- ◆ Lantern Hall (lanterns and crates on chains over plain ledges)

**Void (6):**
- Orbitals (platforms on two counter-rotating arms)
- ◆ Shard Field (scattered small floating blocks and loose cubes)
- Pendulum (a giant weighted pendulum sweeps the middle)
- ◆ Stack (a leaning tower of loose blocks in the middle of a plain room)
- ◆ Hollow Cube (a square frame with a breakable core)
- ◆ Tether (two islands joined by a rope bridge)

**Foundry (6):**
- Smelter (moving crucible platforms over molten metal)
- Assembly (conveyors and crushers in tiers)
- ◆ Scrap Pile (stacked crates and planks that topple)
- Piston Row (rising and falling pistons)
- ◆ Pallets (hanging pallets on chains over a plain floor)
- ◆ Crate Wall (a wall of stacked crates splits the room until it's shot apart)

**Desert (6):**
- Sandfall (breakable sandstone floors)
- ◆ Oasis (a pool in the middle with floating planks)
- Sun Temple (stepped ziggurat with ramps)
- ◆ Market Stalls (crates, barrels and plank awnings on plain platforms)
- ◆ Canyon Bridge (a rope bridge over a pit)
- Obelisk (a central breakable tower)

**Ice (6):**
- Glacier (icy slopes and a sliding block)
- Icicle Cave (icicles that fall)
- ◆ Frozen Lake (ice floor that cracks into the water)
- ◆ Snow Fort (two breakable snow walls)
- ◆ Ice Blocks (stacked loose ice cubes that slide when shot)
- Polar Station (metal platforms on rails over ice)

**Jungle (6):**
- Treehouse (platforms in a tree, rope ladders)
- ◆ Vine Swing (hanging vines with platforms)
- ◆ Ruins (crumbling stone pillars and loose blocks)
- ◆ Swamp (sticky ground and floating logs)
- Waterfall (a liquid column pushes things down)
- Temple Trap (saws and spikes in a temple)

**Neon (6):**
- ◆ Night Market (signs on ropes as platforms)
- Elevator Bank (three elevators on rails)
- ◆ Billboard (a giant breakable sign)
- Rooftops (gaps between buildings, a moving window cleaner's lift)
- Arcade (pinball bumpers that bounce players and bullets)
- ◆ Delivery (stacked parcels and hanging crates on plain rooftops)

I'll send you sketches (screenshots) of the maps in batches of 10 as they're built.

---

## Part E: mockups

### Card editor (item 11)
```
┌──────────────────────────────────────────────────────────────────────────┐
│ Name [ Kinetic Guard      ]  Rarity [< Uncommon >]  Art [motif ▾][badge ▾]│
├──────────────────────────────┬───────────────────────────────────────────┤
│ STATS     [search......]     │                                           │
│ ▸ Gun       ▾ Block          │          ┌─────────────────┐              │
│   Block cooldown   [-][ x0.8][+]        │  Kinetic Guard  │              │
│   Block time       [-][+0.0 ][+]        │      (art)      │              │
│   Block size       [-][ x1.0][+]        │ -20% block cd   │              │
│ ▸ Bullets  ▸ Defence         │          │ +blocked bullets│              │
│ ▸ Movement ▸ Melee           │          │  charge your... │              │
│                              │          │ Stacking: ...   │              │
│ EFFECTS                      │          │    UNCOMMON     │              │
│  When [blocking ▾] do [charge shot ▾]   └─────────────────┘              │
│     amount [15%]  max [90%]  [x]                                         │
│  [+ Add effect]              │  Notes [....................]            │
│                              │  Stacking [..................]           │
├──────────────────────────────┴───────────────────────────────────────────┤
│ [Test vs dummy]  [Test vs bot]        [Revert]  [Save]  [Share]  [Back]  │
└──────────────────────────────────────────────────────────────────────────┘
```
- The left side lists stats by group, with search. Only changed stats show in the card text.
- The "Effects" builder picks a trigger (block, hit, kill, dash, jump, land, melee hit, low HP, interval, ...) and an effect with its settings, which writes `trigger` lines.
- Test buttons start practice with the card applied, using the input set in **Settings > Controls > "Test with"** (keyboard / mouse / gamepad / ask each time).
- Stat audit: every stat in `Stats.LIST` gets a harness check that changing it changes behaviour. Dead stats are removed; new ones are added for the new cards.

### Replay bar (item 10)
```
                              (match view)
┌──────────────────────────────────────────────────────────────────────────┐
│ ▶ ‖  ◀◀ ▶▶  1x   02:14 / 07:40                         [Esc] Exit       │
│ ├─R1───●──●─────▣──R2──●───●─▣──R3────●──────●▣──R4──●──●───────┤       │
│          ▲ hover: "Rook killed Pip (melee)"                             │
└──────────────────────────────────────────────────────────────────────────┘
```
- **R1..** mark round starts, **●** marks a death in the victim's colour, **▣** marks a card pick.
- Click or drag the bar to seek. Hovering a marker shows what happened.
- , and . jump to the previous or next marker; Space pauses; F changes speed.

---

## Order of work
1. Part A fixes (1-9) with harnesses.
2. Card system work:
   - statuses
   - homing cone
   - bullet size
   - turrets
   - the requested card changes
   - removals
   - common nerfs
   - stacking lines
3. New cards in batches by build type, each batch with bot tests. Win-rate harness last.
4. Card editor and stat audit, plus the replay bar.
5. Themes, then maps in batches of 10 with screenshots for you.
6. Full test pass, a web build check, media update, then release **v0.7.0** (protocol 14).

## Open questions
- **Q1:** "Steam invite button does not work in game." Do you mean the lobby's "Steam Invite..." button does nothing, or that there's no way to invite people during a match? (I plan to fix both.) Were you running the game through Steam (Library → Play) when it failed?
- **Q2:** Any of the 100 cards to cut, rename or change? Name tweaks are cheap now.
- Decided after the ROUNDS research: 3 hits to kill (base damage 34), the standard tax, and 25 of the 50 maps as simple physics-prop arenas.
- **Q3:** Map concepts: any to swap out?
