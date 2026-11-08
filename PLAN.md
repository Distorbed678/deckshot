# v0.5 Plan (Deckshot): rename, movement, melee, map objects, editors, 50 maps, 150 cards, bots, mobile, game feel

Status: **implemented in v0.5.0** (see the release notes). Kept for reference.

## Decisions

| Topic | Decision |
|---|---|
| Movement feel | Tight and snappy like Celeste / Hollow Knight. Values are **hardcoded** constants. |
| Extra moves | Corner correction, one-way platforms, dash, and keep wall slide / wall jump (retuned). |
| One-way platforms | Bullets pass through them. |
| Melee | Light melee (tap) plus a charged heavy melee (hold) with a small dash, like Deadlock. Blocking a melee stuns the attacker. |
| Arena edges | Left, right and bottom no longer kill. They're damaging bounce walls (30 damage + launch back in); blocking on them launches you without damage. The ceiling stays open. |
| Hazards | Hitting one shoves you away from it. Blocking bounces you off it with no damage (like ROUNDS). |
| Sudden death | Host setting: in games that started with 3+ players, a red barrier closes in 30 s after it becomes a 1v1. It does the same damage and bounce as the edges. |
| Map editor | Single-screen only, no decoration layer. Grid snap, live mirror, object palette, spawns, test play, undo / redo. |
| Map sharing | The host sends custom maps automatically, plus copy-paste share codes. |
| Card editor | Tune built-in cards and create new ones (stats + abilities + trigger → effect rules). Custom and edited cards get a small wrench icon. **No power limits or warnings.** No curse cards for now. |
| Synergies | About 40 built-in synergies shown on cards. The host can turn them all off or toggle each one. The editor can create new ones. |
| Card picks | 5 cards per hand by default. Cards are dealt **face-down** and flip when hovered; higher rarities sparkle and play a sound on reveal. |
| Starting cards | Host setting, default **1**: everyone picks that many cards before round 1. |
| Pick timer | Host setting: off locally, **45 s online** by default. When it runs out, the hovered card is taken. |
| Card discard | Host setting (on by default): "Discard instead" removes one owned card and replaces that pick. |
| Bots | Easy / normal / hard, for solo play and 3-4 player local matches. They also fill online lobby slots. |
| Mobile | Twin-stick touch controls plus a touch layout editor. Phones join LAN games from the host's `http://` address via a QR code. |
| LAN firewall prompt | Keep direct LAN. Only the host gets the one-time Windows Firewall prompt, and joiners must never trigger one. No relay server. |
| Sounds | Synthesized in code behind one module (real `.ogg` files can replace them later). Separate sounds for light and heavy melee. |
| Releases | Commit and push after each item; **one release at the end** (v0.5.0). |
| Name | The game becomes **Deckshot**. Everything is renamed, including the GitHub repo and the Pages URL. ROUNDS is still credited as the inspiration in the README and the Credits screen. |
| Maps | All 25 current maps are **replaced** by **50 new maps**. Most use the new objects, but not all. Every built-in map is an editor file and can be edited in-game. |
| Cards | A stats overhaul (gun and melee damage become separate stats) plus a card overhaul up to **150 cards**. Every built-in card is a card-editor file and can be edited in-game. **Every change, removal, rename and rework is asked card by card with the question tool when that step is reached, not before.** |

---

## Build order and why

**Phase 0: rename**

0. **Rename to Deckshot** (§0). It goes first so that every new file, save path and build name uses the new name from the start, with no second migration.

**Phase A: core feel**

1. **Movement + melee + arena edges**: everything else gets tuned against how players move and fight. One-way platforms are collision, so they go here too.
2. **Sound and particle groundwork**: built early so every later feature gets its sounds and effects as it's written.
3. **Card pick flow**: 5 cards, face-down dealing with hover-to-flip, the pick timer, discard, starting cards. The editors and the mobile layout are built around it.

**Phase B: arenas**

4. **Map objects**: hazards, breakables, ropes, pickups, plus the sudden-death barrier.
5. **Map editor + custom map transfer**
5b. **Map overhaul: 50 new maps** made in the editor (§5b). This comes after the editor, the objects and the final movement numbers, so the maps are built for how the game really plays. It comes before bots, so the bot platform graphs are built on the final maps. Maps are reviewed with you in screenshot batches.

**Phase C: cards**

6. **Data-driven cards + card editor**, including melee stats and triggers
6b. **Stats and card overhaul to 150 cards** (§6b), going through every card with you in question batches. The 8 melee cards from §1b are part of this review, not added separately.
7. **Synergies** (built-in set, the pool toggle screen, editor support)
8. **Card codex**

**Phase D: players**

9. **Local play setup + bots + gamepads + Teams (2v2) + player colors**
10. **Mobile touch + LAN polish** (QR code, the firewall-safe joiner)

