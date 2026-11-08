# Deckshot v0.5.1 rework plan

Status: **waiting for your review. Nothing in this plan has been implemented yet.** Edit anything here and tell me when to start.

This all ships in v0.5.1, which is still unreleased. The network protocol stays at `"6"`, because no public build has used it yet.

## Please check these

1. **Own look, not a copy.** I'll build the layouts and mechanics you described: corner HUD, character aiming at cards, pie-shaped progress, cosmetic slots. The art, colours, wording and character designs will be Deckshot's own rather than a match for ROUNDS.
2. **Confirm key on the card screen.** I read your answer as: local players confirm with their current selection key (fire) or their jump key, and online confirms with your Jump binding, Space by default. A mouse click won't confirm anything.
3. **Phones keep tapping cards.** They have no left/right keys, so without this they couldn't pick at all. Mouse input is off on every other device.
4. **Matches get about twice as long.** With 2 sub-round wins per point and "first to 5" points, a match is at least 10 sub-rounds. I suggest lowering the default to first to 3. Tell me if you'd rather keep 5.
5. **Taller characters.** With the body riding above its legs, characters are about 14 units taller for terrain. The tightest gap on any built-in map is 72 units and a default character will be about 54, so they fit. Cards that make you much bigger may scrape in tight spots.
6. **Earned cosmetics carry over.** Your current win, kill and card counts will count toward the new achievements, so you start with some unlocked.

## Items

### 1. Transition speed
Every transition goes to the midpoint between the earlier and current values.

| Transition | Earlier | Now | New |
|---|---|---|---|
| Screen change | 0.35s | 0.6s | 0.47s |
| Arena slide | 0.55s | 0.85s | 0.7s |
| Card deal stagger | 0.07s | 0.13s | 0.1s |
| Card deal time | 0.28s | 0.55s | 0.41s |
| Card flip | 0.32s | 0.42s | 0.37s |
| Round-win pause | 1.6s | 2.1s | 1.85s |
| Map vote result | 1.1s | 1.7s | 1.4s |

The menu button entrances, round banner and map vote fade-in also go to their midpoints. The splash and match loading screens keep at least 1 second of loading, as you asked.

### 2, 3, 5, 11. Noodle limbs rebuilt
- **Standing:** the body rides one leg-length above the ground, and the legs visibly hold it up. Terrain collision extends below the body to the feet. Bullets, melee and hazards still only hit the round body. Bots, spawns, edges and the barrier all use the new feet position.
- **No more stuck feet:** a foot can never trail further than its reach. It steps as soon as it falls behind, and step length follows your speed, so landing and running can't leave a leg behind.
- **Noodles:** longer, thin, curved limbs that swing and overshoot, with arms and legs about 30% longer.
- **Firing:** the gun arm kicks back and springs into place, harder for bigger shots. This is cosmetic only.
- **Squash and stretch removed** from the body.
- **Jump and land:** the legs tuck up when you jump, and pull up on landing, so impacts read better.

### 4. Map vote time
It uses the same value as the card pick timer. When that's Off, which is always the case in local play, the vote waits until everyone has voted. Bots vote on their own.

### 6, 10. Card picking screen
- The arena is gone, with a dark themed backdrop.
- A large version of the picker's character stands at the bottom, with their hat, eyes and mouth, and their block circle in the left hand.
- Cards fan in an arc above the character. The right arm stretches to the selected card and follows it.
- Selection uses left/right only, with cards still turning over as you reach them. Discard stays on the Down key.
- The mouse no longer hovers or selects (see items 2 and 3 above for confirm keys and phones).
- Online, everyone watches the picker's character and arm.

### 7. In-round HUD
- **Top left:** a row of points for each player or team. The next point's dot shows sub-round progress as filled pie segments.
- **Top right:** each player's cards as small boxes with 2-letter initials, in their colour, wrapping as they fill. Hovering one shows the full card.
- The round timer stays top middle. King of the Hill bars sit under it.

### 8. Sub-rounds
- New host setting in Settings > Gameplay: **Wins per point**, 1 to 5, default 2.
- First player or team to that many sub-round wins gets a point, everyone else picks a card, all progress resets, and the next map starts.
- Between sub-rounds the same map restarts with no map vote or slide. Health, breakables, hazards and the sudden-death timer all reset.
- A draw just replays the sub-round. King of the Hill uses sub-rounds too.
- **Progress overlay, about 1.5 seconds:** each player's circle cut into n segments, with the new segment filling in and a short line such as "Blue is one win away".

### 9. Explosions
The circle is replaced by chunky cartoon smoke puffs that swell and fade, a bright fiery core, flying debris and bloom. It covers bullets, barrels, gas, mines and explosive triggers, follows the Particles setting, and shows for online clients. Blast damage and radius don't change.

### 12. Achievements and cosmetics
- About 60 cosmetics in four slots: roughly 20 hats, 15 eyes, 15 mouths and 10 details. Some are free from the start and the rest are earned. All are original designs.
- **A mouth by default**, which changes with your expression.
- About 40 achievements that unlock cosmetics: match wins, kills, card and synergy milestones, King of the Hill, block and melee feats, and map variety. Local play, bots and online all count.
- Earned achievements appear on the match-over screen and the next menu visit, and there's a full list on Customize.
- Customize is rebuilt with tabs per slot and a live character preview.

### 13. Chat bubbles
In-match messages also appear in a bubble above the sender for about 4 seconds, following them, with long messages wrapped. They show on every player's screen.

### Your extras
- **Name tags** above players online.
- **Reactive expressions:** angry when hurt, grinning on a kill, shocked at low health. These work online using existing data.
- **Full characters in the lobby** with noodle limbs and an idle wobble.

## Order of work

1. Transition midpoints and map vote timer.
2. Standing, noodle limbs, recoil, jump and land.
3. Sub-rounds, the setting, the overlay and online data.
4. New HUD.
5. Card picking screen and key-only input.
6. Explosions.
7. Cosmetic slots, mouths, expressions, name tags, lobby characters.
8. Achievements and the new Customize screen.
9. Chat bubbles.
10. What's New notes, `CLAUDE.md` and README updates.

## Checks

- Syntax check on every file.
- Bot rounds on all 55 maps in both modes with the new standing height and sub-rounds, plus map validation.
- Loopback and two-process LAN tests covering sub-rounds, new HUD data, explosions, bubbles and cosmetics.
- The overlap and tight-spacing sweep at all text sizes, including the new screens.
- Screenshots of the card screen, HUD, overlay and Customize.
- Browser build test, then local `./build.sh all`.
- Commit locally. No push or tag until you say so.
