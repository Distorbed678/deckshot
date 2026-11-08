# Deckshot v0.5.1 plan

Status: **waiting for your review. Nothing has been implemented yet.** Edit anything here and tell me when to start.

Online play will not be compatible with v0.5.0: chat, the round timer, the lobby settings view, map votes, bans, King of the Hill and cosmetics change the wire format, so `session.PROTOCOL` goes from `"5"` to `"6"`.

**Size warning:** everything below ships together as v0.5.1, as you chose. It is now closer to a major release: rebuilding all 55 maps (item 20) and King of the Hill (item 25) are the two largest pieces, so nothing is playable by you until the whole list is done.

## Approved

- 51 one-tier card rarity moves (item 7).
- The barrier stays drawn after it stops at the final box.
- The first-run tutorial counts as part of How to Play.
- Mode and Rounds are set only in Settings > Gameplay.

## New defaults to check

These are my picks for details you haven't decided. Change any of them here.

1. **Map vote:** runs before every round, including the first, with a 10 second limit. Ties are random and bots vote randomly. On by default, as you asked, so every round gets this extra step.
2. **Card bans:** everyone bans 1 card at the same time before the starting cards, with a 30 second limit. Bans last for that match only.
3. **King of the Hill:** first side to 30 points wins the round. The hill moves every 20 seconds. Only one side inside scores; two sides inside contests it. Dead players respawn after 3 seconds. Losers pick cards as usual.
4. **KotH sudden death:** at zero the hill moves to the arena centre and stays there while the barrier closes.
5. **Unlocks:** 12 hats and 8 faces, a few available from the start, the rest earned from wins, rounds played, card picks and KotH wins. Purely visual.

## Items

### 1. What's New click-through
The menu buttons underneath take the click first, so Close also presses Credits or Quit. What's New becomes its own pushed screen. Only the top screen's widgets get input, so nothing behind it can be clicked.

### 2. Red edge and barrier
- The arena's left, right and bottom edges are no longer drawn in normal play. They still hurt and throw you back, with the existing impact burst.
- When the timer ends, a red barrier closes in from all four sides, including the top.
- The top edge starts above the screen, so a player in the air isn't snapped down and damaged the moment it starts.

### 3. Match settings in one place
Settings > Gameplay becomes a scrolling page with these sections:
- **Match:** Mode (Elimination or King of the Hill), Teams, Rounds to win, Friendly fire (when Teams is on), Cards offered, Picks per round, Starting cards, Pick timer, Allow discarding, Map vote and maps shown, Card bans.
- **Sudden death:** see item 11.
- **Rarity chances:** see item 7.
- **Content:** Card Library, Map Pool, Editor.
- **Reset**, with a confirmation.

Other changes:
- Rounds is removed from the lobby. The host's value is published when the host closes Settings.
- Local Play loses Mode, Rounds and Friendly fire. It keeps players, colours and teams, plus a one-line summary and a Settings button.
- Editor leaves the main menu. It is disabled while you are in a lobby or match, and its Back returns to Settings.

### 4. Card Library (Codex + Card Pool + Synergies)
One new screen under Settings > Gameplay replaces all three:
- Tabs for Cards and Synergies, with search and rarity / disabled filters.
- Card preview, rarity, enabled toggle, your pick statistics and related synergies.
- `screens/codex.lua`, `cards.lua` and `synergies.lua` are removed.

The main menu becomes: Local Play, Online Play, Customize (item 26), How to Play, Settings, Credits, Quit.

### 5. Controls explanations
Removed from the Online choice, LAN and lobby screens, the Local Play gamepad line, the Settings > Controls note, and the unused `Menu.controlsText`. I'll also audit the pause, practice and card-pick screens. The one-line "click a binding, then press a key" instruction stays, because it explains that screen rather than the controls.

### 6. Known overlaps
- **Settings > Video:** the note runs through the right column. It moves into the free space under Apply in the left column.
- **LAN lobby:** the browser link wraps onto Copy Browser Link. The link will be fitted to a single line, as part of the lobby redesign in item 10.

### 7. Rarities
**Chances** always total exactly 100%. Raising one lowers the others proportionally, in whole percents. New defaults are **55 / 28 / 12 / 4 / 1**. Saved settings are migrated: old defaults become the new ones, and customised values are scaled to 100.

**Cards** go from 40/44/33/19/14 to **55/45/28/14/8**:

| Move | Count | Cards |
|---|---|---|
| Legendary → Epic | 5 | Thunder God, Titan Grip, Reroll, Table Flip, Shrine of Order |
| Legendary → Rare | 1 | Fortress |
| Epic → Rare | 11 | Blitz, Chain Reaction, Repulsor, Stasis Field, Shield Generator, Swap Shot, Counter Puncher, Titan Rounds, Time Warp, Ricochet King, Overdrive |
| Rare → Epic (outlier) | 1 | Last Stand |
| Rare → Uncommon | 16 | Aerial Ace, Bone Breaker, Ground Pound, Panic Button, Riposte, Smoke Dash, Trickster, Uppercut, Bomb Squad, Retaliate, Piercing Rounds, Lock and Load, Sticky Mines, Overcharge, Momentum, Deadeye |
| Uncommon → Common | 16 | Hazard Proof, Edge Runner, Heavy Mag, Hot Barrel, Haymaker, Lunge, Iron Guard, Glass Fists, Pickpocket, Dash Reload, Sprint Block, Slipstream, Rapid Block, Wall Kicker, Marksman, Frost Guard |
| Common → Uncommon (outlier) | 1 | Glass Cannon |