**Phase E: online**

11. **Netcode**: client prediction, interpolation buffer, ping display.
12. **Online features**: late joiners spectate, reconnect, Steam lobby browser, rich presence, lobby win streaks.

**Phase F: polish**

13. **HUD and juice**: damage numbers, kill feed, low-HP vignette and heartbeat, the FIGHT countdown, off-screen arrows, the scoreboard on a keybind.
14. **Flow and UI**: slide transitions, How to Play (replacing the web page's controls text and the menu's controls line), practice range, version and what's new, the crash screen, remembered settings, credits, animated menu background, window icon, UI scale, audio settings.

**Phase G**

15. Final checks, docs (CLAUDE.md / README), and the **v0.5.0** release.

**Network:** `session.PROTOCOL` goes from `"4"` to `"5"`. v0.5 can't play online with v0.4.

---

## 0. Rename to Deckshot

**In the game**
- The title on the main menu, the window title (`conf.lua` `t.window.title`), the loading text and the web page title.

**Save folder**
- `t.identity` changes from `rounds_clone` to `deckshot`.
- On first launch, if the new folder is empty and the old one exists, the old settings (and any custom maps or cards, once those exist) are copied over once. The old folder is left alone.
- On the web, browser storage is keyed by identity, so it's migrated the same way.

**Builds**
- `build.sh` outputs `Deckshot.love`, `Deckshot-x86_64.AppImage`, `Deckshot-windows-x64.zip` with `Deckshot.exe`, and the AppImage desktop entry.
- The release workflow's package checks and download table use the new names.

**Network**
- The LAN discovery and handshake magic strings (`RCLQ`, `RCL1`) stay as they are. The protocol bump already stops old versions from joining, so renaming them adds nothing.
- The Steam lobby metadata key is renamed so v0.4 lobbies don't show up in the new lobby browser.

**GitHub**
- Rename the repo `Distorbed678/rounds-clone` → `Distorbed678/deckshot` (`gh repo rename`), and update the git remote.
- GitHub redirects the old repo URL for git and web links, but **not for Pages**: the site moves to `https://distorbed678.github.io/deckshot/`, and the old Pages URL stops working.
  - To keep old links working, I can leave a tiny redirect page in a separate `rounds-clone` repo. This needs your OK when we get there, since it creates a new public repo.
- Links in the web page, README, CLAUDE.md, the update checker (§14) and the workflows are updated.

**Credit to ROUNDS**
- The README's first section: "Deckshot is a fan-made game heavily inspired by **ROUNDS** by Landfall Games. It isn't affiliated with or endorsed by Landfall."
- The same line appears in the Credits screen and on the How to Play page.

**Docs:** CLAUDE.md and README are updated with the new name, paths and URLs.

---

## 1. Movement, melee and arena edges

### 1a. Movement (Celeste / Hollow Knight feel)

All values are constants at the top of `game/player.lua`. Cards still scale them through `speed`, `jump`, `gravityMul` and `airJumps`.

**Horizontal**
- Run speed stays 340. Ground acceleration about 6000 px/s² (full speed in ~0.06 s), ground deceleration about 7000.
- A turn-around boost: reversing direction uses 1.5× deceleration.
- Air acceleration is about 65% of ground; air deceleration is lower, so momentum carries.
- Above max speed (knockback, recoil, dash, edge bounces), speed decays slowly instead of being clamped, so launches still fling you.

**Vertical**
- Jump height stays about 180 px (so all maps remain playable). Gravity is about 2400 and jump speed about 930.
- Variable jump height: releasing jump while rising multiplies upward speed by 0.45.
- Apex hang: when |vy| < 90 and jump is held, gravity is halved.
- **Snap fall**: gravity is ×1.7 after the apex.
- Max fall speed is 900. Holding Down in the air is a **fast fall** (max 1400, reached over ~0.1 s).
- Coyote time 0.1 s. Jump buffering 0.12 s (also before touching a wall).

**Walls**
- Wall slide at 160 px/s. Wall coyote 0.08 s and wall-jump buffering.
- Wall jump: up 0.95× jump, push 0.65× speed, steering weakened for 0.12 s.

**Corner correction**
- Hitting a ceiling within 8 px of its edge nudges you around the corner.
- Clipping a ledge top by 6 px or less while moving sideways lifts you onto it.

**Dash**
- 8 directions, ~0.14 s at 950 px/s, then you keep 60% of that speed.
- 1 dash in the air, refilled on landing or wall contact. Cooldown 0.6 s. Gravity is off during the dash.
- Direction comes from the held direction keys, falling back to the aim direction (online, pad, touch), then to facing.
- Default binds: P1 `E`, P2 `/`, online `L-Shift`.
- New stats: `dashes`, `dashSpeed`, `dashCooldown`.

