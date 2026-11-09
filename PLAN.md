# Deckshot v0.5.2 plan

Status: **implemented, not released.** Name tags show above every player in team matches.

v0.5.2 also carries the unreleased work already on `main` (card art, rarity flair, Match Recap, controller icons, landing page). The version number goes from 0.6.0 back to 0.5.2. **Nothing gets released until you say so.** I'll commit and push as usual unless you'd rather I didn't.

`session.PROTOCOL` goes from `"6"` to `"7"`, because the rules and lobby data change and voice adds a message. v0.5.2 players won't be able to play online with v0.5.1.

## Please check these

1. **Synergy removal costs 31 bonuses.** 9 of the 40 become natural interactions (table in item 6). The other 31 only added stats, so they go with no replacement.
2. **Teammates look identical.** Same colour means same team, so teammates can't be told apart by colour. I suggest a small name tag above teammates during team matches.
3. **Self-damage and bots.** With friendly fire on, bots don't know their own explosions can hurt them, so they'll sometimes blow themselves up. I'd make them avoid firing explosives point-blank, and leave the rest. Friendly fire stays off by default.
4. **Bullets you've just fired.** With friendly fire on, your own bullet can't hit you for its first 0.15 seconds, or every shot would hit you at the muzzle.
5. **Combo Artist achievement.** It counts synergies, and achievements unlock cosmetics by list position, so removing it would change who owns what. I suggest replacing it in place with "Deck Builder: finish matches with 5 or more different cards". Progress on the old count is dropped.
6. **The AppImage adds a menu entry.** The taskbar fix makes the game create a "Deckshot" entry in your applications menu (item 8).
7. **Max team size tops out at 3.** With 4 players at most, a team of 4 would leave nobody to fight.
8. **Anyone who installed 0.6.0** during the few minutes it was public won't be offered v0.5.2 automatically, because 0.5.2 looks older. They'd need to download it by hand.

## Items

### 1. Voice chat
Steam and LAN, in lobbies and matches, desktop only.

- **Off until enabled.** Settings > Audio gets Voice (Off / Push to talk / Open mic), microphone choice, a live mic level with the open-mic threshold, and voice volume.
- **Controls:** a rebindable push-to-talk key, V by default, and right stick click on a gamepad.
- **In use:** a speaking icon beside lobby names and above players in matches, and a mute button per player in the lobby.
- **How it works:** LÖVE records the mic at 16 kHz, a small codec compresses it about 4:1, and clients send to the host, which forwards to everyone else. Each speaker plays through their own audio stream with a short buffer to smooth out delay. Steam and LAN share this one code path. Voice is dropped rather than resent when the connection falls behind.
- **Browser players** can't talk or listen. Their lobby row shows no voice icon.
- **Can't fully test here:** I can run two game copies with synthetic audio over the network, but a real microphone and real speech need you. Please try it with someone before release.

### 2. Teams by colour, friendly fire
- **Colour is team.** Every player's team is their colour. Players with the same colour share points and can't hurt each other unless friendly fire is on. The Red/Blue system and the 2v2 option are removed.
- **Host settings:** Teams becomes Free-for-all / Teams. Free-for-all is a team limit of 1. Choosing Teams shows **Max team size** (2 or 3).
- **Lobby:** a colour swatch goes dim when its team is full. The host can change a bot's colour by clicking its row. Start needs at least two colours and no team over the limit.
- **Names:** banners and the scoreboard say "Orange Team", from the colour's name.
- **Friendly fire works in every mode.** When on, it covers teammates and yourself: your bullets, explosions, shards and mines can all hit you.
- Old settings with 2v2 on convert to Teams with a max size of 2.

### 3. Tutorial for every control scheme
The tutorial opens with the control picker from item 7, and every step shows the right control for what you chose, including icons on a gamepad. Mouse players get an added "aim with the mouse" step, and the mouse step list uses your online key bindings. Gamepad is only offered when one is connected.

### 4. Saw
The saw is a spiky outline filled as if it were a convex shape, which leaves parts of it missing. I'll draw it as a fan of triangles from the centre, so it's a complete blade. This also fixes the saws on blade arms, and I'll check other hazards for the same bug.

### 5. Local Play screen
Rebuilt to match the online lobby:
- Left: "Players n / 4" with a character preview per row, input device, and a remove button.
- Below that: colour swatches, plus add buttons for keyboard, gamepad and bots at each difficulty.
- Right: a panel summarising the match rules.
- Bottom: Start Match, Settings, Back, in the lobby's positions.
- Teams follow item 2. Your saved setup carries over.

### 6. Remove synergies
**Removed:** the system, all 40 files, the Synergies tab in the Library and editor, the card footer line, the Gameplay options, bot scoring and the SYNERGIES network message. Custom synergy files stay on disk but are ignored. The README and landing page stop advertising them.

**Added:** effects that simply work together, with no new stats. Two general rules:
- **A bullet's effects carry into everything it makes.** Poison and frost apply through explosions, bounce blasts, shards, Hydra heads and cluster blasts.
- **Explosive bullets explode whenever they hit something**, including each bounce and each player they pierce. Bounce and pierce blasts are smaller, about 30% damage, so they stay fair.

| Was | Now |
|---|---|
| Bouncing Blasts | Explosive + any bounces: every bounce explodes |
| *(new)* | Explosive + Piercing: an explosion at each player pierced |
| Toxic Shrapnel | Poison carries into shards |
| Frozen Field | Frost makes Static Field slow enemies |
| Guided Ricochet | Homing keeps working after a bounce |
| Pinball | Split bullets keep their remaining bounces |
| Booby Trap | Mines use your explosion radius and cluster |
| Twin Turrets | The Sentry's shots carry your bullet effects |
| Blaze of Glory | Reviving with Phoenix still sets off Martyr |
| Meteor | Ground Pound hits harder the farther you fall |

Cards involved get a note saying what they combine with, in place of the old "Synergy:" line. New chain effects stay behind the existing `isChild` and `isCluster` guards so nothing multiplies forever.

### 7. Control choice in Practice
Practice opens a picker: Keyboard, Mouse and keyboard (your online bindings), Gamepad (when connected), Touch (on touch devices). Your last choice is remembered. The same picker starts the tutorial. Mouse aiming and the crosshair will work in local matches for this.

### 8. Taskbar icon (AppImage)
Most likely cause: the game identifies itself as LÖVE, so the desktop shows LÖVE's icon. The fix has two parts:
- The AppImage launcher sets the game's window class to `deckshot`.
- When run as an AppImage on Linux, the game installs a `deckshot.desktop` entry and icon in your user folders, and updates the entry if the file moves.

**Needs you to confirm:** I can't see your taskbar from here, so you'd need to check it after a build. Windows already has its icon in the `.exe`.

### 9. Black hole
A black hole's center (about 40px) deals 20 damage per second to everyone inside, including its owner. Blocking doesn't stop it. Gravity Block's wells count too. Kills credit the hole's owner, and damage is applied only on the host.

## Order of work
Small fixes first (4, 9, 8), then Practice and the tutorial (7, 3), teams (2), Local Play (5, which depends on teams), synergies (6), and voice last (1).

## Checks before calling it done
Syntax check on every file, bot-vs-bot rounds on all 55 maps in free-for-all and teams, network tests over loopback for the new team and rules data, a real LAN run with two processes for voice with synthetic audio, a headless browser run of the web build, and screenshots of every changed screen. Then the README, `CLAUDE.md` and What's New notes.