Legendaries stay: Bullet Hell, Mirror Shot, Phoenix, Laser, Black Hole, Ghost Bullets, Sentry, Railgun.

Epics after the change: Juggernaut, Blood Pact, Orbiters, Nova, Cluster Bombs, Vampire, Hydra, Lucky Shot, Last Stand, Thunder God, Titan Grip, Reroll, Table Flip, Shrine of Order.

### 8. Practice under Local Play
Local Play opens a choice screen styled like Online's Steam / LAN choice: **Versus** or **Practice**. Practice leaves the main menu.

### 9. Lobby settings for everyone
- Steam, LAN and Local Play setup all have a Settings button.
- Clients keep their own Video, Audio and Controls. Their Gameplay tab shows the **host's** values, read-only, under a "Host's settings" banner.
- Card Library and Map Pool show the host's lists, including custom content (marked with the wrench), read-only. Editors can't be opened from there.
- The host sends rules and content lists when a player joins and whenever the host closes Settings. Client-side color and team display will use these too.

### 10. Chat
- Works in Steam and LAN lobbies, and in matches. In a match, the Chat key (default Enter, rebindable) opens a small box, and messages fade after a few seconds.
- While typing, the player's movement and firing are held so typed letters don't move you.
- The host checks each message: 120 characters at most, about 3 messages per 5 seconds, control characters and invalid text removed. The host names the sender, so names can't be spoofed.
- Join and leave lines appear in chat. History carries between lobby and match. Browser and phone players get the on-screen keyboard through a chat button.
- New message kind `CHAT = 18`.
- The lobby layout is redone: players on the left, join info above chat on the right, and Leave / Settings / Start along the bottom.

### 11. Sudden death
- A countdown at the top middle of the screen, in every match type and any player count. It turns red and ticks for the last 10 seconds, then the barrier starts.
- The old "30 seconds after a 1v1 in 3-4 player games" rule is removed.
- With 3-4 players the score chips leave a gap so the timer has room.
- It closes toward the arena centre and stops at the box. Bots learn to move inside it.
- Practice, the editor test and the menu background have no timer.

| Setting | Options | Default |
|---|---|---|
| Timer | Off, 1:00, 1:30, 2:00, 3:00, 4:00, 5:00, 7:00, 10:00 | 3:00 |
| Closing speed | Slow 40s, Normal 20s, Fast 10s | Normal |
| Final box size | Small 360×264, Medium 504×384, Large 768×528 (sized for the bigger arena) | Medium |
| Barrier damage | Low ×0.5, Normal, High ×2 | Normal |

"Off" replaces the old on/off barrier setting, and saved settings with the barrier off migrate to it.

### 12. Overlap sweep
A test harness walks every screen at Small, Normal and Large text, records each widget and text rectangle, flags intersections and takes screenshots, and I review those. This runs **after** the new font is in, because the font changes text widths. Long labels and values will shrink to fit their widgets.

### 13. Feel and polish
Original work only: no ROUNDS assets or look-alikes.
- **Better deaths:** characters burst into coloured chunks that bounce off the map, with a sound. This also shows for online clients.
- **Music:** original synthesized synthwave, generated in-game. A menu loop and a match loop, with an extra layer fading in at sudden death. New Music volume setting. The browser build gets a lighter version.
- **Match moments:** a short versus intro with player names, an animated round-win banner, and a winner podium showing the final build.
- **UI theme and font:** Russo One titles with a matching clean body font (open licence, credited in Credits), and shared colours, spacing and panels on every screen.
- **Logo and splash:** a drawn Deckshot logo on the menu, a short skippable splash and a matching window icon.
- **Animated menus:** buttons ease on hover and press, with staggered entrances.
- **Safety dialogs:** confirmations for leaving a match or lobby, Quit and every Reset button.
- **First-run tutorial:** a short guided session in the practice range using your actual key bindings. See decision 3.

### 14. README
- **Top:** logo banner, gameplay GIF, a one-line pitch, Play in Browser and Download buttons, highlights, screenshots.
- **Bottom:** a "For developers" section with collapsible blocks for building, architecture and netcode.
- **Media you supply**, in `docs/media/`: `gameplay.gif`, `card-pick.png`, `arena-1.png`, `arena-2.png`, `arena-3.png`, `editor.png`, `lobby.png`. I'll commit labelled placeholder images under those names so the page has no broken images. Replace the files and the README updates itself.
- `docs/` is excluded from the game package.

### 15. Update checker and auto-update (new)
**Flow:** on the main menu, a prompt shows the new version and its notes with **Update Now** and **Later**. Update Now shows download progress, verifies the SHA-256 published in the release, replaces the game and restarts it. Any failure leaves the current game untouched and links to the Releases page. It never prompts in a lobby or match. A "Check for updates" setting can turn it off.