**One-way platforms**
- A new `oneway` rect type: jump up through, land on, and **Down + Jump** drops through.
- Bullets pass through them. They're drawn thinner, with a lighter top edge.

### 1b. Melee (Deadlock-style)

- **Its own bind**: P1 `Q`, P2 `.`, online `F` (or `mouse3`), pad `X`. Rebindable.
- **Light melee**: tap the bind. A quick arc swing in the aim direction: ~0.12 s wind-up, 12 damage, knockback 450, range ~55 px past the body, cooldown 0.45 s.
- **Heavy melee**: hold the bind to charge (up to 0.6 s at full charge; the player glows and a charge ring fills). On release:
  - Damage scales from 20 (minimum charge) to 40 (full).
  - Knockback scales up to 900.
  - A **small dash** in the aim direction comes with it (120-260 px depending on charge).
  - Cooldown 0.9 s. You move at 60% speed while charging.
- **Blocking a melee stuns the attacker.** The stun scales with the melee's power: light 0.25 s, half-charged heavy 0.5 s, full heavy 0.8 s. A stunned player can't act, shows stars or a spark ring, and plays a stun sound. The blocker takes no damage. Parry and other block effects still trigger.
- Melee hits break crates, cut ropes and push hanging objects.
- **Sounds:** light is a short whoosh plus a thwack; heavy has a rising charge hum, a deep swing and a heavy impact; there's a separate stun "clang".
- **Stats for cards** (used by the card editor and new built-in melee cards): `meleeDamage`, `meleeKnockback`, `meleeRange`, `meleeCooldown`, `heavyCharge` (charge time), `heavyDash`, `meleeStun` (extra stun when blocked against), `meleeLifesteal`.
- **New built-in melee cards** (about 8):
  - Bat: +knockback.
  - Uppercut: heavy launches upward.
  - Riposte: a melee right after blocking deals double damage.
  - Quick Jab: -40% light cooldown.
  - Haymaker: faster heavy charge, +damage.
  - Lunge: longer heavy dash.
  - Iron Guard: a melee you block stuns the attacker 50% longer.
  - Vampiric Fists: melee lifesteal.
- **Network:** the INPUT packet gets the melee held bit plus a press counter. The snapshot gets the melee swing state (for drawing the arc) and the charge and stun flags.

### 1c. Arena edges

- The left, right and bottom edges of the 1280×720 arena become **red boundary walls** (drawn as a glowing red line that pulses when touched). The top stays open: you can fly above the screen, with an off-screen arrow (see §13).
- Touching an edge does **30 damage** (through armor and shield like any hit) and launches you back into the arena (about 900 px/s inward plus an upward boost), with 0.3 s of edge immunity so you don't take a double hit.
- **Blocking while touching an edge**: no damage, and you're launched (block-bounce). You can use it on purpose to fly back up or sideways, like in ROUNDS.
- Phoenix and Last Stand still work, since this is normal damage now. The old instant-kill "fell out of the arena" path is removed.
- Bullets still leave through the edges (unchanged).

---

## 2. Sound and particles

**`gfx/sfx.lua`**
- A synth (oscillators, noise, envelopes, pitch sweeps, filters) builds every sound at startup.
- `sfx.play(name, x, volume, pitch)` with stereo pan from `x` and small random pitch variation.
- `assets/sfx/<name>.ogg` overrides a synthesized sound when it exists.
- The host's sounds are recorded and replayed on clients (fx event kind 5).
- On the web, audio unlocks on the first click or tap.

**Sounds:** shoot (pitched by bullet size), shotgun, laser, bounce, wall impact, hit, crit, block, parry, reflect, empty click, reload start / done, jump, double jump, wall jump, land (scaled by fall speed), dash, dash refill, light melee, heavy charge loop, heavy melee, melee hit, stun clang, edge bounce, death, Phoenix revive, explosions (small / big), mine arm / beep, black hole hum, countdown beeps, "fight", round win, match win, card deal, card flip, rarity reveal (rising sparkle for rare / epic / legendary), card pick, UI hover / click / back, low-HP heartbeat.

Map objects add: saw whirr (looping, distance volume), spike hit, crate break, glass break, rope snap, barrel explode, crusher slam, turret shot, conveyor hum, bounce pad, fan, crumble, gas hiss, pickup, and the barrier warning.

**Particles (`gfx/fx.lua` additions, replayed online)**
- Directional wall sparks.
- Jump, land and run dust; wall-slide sparks.
- Dash afterimages.
- Muzzle flash plus a small camera kick on shooting.
- Melee swing arcs.
- Debris chunks.
- Squash and stretch on players (visual only; the snapshot gains a velocity byte).
- **No hit-stop and no screen flash** (your call).

---

## 3. Card pick flow

**Hands**
- **5 cards per hand by default.** Old `settings.txt` files still on 3 are migrated to 5 once.
- Card size and fonts are checked at 1280×720 and on phones.

**Face-down dealing (like ROUNDS)**
- Cards fly in from the side face-down. Hovering or selecting a card flips it to show what it is.
- Each card flips once and then stays face-up. On rare, epic and legendary cards the reveal plays a rarity sound and a sparkle burst (legendary gets the biggest).
- Online, everyone watching sees the same flips, because the flip state rides with the pick's hover in the snapshot.
- Bots and the pick timer flip as they go.

**Taking a card**
- The taken card flies into the picker's card list on the score panel.

**Pick timer** (host setting, Gameplay tab)
- Off locally, **45 s online** by default; the range is off or 10-120 s.
- A bar shows the time left.
- When it runs out, the hovered card is taken. If none was hovered, a random card is taken.

**Card discard** (host setting, on by default)
- The pick screen has a **"Discard a card instead"** button.
- It opens your owned cards. Choosing one removes it, and that pick is used up.
- It's hidden when you own no cards.

**Starting cards** (host setting, default **1**, range 0-5)
- Before round 1 (and on New Match), every player picks that many cards, in slot order, using the normal pick screen.

---

## 4. Map objects

**Entity system (`game/objects.lua`)**
- Maps gain `objects = { … }`. The world copies them fresh every round.
- Solid objects (crates, crushers, moving platforms, destructible walls) are added to the collision lists that players and bullets use.