- **Linux:** runs when launched as the AppImage. It downloads beside the existing file, verifies it, swaps it in with an atomic rename and relaunches.
- **Windows:** a running exe can't overwrite itself. It downloads and extracts the zip, then a small helper script waits for the game to exit, copies the new files in and relaunches. Save data isn't touched.
- **Notice only** (no install) for runs from source, folders the game can't write to (such as Program Files), and `.love` runs. The browser version does nothing.

Limits to know:
- **v0.5.0 players must install v0.5.1 by hand.** The first automatic update will be from v0.5.1 to whatever comes next.
- The checksum catches corrupted downloads but not a compromised GitHub account, because it comes from the same release. Signing could be added later.
- I can test the Linux path here against a fake local release. **The Windows path needs a real test on your Windows PC**, unless it runs properly under Wine here.

### 16. Practice card menu
Cards are sorted by rarity under rarity headings, with no gaps in the grid. Hovering a card shows its full card, including what it does, in a popup placed so it doesn't cover the card you're pointing at.

### 17. Bullet drop
Default `bulletGravity` goes from 0.25 to **0.45**, so a straight 1000-unit shot falls about 450 instead of 250. Bullet speed is unchanged. Bots already aim using this stat, and cards that change drop still multiply it.

### 18. Thunder God
Lightning strike delay goes from 0.75s to **0.35s**. Damage stays 30.

### 19. Card pick feel
- The flip slows from 0.2s to about 0.3s. Dealing speed stays the same.
- The hovered card slides up smoothly instead of jumping. Hover detection ignores the slide, so the card can't flicker at its bottom edge.
- Changing hover plays the same sound as hovering a menu button, for mouse, keyboard and gamepad. It plays only for the player choosing, not for people watching.

### 20. Bigger maps
- The arena becomes **1536×864**, 20% larger, with the whole arena always on screen. Players look about 17% smaller. Player size, speed and jump height don't change.
- The menus and HUD stay at their current size. Only the game world zooms out. This touches arena constants in the player, bot, world, map, barrier, Mirror Shot and editor code, and mouse and touch aiming.
- **Built-in maps are rebuilt, not just stretched.** All 55 are spread out to the new size, then each gets new platforms, hazards or breakables in the added space, keeping its character. Each map gets at least two new features.
- Every map must pass the editor validation and finish bot-vs-bot rounds. I'll make a contact sheet of all 55 for you to look over.
- **Custom maps and old share codes** still load: their layout is spread to the new size automatically, but nothing new is added to them. The map format moves to version 2.

### 21. Sound
- **Impact variety:** separate sounds for walls, players, blocks, breakables and heavy damage.
- **Tension audio:** sound and music muffle at low health and during death moments, with short musical stingers for round wins and match point.

### 22. Feel
- **Living characters:** eyes follow your aim, blink, squint when hurt and react to firing, jumping and dying. Online players see this on everyone.
- **Movement effects:** dust on jumps and landings, wall-slide sparks, dash trails.
- **Map atmosphere:** themed colours and layered parallax backgrounds by map group, with light ambient motion. The browser build gets a lighter version. None of it affects gameplay.

### 23. Map vote
A host option, **on by default**, with the number of maps shown adjustable from 2 to 6 (default 3). Maps come from the enabled Map Pool. If it's off, maps are picked randomly as they are now.

### 24. Card bans
A host option, **off by default**. Banned cards can't be offered to anyone that match, and everyone can see what was banned. Bots ban a strong card.

### 25. King of the Hill
A new mode that works in free-for-all and teams, using the rules under "New defaults to check". It needs respawning, scoring and an on-screen score display, hill locations worked out per map, snapshot data for online play, and bots that go for the hill.

### 26. Cosmetics and unlocks
A new **Customize** screen on the main menu for choosing a hat and face, showing how to unlock the rest. Progress is saved with your profile. Your choices are shown to everyone in online and LAN games. All designs are original.

## Order of work

1. Foundations: scrolling region, read-only widgets, confirmation dialog, theme and font.
2. Arena: the 1536×864 world and camera (item 20 code), because later work depends on it.
3. Menus and settings: items 1, 3, 4, 5, 8, 16.
4. Gameplay: items 2, 7, 11, 17, 18, including bots.
5. Rebuild all 55 maps (item 20 content).
6. Online: items 9, 10, and the protocol bump.
7. New match features: items 23, 24, 25, 26.
8. Polish: items 13, 19, 21, 22.
9. Auto-update: item 15.
10. Item 6 and the item 12 sweep.
11. README, `CLAUDE.md`, What's New notes (item 14).

## Checks before release

- Syntax check on every file.
- Bot-vs-bot rounds on every rebuilt map, with the timer on, in both Elimination and King of the Hill.
- Loopback online test and a real two-process LAN test, including chat, read-only settings, map vote, bans, King of the Hill and cosmetics.
- Headless browser test of the web build, including phone layout.
- Screenshots of every changed screen.
- Local `./build.sh all` smoke test, then version 0.5.1, commit, push and the `v0.5.1` tag.