**Hazard contact (your rules)**
- Taking hazard damage **shoves you away** from the hazard (out of its centre for saws; along the surface direction for spikes and lava).
- **Blocking while touching a hazard bounces you off** it with no damage and a parry spark. Parry still recharges the block, as with a blocked bullet.
- Kill credit goes to whoever caused the hazard to hit (who cut the rope, shot the barrel, melee'd you into it). Otherwise it's an environment kill: "sawed", "spiked", "burned"…

**Hazards**
1. **Saw blade**: static, moving on a path, or hanging from a rope. 25 damage per touch (0.4 s cooldown per player).
2. **Spike strip**: floor, ceiling or wall. 30 damage.
3. **Retracting spikes**: on a timer, with a warning wiggle.
4. **Laser emitter**: a cycle of charge line, then a beam that stops at solids and crates.
5. **Crusher**: slams on a timer. Crushing damage is 60, plus a shove out sideways (no instant kill).
6. **Flame jet**: periodic bursts that apply burn.
7. **Acid pool**: damage per tick plus an upward shove (no instant kill, consistent with the new edges).
8. **Turret**: fires at the nearest player every 2 s. It has HP, breaks, and the kill credit goes to whoever broke it.
9. **Conveyor belt**: moves players and crates standing on it.
10. **Bounce pad**: launches players high; bullets that hit it get a speed boost.
11. **Wind fan**: pushes players and bullets inside its stream.
12. **Crumbling platform**: breaks 0.5 s after you stand on it and comes back after 4 s.
13. **Rotating blade arm**: saws on a bar spinning around a pivot.
14. **Moving platform**: a solid platform on a path; it carries whoever stands on it.

**Breakables**
1. **Wooden crate**: 60 HP. Solid, falls when unsupported, debris on break. **8% chance to drop a pickup** (small health +25, or an ammo refill). Pickups vanish after 8 s.
2. **Glass pane**: shatters on one hit.
3. **Rope**: cut by bullets, melee or explosions. Anything can hang from it: a saw, a barrel, a crate, a chandelier / weight, or a swinging platform. Hanging objects swing as pendulums when hit or caught in a blast.
4. **Exploding barrel**: 30 HP. Radius 110, 55 damage. Sets off barrels nearby in a chain. Credit goes to whoever shot it.
5. **Gas canister**: breaks into a poison cloud that lasts 4 s (applies poison damage-over-time inside it).
6. **Destructible walls**: map blocks marked breakable in the editor, with HP. They crack visually as they take damage and break into debris.
7. **Breakable bridge**: a row of planks, each hung on ropes. Shooting a rope drops that part of the bridge.

**Sudden-death red barrier** (host setting, on by default)
- Only in matches that started with **3 or more players**.
- **30 s after the round becomes a 1v1** (2 alive), a red barrier rect starts shrinking toward the middle of the map, closing to about a 400×300 area over 20 s.
- Touching it does exactly what the arena edges do: 30 damage, launch inward, and blocking means no damage plus a launch.
- A warning (sound plus a pulsing border) plays 3 s before it starts.

**Maps**
- While the objects are being built, they're tested on a few scratch maps. The real maps come in the overhaul (§5b).
- The spawn harness also checks that spawns don't touch hazards.
- A host toggle "Map hazards: on / off" removes hazards and keeps breakables.

**Network:** a new object section in snapshots (type, position, angle, HP, state, rope length), sent only when changed. Pickups and the barrier rect are included.

---

## 5. Map editor (`screens/editor_map.lua`)

**Entry points:** Main menu → **Editor** → Maps / Cards. The map pool screen lists custom maps alongside built-ins, with Edit / Duplicate / Delete / Share.

**Canvas:** the fixed 1280×720 arena, single screen only. A 20 px grid toggles with G; Shift drags off-grid at 5 px. Mirror mode (M) mirrors left to right live.

**Tools:**
1. Select / move / resize (arrow nudge, Delete, Ctrl+D).
2. Solid block.
3. One-way platform.
4. Destructible wall.
5. Object palette (everything in §4).
6. Rope (anchor → attached object).
7. Path (waypoints for moving saws and platforms).
8. Spawns 1-4.

**Inspector:** shows the selected item's properties (size, damage, timers, phase, HP, rope length, path mode and speed, crate pickup chance).

**Top bar:** name, Undo / Redo (100 steps), **Test** (play the map at once against a bot or a dummy; Esc returns), Save, Share, Import, and a validation indicator.

**Validation:** spawns land on solid ground and touch no solid or hazard; at least one solid; the name is unique.

**Storage:** `maps/<id>.txt` in the save folder (a readable line format). Share codes are `RCMAP1:` + base64(zlib).

**Online:** the host sends its pool's custom maps in a MAPS message at START and on New Match. Clients keep them for the session, and can save one from the pause menu.

Built-in maps can be duplicated as templates. **No decoration layer.**

---

## 5b. Map overhaul: 50 new maps

**All built-in maps are editor files**
- Built-in maps live in the repo as editor files (`data/maps/<id>.txt`, the same format the editor saves) and are packed into the game. The Lua map table in `game/map.lua` goes away; `game/map.lua` keeps only loading and collision.
- **Editing a built-in in-game** saves an override copy to the save folder (`maps/<id>.txt`), which is used instead of the packed one. "Reset to default" deletes the override. Edited built-ins show a wrench icon in the map pool.
- Online, the host sends overridden built-ins along with its custom maps, so everyone plays the same version.
- The 25 current maps are **removed**. Their names may be reused if a new map fits one.

**Building the maps**
- I build all 50 with the in-game editor (driven from harness scripts that place things through the editor's own operations and save through its own code). That checks the editor can make every map and keeps the files in the editor's format.
- **Mix:** about 10 plain maps (only solids and one-way platforms, for pure duels) and about 40 that use objects. Each object map has a clear theme built around one or two mechanics, e.g.:
  - Sawmill: moving saws and conveyors.
  - Powder Keg: barrel chains.
  - Chandelier Hall: hanging weights over the spawns.
  - Rope Bridge: a breakable bridge over acid.
  - Windmill: fans and moving platforms.
  - Crumble Tower: crumbling platforms.
  - Turret Nest: destructible cover.
  - Crusher Works.
  - Laser Grid.
  - Bounce House: bounce pads and open air.
- **Layout rules:**
  - Fair spawns: symmetric, or rotationally balanced when asymmetric.
  - Every spawn reachable.
  - No hazard within 120 px of a spawn.
  - Edges and an open ceiling taken into account.
  - Platforms spaced for the new jump height (~180 px), with dash and wall jumps.
  - Readable at phone size.
  - Sizes vary: tight brawl maps and open sniper maps.
- **Checks:** a harness spawns at all 4 spawns on all 50 maps, and bots play every map in headless matches (no stuck spots, rounds end).
- **Review with you:** I take screenshots of each map and go through them in question batches (keep / change / drop, with notes) before they're final.

---

## 6. Data-driven cards + card editor

**Conversion**
- Built-in cards stop being Lua functions. They become card-editor files in the repo (`data/cards/<id>.txt`, the same format the editor saves): mods (stat, op, value), abilities, trigger rules and notes.
- Their **stat lines are generated** from the data; flavour lines become `notes`.
- Anything a card needs that the editor can't express yet (Railgun's first-copy-vs-extra-copy rule, the specials Reroll / Table Flip / Shrine) gets added as an editor feature (e.g. "first copy only" / "extra copies only" on a row, and a "special" effect type), so **every card can be edited in-game**.
- Before the overhaul, a harness checks that every converted card gives the same stats as the old `apply` code.

**Tuning built-in cards**
- Every number is editable. As with maps, editing a built-in saves an override to the save folder (`cards/<id>.txt`), and "Reset to default" deletes it. Reset all is also available.
- **Edited cards show a wrench icon** on the card face, in tooltips and in the pool.

**New cards**
- Name and rarity.
- Stat rows (every stat, including melee and dash stats).
- Ability rows (every ability with a count).
- **Trigger → effect rules**:
  - Triggers: shoot, hit, kill, take damage, block, parry, **melee hit, heavy melee hit, melee blocked**, reload, jump, land, dash, wall jump, low HP, round start, every N s.
  - Effects: explode, heal, shield, nova, shockwave, speed boost, damage boost (next N shots), refill ammo, invulnerability, mine, blink, slow nearby, poison aura, black hole, refill dash, **reset melee cooldown**.
  - Each rule has an optional chance and cooldown.
  - Effects that come from triggers can't trigger other rules.
  - Each copy of the card repeats its rules, so every card still stacks.
- Live card preview plus a **Test** button (a practice range where you own the card).
- **No power limits or warnings.** Custom cards get the wrench icon too.

**Storage and network:** `cards/custom/<id>.txt` with `RCCARD1:` share codes. Custom cards go after the built-ins in `Cards.list`. The host sends a CARDS message (custom definitions plus built-in overrides plus synergy settings) along with RULES.

---

## 6b. Stats and card overhaul (150 cards)

**Stats overhaul** (done first, because the cards are built on it)
- **Gun and melee damage are separate stats.** Today `damage` is gun damage; it's renamed `gunDamage`. Melee gets its own `meleeDamage`, plus the other melee stats from §1b. Cards that say "+damage" now say which one.
- A pass over the `BASE` stats:
  - Clearer names (`fireDelay` → shown as fire rate, `bulletGravity` → bullet drop).
  - Group them (Gun, Melee, Movement, Defense, Block, Abilities) for the editor and tooltips.
  - Remove stats that only one outdated card used.
  - Add the new ones: dash, melee, and any that new cards need.
- **Proposed stat changes go to you** in a question batch before the cards (e.g. base HP, base gun damage, base melee damage, ammo, reload, block cooldown), since every card depends on them.

**Card review process** (your rule: nothing changes without your answer)
1. I audit all 100 current cards and group them by theme (gun stats, bullets, block, movement, defense, special effects, specials).
   - For each card, I propose one of: **keep**, **retune** (new numbers), **rework** (new effect), **rename**, **merge** (two cards too similar → one), or **remove**, with a one-line reason (outdated, too similar to X, too weak or too strong, doesn't fit the new movement or melee…).
2. **I ask you about every card with the question tool** in batches of 4 (one question per card).
   - The options are my proposal, keep as is, one alternative, and your own answer via "Other".
   - The batches are grouped by theme so similar cards are judged together.
   - I don't change a card until you've answered.
3. I then propose the **new cards** needed to reach **150** (about 50 or more, depending on how many get removed or merged). This includes the 8 melee cards from §1b, dash cards, and cards built around the new triggers and map objects (e.g. "Demolition": +damage to objects; "Hazard Proof": take half hazard damage).
   - Each new card is also put to you in question batches (approve / change / drop).
4. Everything approved is made **in the card editor** (driven from harness scripts through the editor's own operations and saved in its format) into `data/cards/`.
5. Checks: every card stacks (the "every card must stack" rule still holds), and each one is tested in the practice range harness. I then report a balance summary (rarity counts, how many gun / melee / movement / defense / block cards).

**Rarity spread target** for 150 cards: about 45 common, 40 uncommon, 30 rare, 20 epic, 15 legendary (also confirmed with you during the review).

**Network:** card indices change, which is part of the PROTOCOL 5 bump. Saved per-card settings (`card.<id>=…`) for removed cards are ignored. Renamed cards keep their settings through an id alias table.

---

## 7. Synergies

- About **40 built-in synergies**. Owning both cards (or tags, e.g. any explosive card plus any bounce card) unlocks a bonus. Examples:
  - Explosive + Bouncy: every bounce makes a small explosion.
  - Homing + Laser: the laser bends toward the nearest enemy.
  - Poison + Shrapnel: the shards poison.
  - Parry + Reflector: parried bullets come back as crits.
  - Black Hole + Cluster: mini black holes.
  - Rocket Jump + Heavy Melee: a heavy melee after a recoil shot has double dash distance.
  - Frost + Static Field: the field slows.
  - Phoenix + Martyr: reviving triggers a Martyr blast.
  - Sentry + Mirror Shot: the sentry's shots are mirrored too.
  - Uppercut + Spring Legs: uppercut launches you up with the target.
  - …and about 30 more, spread across rarities and the new melee cards. Each synergy works with stacking: its bonus scales with the copies held of the lower-count card.
- **Display**
  - Cards list "Synergy: <other card>" lines (the tooltip shows the bonus).
  - Your owned card chips glow and are linked when a synergy is active.
  - A toast plays when a synergy unlocks.
- **Host control:** Settings → Gameplay → **Synergies**: "All on / all off" plus a per-synergy toggle screen (like the card pool). This travels with RULES.
- **Editor:** a "Synergies" tab where you create new synergies from card A + card B (or tags) → stat rows, abilities or trigger rules. These share through codes and travel with CARDS.

---

## 8. Card codex

- Main menu → Codex. Shows every card (built-in and custom) and every synergy.
- Search, rarity filter, tag filter.
- Per-card stats saved locally: times offered, picked, and rounds won while holding it.

---

## 9. Local setup, bots, gamepads, teams, colors

**Local Play setup screen**
- 2-4 slots. Each slot is: Off, P1 keys, P2 keys, Gamepad 1-4, Touch, or Bot (Easy / Normal / Hard).
- Also: rounds to win, and mode (FFA / Teams).
- The last setup is remembered.

**Bots** (`game/bot.lua`, `Input.bot`)
- Targeting with lead and drop compensation.
- A platform graph per map for movement, using jumps, drops, wall jumps and dash.
- Avoids hazards and edges, and uses the barrier and edge bounces knowingly.
- Blocks and dashes away from incoming bullets and melee; uses light and heavy melee at close range; times blocks against charging heavies.
- Card choice is scored by rarity plus synergies.
- The online host can fill empty slots with bots.

**Gamepads**
- Up to 4. Default layout:
  - Left stick: move (down = fast fall / drop).
  - Right stick: aim. RT fire, LT or RB block, A jump, B dash, X melee (hold for heavy).
  - Start: pause. The D-pad and A move through menus and card picks.
- Rebindable in Controls.
- Hot-plugging is supported.

**Teams (2v2)**
- A mode setting (local and host).
- Team colours tint players.
- A friendly-fire option (default off): friendly bullets pass through teammates; explosions don't hurt them.
- A round ends when one team is left. Every player on the losing team picks.
- The score is per team.
- Bots respect teams.

**Player colors**
- A palette of about 12 distinct colors.
- In the lobby (and the local setup screen), each player picks one, and no two players can share a color.
- In Teams mode, the team tint is mixed in during matches.
- It's sent with the lobby members and in START.

---

## 10. Mobile + LAN polish

**Touch controls**
- Turned on automatically on the first touch.
- Left: a floating move stick (up = jump, down = fast fall / drop).
- Right: an aim stick that fires while held (a tap fires once).
- Buttons: Jump, Block, Dash, **Melee** (hold for heavy, with a charge ring).
- Card picks: tap to flip and select, tap again to take.
- **Touch layout editor** in Settings → Controls: drag and resize each control, set opacity, reset.
- The hidden HTML input for text fields opens the phone keyboard.

**Web page**
- A mobile viewport; no zoom or scroll.
- A rotate-to-landscape overlay.
- A web app manifest so the game runs fullscreen from the home screen.
- Audio unlock on first tap.
- Lower effect defaults on phones.
- A performance pass in mobile emulation.

**LAN**
- A QR code and the address in large text in the LAN lobby.
- The joiners' discovery socket binds implicitly, so joiners never trigger the Windows Firewall prompt.
- A tip appears when nobody can connect.

---

## 11. Netcode

**Client prediction**
- The client simulates its own player locally with the same `Player` movement code: movement, jump, dash, wall jump and one-way platforms, against the map rects and solid objects.
- When a snapshot arrives with the host's position for the last input sequence it processed, the client replays its unacknowledged inputs from there.
- Small errors are blended out over ~100 ms; big ones snap.
- Shooting, melee and damage stay host-authoritative.
- The INPUT packet gets per-input dt, and the snapshot gets the last processed input sequence per player.

**Interpolation buffer**
- Other players and objects render ~2 snapshots (~66 ms) behind, interpolating between real snapshots instead of extrapolating.

**Ping display**
- The host measures round-trip time with the ping messages and sends each player's ping in the snapshot.
- Pings are shown in the lobby list and the scoreboard (§13).
- A warning icon appears when ping is over 200 ms or snapshots stall.

---

## 12. Online features

- **Late joiners spectate:** a player who joins a lobby mid-match becomes a spectator (sees the match and the score panel, no player) and joins as a player at the next New Match or Back to Lobby. Dead players keep today's view of the map without their player.
- **Reconnect:**
  - If a client drops, the host keeps their slot for 60 s (shown as "reconnecting…").
  - The client automatically tries to rejoin (Steam lobby or LAN address) and gets its slot, cards and score back.
  - After 60 s it's a normal disconnect.
- **Steam lobby browser:**
  - The Online → Steam page lists public lobbies (name, host, players / 4, mode, ping region), with refresh and join.
  - The host can mark a lobby Public / Friends / Private (code only).
- **Steam rich presence:** "Main menu", "In lobby (2/4)", "Round 3 — 2-1", plus "Join game" through the friends list.
- **Lobby win streaks:**
  - The lobby tracks each player's match wins and current win streak (shown next to names in the lobby and the scoreboard: 🔥3).
  - Kept only in that lobby's memory; it resets when the host disbands the lobby.

---

## 13. HUD and juice

- **Damage numbers:** floating, merged per target over 0.2 s. Crits are larger and gold. A **client-side toggle**, on by default.
- **Low-HP vignette** (below 30% HP, local player only) plus a **heartbeat** sound.
- **Kill feed** at the top right, e.g. "P1 ▸ P2 (Explosive)", "P3 was sawed", "P2 was launched by the edge".
- **3 · 2 · 1 · FIGHT!** countdown with scale-pop and sounds.
- **Off-screen arrows** for players above the open ceiling (with their height).
- **Scoreboard / recap on a keybind** (`Tab` / pad `Back`, rebindable). An option chooses **hold** or **toggle**. It shows:
  - per player: score, kills, deaths, damage dealt, accuracy, blocks, melee hits, cards held, ping, lobby win streak;
  - plus a round-by-round mini history.
  - The match-over screen has a button to open it too.

---

## 14. Flow and UI

- **Slide transitions like ROUNDS:** new screens and rounds slide in from the **right** and old ones slide out to the **left**.
- **How to Play** screen:
  - Controls for each scheme (keyboard P1 / P2, online, gamepad, touch).
  - The rules: block and parry, melee and stuns, edges, the barrier, card picks.
  - It **replaces** the controls footer on the web page (the page becomes just the game plus a small header) and the controls text at the bottom of the main menu.
- **Practice range:** a sandbox map with target dummies (and an optional bot), every card toggleable, HP reset, and a damage meter. It's also used by the editors' Test buttons.
- **Version + What's new:** the version on the menu and a What's New panel (the release notes are bundled at build time). On desktop, a GitHub API check shows "update available".
- **Friendly crash screen:** catches Lua errors, writes `crash.txt` to the save folder, and offers copy-to-clipboard and restart.
- **Remember last settings:** lobby rounds, mode, last LAN name and address, local setup, and the last editor file.
- **Credits** screen.
- **Animated main menu background:** bots fighting on a random map, dimmed.
- **Window icon** (generated; no custom cursor).
- **UI scale** option.
- **Audio settings tab:** master / effects / UI volume, mute when unfocused.

---

## 15. Testing plan

- `luajit -bl` on every touched file. Lua 5.1 and web-safe code.
- **Movement and melee:** harnesses for jump height and apex, coyote and buffer windows, dash distance, corner correction, the melee stun and block outcomes, and edge damage and launches. The spawn harness runs on all maps.
- **Map objects:** per-object harnesses (damage + shove, block bounce, chain explosions, rope cut → fall, crate pickup roll, barrier timing in 3-player → 1v1). Loopback host and client comparison.
- **Rename:** the save folder migration (old folder → new on first launch), the build output names, and the workflow package checks.
- **Editors:** save → load → share code → import round trips, validation, screenshots. Every built-in map and card file loads, is edited, saved as an override, and reset back to the packed default.
- **Map overhaul:** the 4-spawn landing check on all 50 maps, a hazard-distance check, bot playthroughs, and screenshots for your review.
- **Card overhaul:** every card loads from its editor file, stacks (2 and 5 copies), and runs in the practice range without errors. A rarity and category count report.
- **Cards:** the old-vs-new equivalence harness, trigger no-loop checks, synergy checks, loopback card sync.
- **Bots:** hundreds of headless bot-vs-bot rounds on every map (no stuck bots, no errors, rounds end).
- **Netcode:** loopback with loss and latency; the client-predicted position stays within tolerance of the host; reconnect flow.
- **Mobile:** puppeteer with Chrome mobile emulation (touch, landscape), screenshots, and a LAN test with a phone-emulated browser client.
- **Release:** `./build.sh all`, AppImage launch, web smoke test, then tag **v0.5.0** (PROTOCOL 5, not compatible with v0.4).

---

## Backlog (not in this batch)

- **Hazards and objects:** gravity field zones, portals, falling stalactites, ice floors, tesla coils, mine crates, TNT with a fuse.
- **Modes:** King of the Hill, survival vs bot waves, mutators, map vote / ban, best-of sets.
- **Cards and picks:** curse cards, mid-round pickups (other than crate drops), environmental events, grenades.
- **Online:** a relay server.
- **Juice:** slow-motion final kill, final-kill camera zoom.
- **Options:** aim assist, toggle fire, a custom cursor.
